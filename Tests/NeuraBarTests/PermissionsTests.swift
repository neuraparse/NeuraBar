import XCTest
@testable import NeuraBar

/// Permission state is owned by macOS TCC, so we can't flip it from tests.
/// We instead verify the pure-function parts: URL builders, state-to-action
/// mapping, and the "just granted, need restart" transition logic.
final class PermissionsServiceTests: XCTestCase {

    func testScreenRecordingPaneURLIsTheDocumentedDeepLink() {
        let url = PermissionsService.PrivacyPane.screenRecording.url
        XCTAssertEqual(
            url.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    func testMicrophonePaneURLIsTheDocumentedDeepLink() {
        let url = PermissionsService.PrivacyPane.microphone.url
        XCTAssertEqual(
            url.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
    }

    func testScreenRecordingStateMapsToBoolean() {
        // We can't force-change TCC, but we can assert that `.authorized`
        // mirrors the live CGPreflight result without crashing.
        let state = PermissionsService.screenRecording
        XCTAssertTrue(state == .authorized || state == .denied,
                      "Screen recording status is always authorized or denied on macOS (no notDetermined).")
    }

    func testMicrophoneStateIsReadable() {
        // Doesn't crash, returns a well-formed enum value.
        let state = PermissionsService.microphone
        switch state {
        case .authorized, .denied, .notDetermined:
            break
        }
    }

    func testPermissionStateIsAuthorizedHelper() {
        XCTAssertTrue(PermissionState.authorized.isAuthorized)
        XCTAssertFalse(PermissionState.denied.isAuthorized)
        XCTAssertFalse(PermissionState.notDetermined.isAuthorized)
    }
}

@MainActor
final class PermissionsStoreActionTests: XCTestCase {

    /// The store's `nextScreenRecordingAction` tells the UI whether to
    /// prompt, open Settings, restart, or do nothing. We force-stub the
    /// store's state and assert the mapping is right.

    func testRestartWinsOverEverythingElse() {
        // Once we've observed a grant mid-session, we prefer "Restart" over
        // anything else — macOS often needs the fresh process.
        let s = PermissionsStore.shared
        s.forceStateForTesting(screen: .authorized, needsRestart: true)
        XCTAssertEqual(s.nextScreenRecordingAction, .restartNeuraBar)
    }

    func testAuthorizedAndNoRestartFlagMapsToGood() {
        let s = PermissionsStore.shared
        s.forceStateForTesting(screen: .authorized, needsRestart: false)
        XCTAssertEqual(s.nextScreenRecordingAction, .good)
    }

    func testDeniedMapsToOpenSystemSettings() {
        let s = PermissionsStore.shared
        s.forceStateForTesting(screen: .denied, needsRestart: false)
        XCTAssertEqual(s.nextScreenRecordingAction, .openSystemSettings)
    }

    func testNotDeterminedMapsToRequest() {
        let s = PermissionsStore.shared
        s.forceStateForTesting(screen: .notDetermined, needsRestart: false)
        XCTAssertEqual(s.nextScreenRecordingAction, .request)
    }

    func testMicrophoneActionMapping() {
        let s = PermissionsStore.shared
        s.forceStateForTesting(mic: .authorized)
        XCTAssertEqual(s.nextMicrophoneAction, .good)
        s.forceStateForTesting(mic: .notDetermined)
        XCTAssertEqual(s.nextMicrophoneAction, .request)
        s.forceStateForTesting(mic: .denied)
        XCTAssertEqual(s.nextMicrophoneAction, .openSystemSettings)
    }
}

/// Recording should refuse to start silently when permission isn't granted.
/// We can't deny mic permission from a test, so we only assert that
/// `startScreen` returns false if preflight is denied. Since `screencapture`
/// itself is the system binary, we don't actually run it here — the guard
/// fires first.
final class RecordingGuardTests: NBTestCase {

    func testStartScreenReturnsFalseWhenPermissionDenied() {
        // On CI / dev box without screen recording permission, this returns
        // false immediately with `lastError` set. We just assert the
        // boolean signal — the banner wires up from there.
        let s = RecordingStore()
        if PermissionsService.screenRecording != .authorized {
            let ok = s.startScreen(source: .fullScreen)
            XCTAssertFalse(ok)
            XCTAssertNotNil(s.lastError)
        }
    }

    func testSystemPickerModeBypassesScreenRecordingGuard() {
        // .systemPicker hands off to macOS's Screenshot.app, which has its
        // own permission prompt. We should return true (launched) without
        // pre-flighting our own screen recording permission.
        let s = RecordingStore()
        let ok = s.startScreen(source: .systemPicker)
        XCTAssertTrue(ok)
        XCTAssertFalse(s.isRecordingScreen,
                       "System picker doesn't count as us recording anything")
    }

    func testAreaModeRoutesToSystemPickerNotScreencapture() {
        // `screencapture` doesn't actually support -i combined with -v on
        // macOS 26 (interactive area + video is unsupported). We route
        // .area through macOS Screenshot.app instead — same deal as
        // .systemPicker. Assert the behaviour contract here.
        let s = RecordingStore()
        let ok = s.startScreen(source: .area)
        XCTAssertTrue(ok,
                      ".area should succeed by launching the macOS toolbar, not fail")
        XCTAssertFalse(s.isRecordingScreen,
                       ".area hands off to macOS so we aren't tracking a local recording")
    }
}
