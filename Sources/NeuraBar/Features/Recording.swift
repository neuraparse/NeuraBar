import Foundation
import SwiftUI
import AVFoundation
import AppKit

// MARK: - Models

enum RecordingKind: String, Codable {
    case audio, screen
}

struct Recording: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let kind: RecordingKind
    let filePath: String
    let createdAt: Date
    var durationSeconds: Double
    var sizeBytes: Int64

    var url: URL { URL(fileURLWithPath: filePath) }

    var displayName: String { url.lastPathComponent }

    static func directory() -> URL {
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("NeuraBar Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Produce a unique filename for a new recording of the given kind.
    /// Pure function — exposed for tests.
    static func newFilePath(kind: RecordingKind,
                            now: Date = Date(),
                            directory: URL = directory()) -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        let stamp = df.string(from: now)
        let ext = kind == .audio ? "m4a" : "mov"
        let prefix = kind == .audio ? "audio" : "screen"
        return directory.appendingPathComponent("\(prefix)-\(stamp).\(ext)")
    }
}

// MARK: - Store

struct RecordingOptions: Codable, Equatable {
    var includeMicrophone: Bool = true
    var captureCursor: Bool = true
    var postNotification: Bool = true

    static let `default` = RecordingOptions()

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        includeMicrophone = (try? c.decode(Bool.self, forKey: .includeMicrophone)) ?? true
        captureCursor = (try? c.decode(Bool.self, forKey: .captureCursor)) ?? true
        postNotification = (try? c.decode(Bool.self, forKey: .postNotification)) ?? true
    }
}

final class RecordingStore: NSObject, ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var isRecordingAudio: Bool = false
    @Published var isRecordingScreen: Bool = false
    @Published var currentDuration: Double = 0
    @Published var audioLevel: Float = 0          // 0…1 for the live meter
    @Published var lastError: String?
    @Published var options: RecordingOptions {
        didSet { Persistence.save(options, to: "recording_options.json") }
    }

    private var audioRecorder: AVAudioRecorder?
    private var currentAudioURL: URL?
    private var currentAudioStart: Date?

    private var screenProcess: Process?
    private var currentScreenURL: URL?
    private var currentScreenStart: Date?

    private var tickTimer: Timer?
    private let file = "recordings.json"

    override init() {
        self.options = Persistence.load(RecordingOptions.self, from: "recording_options.json")
            ?? RecordingOptions()
        super.init()
        if let saved = Persistence.load([Recording].self, from: file) {
            self.recordings = saved.filter { FileManager.default.fileExists(atPath: $0.filePath) }
        }
    }

    // MARK: - Input device enumeration (read-only)

    /// Available audio input devices — shown for transparency so the user
    /// knows which mic the system default is using. AVAudioRecorder uses the
    /// system default input; to record from a specific device the user must
    /// change it in System Settings → Sound.
    static var availableMicrophones: [(id: String, name: String)] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        return session.devices.map { ($0.uniqueID, $0.localizedName) }
    }

    static var currentMicrophoneName: String? {
        AVCaptureDevice.default(for: .audio)?.localizedName
    }

    // MARK: Audio

    func startAudio() {
        guard !isRecordingAudio else { return }
        let url = Recording.newFilePath(kind: .audio)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            currentAudioURL = url
            currentAudioStart = Date()
            isRecordingAudio = true
            startTick()
            lastError = nil
        } catch {
            lastError = "Audio: \(error.localizedDescription)"
        }
    }

    func stopAudio() {
        guard isRecordingAudio else { return }
        audioRecorder?.stop()
        let url = currentAudioURL
        let start = currentAudioStart ?? Date()
        audioRecorder = nil
        currentAudioURL = nil
        currentAudioStart = nil
        isRecordingAudio = false
        audioLevel = 0
        stopTickIfIdle()

        if let url = url {
            let size = fileSize(at: url)
            let dur = Date().timeIntervalSince(start)
            let rec = Recording(
                kind: .audio,
                filePath: url.path,
                createdAt: start,
                durationSeconds: dur,
                sizeBytes: size
            )
            recordings.insert(rec, at: 0)
            persist()
            notifyRecordingSaved(rec)
        }
    }

    // MARK: Screen

    /// Start a screen recording using the system `screencapture -v` tool.
    /// Flags are driven by `options`:
    ///   -v    video mode
    ///   -x    silent (no shutter beep)
    ///   -C    capture cursor         (options.captureCursor)
    ///   -g    capture system + mic audio into the video track
    ///         (options.includeMicrophone)
    func startScreen() {
        guard !isRecordingScreen else { return }
        let url = Recording.newFilePath(kind: .screen)
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"

        var args = ["-v", "-x"]
        if options.captureCursor { args.append("-C") }
        if options.includeMicrophone { args.append("-g") }
        args.append(url.path)
        task.arguments = args

        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            screenProcess = task
            currentScreenURL = url
            currentScreenStart = Date()
            isRecordingScreen = true
            startTick()
            lastError = nil
        } catch {
            lastError = "Screen: \(error.localizedDescription)"
        }
    }

    func stopScreen() {
        guard isRecordingScreen, let task = screenProcess else { return }
        // screencapture -v stops cleanly on SIGINT and flushes the file.
        task.interrupt()
        // Give it up to ~1.2s to write the file before we snapshot metadata.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.finishScreen()
        }
    }

    private func finishScreen() {
        screenProcess = nil
        let url = currentScreenURL
        let start = currentScreenStart ?? Date()
        currentScreenURL = nil
        currentScreenStart = nil
        isRecordingScreen = false
        stopTickIfIdle()

        if let url = url, FileManager.default.fileExists(atPath: url.path) {
            let size = fileSize(at: url)
            let dur = Date().timeIntervalSince(start)
            let rec = Recording(
                kind: .screen,
                filePath: url.path,
                createdAt: start,
                durationSeconds: dur,
                sizeBytes: size
            )
            recordings.insert(rec, at: 0)
            persist()
            notifyRecordingSaved(rec)
        } else {
            lastError = "Screen recording file not found — permission needed?"
        }
    }

    // MARK: - List ops

    func reveal(_ recording: Recording) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.url])
    }

    func delete(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.url)
        recordings.removeAll { $0.id == recording.id }
        persist()
    }

    func clearAll() {
        for rec in recordings {
            try? FileManager.default.removeItem(at: rec.url)
        }
        recordings.removeAll()
        persist()
    }

    // MARK: - Helpers

    private func startTick() {
        currentDuration = 0
        tickTimer?.invalidate()
        // 10 Hz while audio is recording so the level meter feels responsive;
        // 2 Hz otherwise is plenty for the duration counter.
        let interval = isRecordingAudio ? 0.1 : 0.5
        tickTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isRecordingAudio, let s = self.currentAudioStart {
                self.currentDuration = Date().timeIntervalSince(s)
                self.audioRecorder?.updateMeters()
                // avgPower is in dB, typical range -60…0. Map to 0…1.
                let db = self.audioRecorder?.averagePower(forChannel: 0) ?? -60
                let normalized = max(0, min(1, (db + 60) / 60))
                self.audioLevel = Float(normalized)
            } else if self.isRecordingScreen, let s = self.currentScreenStart {
                self.currentDuration = Date().timeIntervalSince(s)
            }
        }
    }

    private func notifyRecordingSaved(_ rec: Recording) {
        Task { @MainActor in
            MenuBarStatusCoordinator.shared.flash(.recordingSaved)
        }
        guard options.postNotification else { return }
        let body = "\(rec.displayName) · \(Self.formatDuration(rec.durationSeconds))"
        NotificationService.post(
            title: rec.kind == .audio ? L.t(.record_notif_audioSaved) : L.t(.record_notif_screenSaved),
            body: body
        )
    }

    private func stopTickIfIdle() {
        if !isRecordingAudio && !isRecordingScreen {
            tickTimer?.invalidate()
            tickTimer = nil
            currentDuration = 0
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func persist() {
        Persistence.save(recordings, to: file)
    }

    /// Format seconds as "m:ss" or "h:mm:ss". Pure, used in UI and exposed for
    /// tests.
    static func formatDuration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Human-friendly byte count. Exposed for tests.
    static func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useAll]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

extension RecordingStore: AVAudioRecorderDelegate {
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        lastError = "Audio encode error: \(error?.localizedDescription ?? "unknown")"
        isRecordingAudio = false
        stopTickIfIdle()
    }
}
