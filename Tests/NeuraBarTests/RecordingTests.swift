import XCTest
@testable import NeuraBar

final class RecordingTests: NBTestCase {

    // MARK: - Recording model

    func testDirectoryIsCreated() {
        let dir = Recording.directory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertTrue(dir.path.hasSuffix("NeuraBar Recordings"))
    }

    func testAudioFilePathHasCorrectShape() {
        let fixed = Date(timeIntervalSince1970: 1_713_000_000)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-test-\(UUID())")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let url = Recording.newFilePath(kind: .audio, now: fixed, directory: tmp)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("audio-"))
        XCTAssertEqual(url.pathExtension, "m4a")
        XCTAssertEqual(url.deletingLastPathComponent().path, tmp.path)
    }

    func testScreenFilePathHasCorrectShape() {
        let fixed = Date(timeIntervalSince1970: 1_713_000_000)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-test-\(UUID())")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let url = Recording.newFilePath(kind: .screen, now: fixed, directory: tmp)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("screen-"))
        XCTAssertEqual(url.pathExtension, "mov")
    }

    func testFilePathsAreUniquePerSecond() {
        // Different timestamps produce different paths; same second yields same
        // deterministic path (callers must wait a second or override).
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-test-\(UUID())")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let t1 = Date(timeIntervalSince1970: 1_713_000_000)
        let t2 = Date(timeIntervalSince1970: 1_713_000_001)
        let p1 = Recording.newFilePath(kind: .audio, now: t1, directory: tmp)
        let p2 = Recording.newFilePath(kind: .audio, now: t2, directory: tmp)
        XCTAssertNotEqual(p1, p2)
    }

    // MARK: - Formatting helpers

    func testFormatDurationHandlesSubMinute() {
        XCTAssertEqual(RecordingStore.formatDuration(0), "0:00")
        XCTAssertEqual(RecordingStore.formatDuration(7), "0:07")
        XCTAssertEqual(RecordingStore.formatDuration(59), "0:59")
    }

    func testFormatDurationHandlesMinutes() {
        XCTAssertEqual(RecordingStore.formatDuration(60), "1:00")
        XCTAssertEqual(RecordingStore.formatDuration(125), "2:05")
        XCTAssertEqual(RecordingStore.formatDuration(3599), "59:59")
    }

    func testFormatDurationHandlesHours() {
        XCTAssertEqual(RecordingStore.formatDuration(3600), "1:00:00")
        XCTAssertEqual(RecordingStore.formatDuration(3661), "1:01:01")
        XCTAssertEqual(RecordingStore.formatDuration(7260), "2:01:00")
    }

    func testFormatDurationHandlesNegative() {
        XCTAssertEqual(RecordingStore.formatDuration(-5), "0:00")
    }

    func testFormatBytesReadable() {
        // ByteCountFormatter output is locale-dependent but should always
        // include a "B" suffix and a numeric prefix.
        let out = RecordingStore.formatBytes(1024)
        XCTAssertTrue(out.contains("B"))
        XCTAssertFalse(out.isEmpty)
    }

    // MARK: - Store state

    func testInitialStateIsIdle() {
        let s = RecordingStore()
        XCTAssertFalse(s.isRecordingAudio)
        XCTAssertFalse(s.isRecordingScreen)
        XCTAssertEqual(s.currentDuration, 0)
        XCTAssertNil(s.lastError)
    }

    func testDropsRecordingsWithMissingFile() {
        // Seed the store with a phantom recording file whose path doesn't exist.
        let phantom = Recording(
            id: UUID(),
            kind: .audio,
            filePath: "/tmp/does-not-exist-\(UUID()).m4a",
            createdAt: Date(),
            durationSeconds: 3,
            sizeBytes: 100
        )
        Persistence.save([phantom], to: "recordings.json")

        let s = RecordingStore()
        XCTAssertTrue(s.recordings.isEmpty,
                      "Recordings whose files vanished should be dropped on load")
    }

    func testDeleteRemovesFromListAndDisk() throws {
        // Create an actual tiny file, register it, then call delete.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-delete-\(UUID()).m4a")
        try Data([0x00]).write(to: tmp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))

        let rec = Recording(
            id: UUID(),
            kind: .audio,
            filePath: tmp.path,
            createdAt: Date(),
            durationSeconds: 1,
            sizeBytes: 1
        )
        let s = RecordingStore()
        s.recordings = [rec]
        s.delete(rec)
        XCTAssertTrue(s.recordings.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path))
    }

    func testClearAllRemovesEverything() throws {
        let tmp1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-clear1-\(UUID()).m4a")
        let tmp2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-clear2-\(UUID()).mov")
        try Data([0x00]).write(to: tmp1)
        try Data([0x00]).write(to: tmp2)
        let s = RecordingStore()
        s.recordings = [
            Recording(kind: .audio, filePath: tmp1.path, createdAt: Date(),
                      durationSeconds: 1, sizeBytes: 1),
            Recording(kind: .screen, filePath: tmp2.path, createdAt: Date(),
                      durationSeconds: 1, sizeBytes: 1)
        ]
        s.clearAll()
        XCTAssertTrue(s.recordings.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp1.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp2.path))
    }
}
