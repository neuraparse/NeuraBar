import SwiftUI
import AppKit

/// Owns the standalone pop-out window and coordinates "only one UI visible at a
/// time" — opening the big window closes the menu-bar popover, closing the
/// window leaves the popover reachable again.
final class WindowManager: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = WindowManager()

    @Published private(set) var isBigWindowOpen: Bool = false

    private var mainWindow: NSWindow?

    /// Called on launch to record a reference to whatever window the popover
    /// creates. We identify it by class-name prefix since Apple uses private
    /// NSMenuBarExtraWindow class.
    private var popoverWindow: NSWindow? {
        NSApp.windows.first { window in
            let cls = String(describing: type(of: window))
            return cls.contains("MenuBarExtra") || cls.contains("Popover")
        }
    }

    @MainActor
    func openMainWindow(store: AppStore, l10n: Localization) {
        // Close the popover first — mutex behaviour.
        closePopover()

        if let w = mainWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentSize = NSSize(width: 820, height: 720)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = l10n.t(.appName)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 560, height: 560)
        // Opaque adaptive window background — guarantees readable contrast
        // regardless of what's behind the window. SwiftUI's material layer on
        // top still gives us the vibrancy look.
        win.isOpaque = true
        win.backgroundColor = .windowBackgroundColor
        win.center()
        win.delegate = self

        let root = PoppedMainView()
            .environmentObject(store)
            .environmentObject(l10n)
            .environmentObject(self)
            .frame(minWidth: 560, minHeight: 560)

        win.contentView = NSHostingView(rootView: root)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow = win
        isBigWindowOpen = true
    }

    @MainActor
    func closeMainWindow() {
        mainWindow?.close()
    }

    /// Dismiss the MenuBarExtra popover, if one is currently showing. Works by
    /// locating the popover's NSWindow among app windows.
    @MainActor
    func closePopover() {
        if let pw = popoverWindow, pw.isVisible {
            pw.orderOut(nil)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow, w === mainWindow {
            mainWindow = nil
            isBigWindowOpen = false
        }
    }
}

struct PoppedMainView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var l10n: Localization

    var body: some View {
        MainView(isPoppedOut: true)
            .environmentObject(store)
            .environmentObject(l10n)
    }
}
