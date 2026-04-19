import SwiftUI

/// Short-lived events that flash on the menu bar icon. Live status (system
/// alert) is handled by `SystemMonitor.alertLevel`; this type is strictly for
/// "something happened" pings that should revert to the base glyph quickly.
enum MenuBarEvent: String, Equatable, CaseIterable {
    case clipboardCopied
    case recordingSaved
    case automationDone
    case automationFailed

    var icon: String {
        switch self {
        case .clipboardCopied:  return "doc.on.clipboard.fill"
        case .recordingSaved:   return "waveform.circle.fill"
        case .automationDone:   return "checkmark.circle.fill"
        case .automationFailed: return "xmark.octagon.fill"
        }
    }

    /// Plain NSColor-equivalent tint for menu bar rendering. Keep these
    /// saturated — the menu bar blurs colours, so subtle shades vanish.
    var tint: Color {
        switch self {
        case .clipboardCopied:  return .blue
        case .recordingSaved:   return .pink
        case .automationDone:   return .green
        case .automationFailed: return .red
        }
    }

    /// Default duration the glyph stays on the icon before reverting.
    var duration: TimeInterval { 1.4 }
}

/// Owns the menu bar icon's transient state. Feature code calls `flash(...)`
/// from anywhere; the icon view observes and animates accordingly.
@MainActor
final class MenuBarStatusCoordinator: ObservableObject {
    static let shared = MenuBarStatusCoordinator()

    @Published private(set) var currentEvent: MenuBarEvent?

    private var dismissTask: Task<Void, Never>?

    func flash(_ event: MenuBarEvent, duration: TimeInterval? = nil) {
        dismissTask?.cancel()
        currentEvent = event
        let d = duration ?? event.duration
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000))
            guard let self = self, !Task.isCancelled else { return }
            self.currentEvent = nil
        }
    }

    /// Test hook — synchronously clear the current event.
    func clear() {
        dismissTask?.cancel()
        currentEvent = nil
    }
}
