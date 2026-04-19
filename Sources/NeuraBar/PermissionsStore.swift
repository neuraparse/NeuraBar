import Foundation
import SwiftUI

/// Observable store that tracks permission states + whether a grant has been
/// made in the *current* session (which means a restart is usually required
/// before the running process picks it up).
@MainActor
final class PermissionsStore: ObservableObject {
    static let shared = PermissionsStore()

    @Published private(set) var screenRecording: PermissionState
    @Published private(set) var microphone: PermissionState

    /// True when screen recording transitioned from denied/notDetermined to
    /// authorized during this session — macOS typically requires a restart
    /// before a running process actually picks up the grant.
    @Published private(set) var screenRecordingNeedsRestart: Bool = false

    private var lastScreenRecording: PermissionState
    private var refreshTimer: Timer?

    init() {
        let initial = PermissionsService.screenRecording
        self.screenRecording = initial
        self.lastScreenRecording = initial
        self.microphone = PermissionsService.microphone
        // TCC doesn't emit notifications when the user flips a toggle in
        // System Settings, so we poll. Timer runs on the main run loop and
        // weak-captures self — safer than a Task loop.
        startPolling()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    private func startPolling() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop but the block isn't
            // MainActor-isolated by default; hop explicitly.
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Snapshot current states. Called implicitly on a 1.5 s loop but also
    /// exposed so the UI can trigger a re-check right after clicking an
    /// "Open Settings" button.
    func refresh() {
        let newScreen = PermissionsService.screenRecording
        let newMic = PermissionsService.microphone

        if newScreen == .authorized && lastScreenRecording != .authorized {
            // Transitioned to granted — but this running process might still
            // be using a stale TCC cache. Flag that a restart would help.
            screenRecordingNeedsRestart = true
        }
        if newScreen != .authorized {
            screenRecordingNeedsRestart = false
        }

        screenRecording = newScreen
        lastScreenRecording = newScreen
        microphone = newMic
    }

    /// Run the platform request + update our cache. For screen recording
    /// this creates the System Settings entry and returns the *current*
    /// state — the user still has to flip the toggle themselves.
    func requestScreenRecording() {
        _ = PermissionsService.requestScreenRecording()
        refresh()
    }

    /// Async mic prompt. Updates cache on completion.
    func requestMicrophone() async -> PermissionState {
        let result = await PermissionsService.requestMicrophone()
        self.microphone = result
        return result
    }

    // MARK: - Convenience

    /// Best next action for the current screen-recording state. Helps the UI
    /// render a single "do the right thing" button.
    enum NextScreenRecordingAction {
        case request               // notDetermined-ish — hit the system prompt
        case openSystemSettings    // denied — user needs to flip the toggle
        case restartNeuraBar       // granted but we suspect restart is needed
        case good                  // everything is in order
    }

    var nextScreenRecordingAction: NextScreenRecordingAction {
        if screenRecordingNeedsRestart { return .restartNeuraBar }
        switch screenRecording {
        case .authorized:    return .good
        case .notDetermined: return .request
        case .denied:        return .openSystemSettings
        }
    }

    enum NextMicrophoneAction {
        case request
        case openSystemSettings
        case good
    }

    var nextMicrophoneAction: NextMicrophoneAction {
        switch microphone {
        case .authorized:    return .good
        case .notDetermined: return .request
        case .denied:        return .openSystemSettings
        }
    }

    /// Test hook — lets unit tests pin state without relying on live TCC.
    /// Not intended for production code.
    func forceStateForTesting(
        screen: PermissionState? = nil,
        mic: PermissionState? = nil,
        needsRestart: Bool? = nil
    ) {
        if let screen = screen {
            self.screenRecording = screen
            self.lastScreenRecording = screen
        }
        if let mic = mic {
            self.microphone = mic
        }
        if let needsRestart = needsRestart {
            self.screenRecordingNeedsRestart = needsRestart
        }
    }
}
