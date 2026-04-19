import SwiftUI

@main
struct NeuraBarApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var l10n = Localization.shared

    @StateObject private var permissions = PermissionsStore.shared

    var body: some Scene {
        MenuBarExtra {
            MainView()
                .environmentObject(store)
                .environmentObject(l10n)
                .environmentObject(store.conversations)
                .environmentObject(store.system)
                .environmentObject(permissions)
                .frame(width: NB.panelWidth, height: NB.panelHeight)
        } label: {
            MenuBarIconView()
                .environmentObject(store.system)
                .environmentObject(store.pomodoro)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Holds all feature stores so they persist while the popover is reopened.
final class AppStore: ObservableObject {
    let todos: TodoStore
    let notes: NoteStore
    let pomodoro: PomodoroTimer
    let clipboard: ClipboardManager
    let system: SystemMonitor
    let shortcuts: ShortcutStore
    let settings: SettingsStore
    let automation: AutomationStore
    let recording: RecordingStore
    let conversations: AIConversationStore

    init() {
        // Bootstrap the data location FIRST — before any sub-store loads
        // its JSON. Swift normally runs stored-property initializers before
        // the init body; we keep them lazy-style (assigned here) so the
        // bootstrap decides where they read from.
        let locationConfig = Persistence.loadDataLocation()
        Persistence.applyDataLocation(locationConfig)

        self.todos = TodoStore()
        self.notes = NoteStore()
        self.pomodoro = PomodoroTimer()
        self.clipboard = ClipboardManager()
        self.system = SystemMonitor()
        self.shortcuts = ShortcutStore()
        self.settings = SettingsStore()
        self.automation = AutomationStore()
        self.recording = RecordingStore()
        self.conversations = AIConversationStore()

        Localization.shared.apply(override: settings.data.language)
        clipboard.start()
        system.start()
        registerGlobalHotkey()
    }

    /// Registers ⌘⌥N as a system-wide shortcut to pop the menu bar window open
    /// / focus the big window. Carbon-based so it doesn't require
    /// Accessibility permission, and the binding doesn't collide with common
    /// chords in browsers / editors / Finder.
    private func registerGlobalHotkey() {
        GlobalHotkey.shared.onTrigger = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                if WindowManager.shared.isBigWindowOpen {
                    WindowManager.shared.closeMainWindow()
                } else {
                    WindowManager.shared.openMainWindow(store: self, l10n: Localization.shared)
                }
            }
        }
        GlobalHotkey.shared.register()
    }
}
