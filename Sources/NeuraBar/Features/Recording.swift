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

/// What the user wants to capture. Selected from the Start Recording sheet.
enum RecordingSource: String, Equatable {
    case fullScreen
    case area
    case systemPicker  // hands off to the built-in macOS Screenshot.app

    var icon: String {
        switch self {
        case .fullScreen:   return "rectangle.on.rectangle"
        case .area:         return "selection.pin.in.out"
        case .systemPicker: return "macwindow.and.cursorarrow"
        }
    }

    var titleKey: Loc {
        switch self {
        case .fullScreen:   return .record_src_fullScreen
        case .area:         return .record_src_area
        case .systemPicker: return .record_src_systemPicker
        }
    }

    var subtitleKey: Loc {
        switch self {
        case .fullScreen:   return .record_src_fullScreen_hint
        case .area:         return .record_src_area_hint
        case .systemPicker: return .record_src_systemPicker_hint
        }
    }
}

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

    /// Attempts to start an audio recording. Returns false if permission is
    /// denied / not yet determined so the UI can show the permission banner.
    /// The caller should call `requestMicAccess()` first (async) to prompt
    /// the user before reaching this.
    @discardableResult
    func startAudio() -> Bool {
        guard !isRecordingAudio else { return false }
        // Belt-and-braces: if we somehow reach here without mic access,
        // bail out cleanly instead of recording a silent file.
        guard PermissionsService.microphone == .authorized else {
            lastError = "Microphone permission not granted."
            return false
        }
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
            return true
        } catch {
            lastError = "Audio: \(error.localizedDescription)"
            return false
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

    /// Build the `screencapture` argument list for a given source + options.
    /// Pure — lets tests verify flag plumbing without running the binary.
    static func screencaptureArguments(
        source: RecordingSource,
        outputPath: String,
        options: RecordingOptions
    ) -> [String] {
        var args = ["-v", "-x"]
        if options.captureCursor { args.append("-C") }
        if options.includeMicrophone { args.append("-g") }
        switch source {
        case .fullScreen:
            break
        case .area:
            // -i prompts for interactive rect selection before the capture
            // begins. Combined with -v this lets the user drag a region to
            // record.
            args.append("-i")
        case .systemPicker:
            // Handled out-of-band — we don't launch screencapture for this
            // path. The caller should open Screenshot.app instead.
            break
        }
        args.append(outputPath)
        return args
    }

    /// Attempts to start a screen recording. Returns false when permission
    /// is not yet granted so the UI can surface the permission banner
    /// instead of silently spawning a capture that macOS will drop.
    @discardableResult
    func startScreen(source: RecordingSource = .fullScreen) -> Bool {
        guard !isRecordingScreen else { return false }
        // `screencapture` on macOS 26 doesn't support interactive area
        // selection + video together (-i and -v conflict). Route area
        // requests through the OS Screenshot toolbar, which handles all
        // window + area + full-screen video modes with its own permissions
        // and UI. systemPicker already goes there too.
        if source == .systemPicker || source == .area {
            launchSystemPicker()
            return true
        }
        // Pre-flight screen recording permission. `screencapture -v`
        // inherits nothing from the parent's entitlements on macOS 26, so
        // NeuraBar itself must be authorized in System Settings.
        guard PermissionsService.screenRecording == .authorized else {
            PermissionsService.requestScreenRecording()
            lastError = "Screen recording permission not granted."
            return false
        }
        let url = Recording.newFilePath(kind: .screen)
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = Self.screencaptureArguments(
            source: source,
            outputPath: url.path,
            options: options
        )
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
            return true
        } catch {
            lastError = "Screen: \(error.localizedDescription)"
            return false
        }
    }

    /// Open the macOS Screenshot.app tool (Cmd+Shift+5 equivalent) — user
    /// picks window/area/full + starts recording there. We don't track
    /// output, macOS saves the file to its own default location.
    private func launchSystemPicker() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.open(url)
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
