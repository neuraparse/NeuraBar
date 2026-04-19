import XCTest
@testable import NeuraBar

/// End-to-end contract tests for the Record feature. We can't actually spawn
/// screen capture in tests (macOS would refuse and/or block for permission),
/// but we can verify the code paths the UI relies on: permission-guarded
/// starts, source routing, option persistence, and state transitions.
@MainActor
final class RecordFlowTests: NBTestCase {

    // MARK: - Start/stop symmetry

    func testIdleStateOnFreshStore() {
        let s = RecordingStore()
        XCTAssertFalse(s.isRecordingAudio)
        XCTAssertFalse(s.isRecordingScreen)
        XCTAssertEqual(s.currentDuration, 0)
        XCTAssertEqual(s.audioLevel, 0)
        XCTAssertNil(s.lastError)
    }

    func testStartScreenWhileAudioIsIdle() {
        let s = RecordingStore()
        // If permission exists on the dev machine, startScreen succeeds.
        // Either way the boolean signal must be consistent — either we
        // recorded and isRecordingScreen is true, or we were blocked and
        // lastError is populated.
        let started = s.startScreen(source: .fullScreen)
        if started {
            XCTAssertTrue(s.isRecordingScreen)
            s.stopScreen()
        } else {
            XCTAssertNotNil(s.lastError)
        }
    }

    func testStopScreenWhenNotRecordingIsNoOp() {
        let s = RecordingStore()
        // Should not crash, should not toggle state.
        s.stopScreen()
        XCTAssertFalse(s.isRecordingScreen)
    }

    func testStopAudioWhenNotRecordingIsNoOp() {
        let s = RecordingStore()
        s.stopAudio()
        XCTAssertFalse(s.isRecordingAudio)
    }

    // MARK: - Source routing

    func testSystemPickerAndAreaBothHandOffToMacOS() {
        // Neither mode should mark us as actively recording — macOS
        // Screenshot.app handles capture and file output.
        let s = RecordingStore()
        XCTAssertTrue(s.startScreen(source: .systemPicker))
        XCTAssertFalse(s.isRecordingScreen)

        let s2 = RecordingStore()
        XCTAssertTrue(s2.startScreen(source: .area))
        XCTAssertFalse(s2.isRecordingScreen)
    }

    func testStartScreenWhileAlreadyRecordingReturnsFalse() {
        let s = RecordingStore()
        // Force the flag without actually launching a process.
        s.isRecordingScreen = true
        defer { s.isRecordingScreen = false }
        let ok = s.startScreen(source: .fullScreen)
        XCTAssertFalse(ok)
    }

    // MARK: - Options surface

    func testTogglingOptionsPersistsImmediately() {
        let s1 = RecordingStore()
        s1.options.includeMicrophone = false
        s1.options.captureCursor = false
        // Fresh instance must see the new values.
        let s2 = RecordingStore()
        XCTAssertFalse(s2.options.includeMicrophone)
        XCTAssertFalse(s2.options.captureCursor)
    }

    func testFormatDurationHandlesRealisticRanges() {
        // UI renders durations for every recording row; make sure edge
        // cases render cleanly without crashing or producing empty strings.
        for secs: Double in [0, 0.3, 1, 59.9, 60, 61, 3599, 3600, 7321, 99999] {
            let out = RecordingStore.formatDuration(secs)
            XCTAssertFalse(out.isEmpty)
        }
    }

    // MARK: - Screencapture args (safety)

    func testAreaRetainsInteractiveFlagInArgumentBuilder() {
        // The args builder still emits `-i` for area even though
        // startScreen routes .area to the system picker — the builder is a
        // pure function reused by future ScreenCaptureKit work.
        let args = RecordingStore.screencaptureArguments(
            source: .area, outputPath: "/tmp/x.mov",
            options: RecordingOptions()
        )
        XCTAssertTrue(args.contains("-i"))
    }

    func testFullScreenDoesNotRequestInteractive() {
        let args = RecordingStore.screencaptureArguments(
            source: .fullScreen, outputPath: "/tmp/x.mov",
            options: RecordingOptions()
        )
        XCTAssertFalse(args.contains("-i"))
    }

    // MARK: - Defensive

    func testPermissionsStoreIsStableSingleton() {
        // Two references must be the same instance — env object wiring
        // relies on this.
        let a = PermissionsStore.shared
        let b = PermissionsStore.shared
        XCTAssertTrue(a === b)
    }

    func testMenuBarCoordinatorIsStableSingleton() {
        let a = MenuBarStatusCoordinator.shared
        let b = MenuBarStatusCoordinator.shared
        XCTAssertTrue(a === b)
    }
}
