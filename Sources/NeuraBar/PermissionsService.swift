import Foundation
import AVFoundation
import AppKit
import CoreGraphics

/// Simple tri-state that maps cleanly onto both AVFoundation's
/// `AVAuthorizationStatus` and our Screen Recording tri-state.
enum PermissionState: Equatable {
    /// Never asked. Next call should prompt the user.
    case notDetermined
    /// User granted. Safe to proceed.
    case authorized
    /// User denied or the system restricts it. Need a Settings trip.
    case denied

    var isAuthorized: Bool { self == .authorized }
}

/// Centralised access to the macOS permission surfaces NeuraBar actually
/// touches: Screen Recording (for `screencapture` / ScreenCaptureKit) and
/// the Microphone (for `AVAudioRecorder`).
///
/// macOS 26 notes — drawn from real-world bug reports:
///   • Screen recording permission is evaluated against the "responsible
///     process". For a non-sandboxed .app like NeuraBar that's the .app
///     itself, so the parent must have the grant — the spawned
///     `screencapture` binary does NOT bring its own.
///   • `CGRequestScreenCaptureAccess()` is the right call to *register*
///     NeuraBar in System Settings → Privacy → Screen & System Audio.
///     `CGPreflightScreenCaptureAccess()` only reads the current state.
///   • After a grant in Settings the running process often doesn't pick up
///     the new TCC state until it's restarted. We expose a one-click
///     `restartApp()` helper for that exact case.
enum PermissionsService {

    // MARK: - Screen Recording

    /// Live state of the Screen Recording TCC entry for NeuraBar.
    static var screenRecording: PermissionState {
        CGPreflightScreenCaptureAccess() ? .authorized : .denied
    }

    /// Registers NeuraBar in the Screen Recording list and returns whether
    /// access is granted *at this moment*. If the entry didn't exist yet,
    /// this call creates it (macOS will show its prompt once). On first run
    /// against a denied state the user typically has to click "Allow" in
    /// System Settings and then restart NeuraBar.
    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Microphone

    static var microphone: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: return .notDetermined
        case .authorized:    return .authorized
        case .denied, .restricted: return .denied
        @unknown default:    return .denied
        }
    }

    /// Prompts the user for microphone access when we haven't asked yet.
    /// Resolves with the final state. Never prompts a second time — once
    /// denied, the user must go to System Settings.
    @MainActor
    static func requestMicrophone() async -> PermissionState {
        switch microphone {
        case .authorized: return .authorized
        case .denied:     return .denied
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    cont.resume(returning: granted ? .authorized : .denied)
                }
            }
        }
    }

    // MARK: - System Settings deep links

    enum PrivacyPane: String {
        case screenRecording
        case microphone

        /// macOS 13+ deep link that opens System Settings directly on the
        /// Privacy pane for this permission.
        var url: URL {
            switch self {
            case .screenRecording:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            case .microphone:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            }
        }
    }

    static func openSystemSettings(for pane: PrivacyPane) {
        NSWorkspace.shared.open(pane.url)
    }

    // MARK: - Restart

    /// Relaunch NeuraBar so the running process picks up any permission
    /// grant the user just made in System Settings. macOS caches TCC state
    /// per-process, so a fresh process avoids the "granted but still
    /// denied" trap.
    @MainActor
    static func restartApp() {
        let bundleURL = Bundle.main.bundleURL
        // Use `open -n` to spawn a fresh instance detached from us.
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundleURL.path]
        try? task.run()

        // Give the relaunch a moment, then terminate.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }
}
