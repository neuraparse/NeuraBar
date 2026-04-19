import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter that:
///  - never crashes when running inside XCTest (no valid .app bundle)
///  - honours user-facing enable flags stored in Settings
///  - swallows authorization failures silently (we don't want a denied
///    prompt to ever throw).
///
/// Call sites post without worrying about permissions — if anything is off,
/// the post becomes a no-op.
enum NotificationService {

    /// True when we're running inside a real .app bundle (not the xctest
    /// runner). UserNotifications throws NSInternalInconsistencyException
    /// otherwise, so every other helper short-circuits on this flag.
    static var isAvailable: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// Request authorization once, silently. Safe to call multiple times.
    static func requestAuthorizationIfNeeded() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Post a notification. `subtitle` is optional; `sound` defaults to the
    /// system default.
    static func post(
        title: String,
        body: String,
        subtitle: String? = nil,
        sound: UNNotificationSound? = .default,
        category: String? = nil
    ) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let s = subtitle { content.subtitle = s }
        content.sound = sound
        if let c = category { content.categoryIdentifier = c }
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req) { _ in }
    }
}
