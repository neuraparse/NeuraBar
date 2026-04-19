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

final class RecordingStore: NSObject, ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var isRecordingAudio: Bool = false
    @Published var isRecordingScreen: Bool = false
    @Published var currentDuration: Double = 0   // live timer, seconds
    @Published var lastError: String?

    private var audioRecorder: AVAudioRecorder?
    private var currentAudioURL: URL?
    private var currentAudioStart: Date?

    private var screenProcess: Process?
    private var currentScreenURL: URL?
    private var currentScreenStart: Date?

    private var tickTimer: Timer?
    private let file = "recordings.json"

    override init() {
        super.init()
        if let saved = Persistence.load([Recording].self, from: file) {
            // Drop any recordings whose file has been deleted on disk.
            self.recordings = saved.filter { FileManager.default.fileExists(atPath: $0.filePath) }
        }
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
        }
    }

    // MARK: Screen

    /// Start a screen recording using the system `screencapture -v` tool —
    /// avoids ScreenCaptureKit's async ceremony for a simple non-interactive
    /// flow, and the first run automatically prompts for permission.
    func startScreen() {
        guard !isRecordingScreen else { return }
        let url = Recording.newFilePath(kind: .screen)
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        // -v = video, -x = silent, -C = capture cursor
        task.arguments = ["-v", "-x", "-C", url.path]
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
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isRecordingAudio, let s = self.currentAudioStart {
                self.currentDuration = Date().timeIntervalSince(s)
            } else if self.isRecordingScreen, let s = self.currentScreenStart {
                self.currentDuration = Date().timeIntervalSince(s)
            }
        }
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
