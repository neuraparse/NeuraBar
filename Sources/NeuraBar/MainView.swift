import SwiftUI
import AppKit

enum Tab: String, CaseIterable, Identifiable {
    case todos, focus, shortcuts, automate, clipboard, notes, record, system, ai
    var id: String { rawValue }

    var titleKey: Loc {
        switch self {
        case .todos: return .tab_todos
        case .focus: return .tab_focus
        case .shortcuts: return .tab_shortcuts
        case .automate: return .tab_automate
        case .clipboard: return .tab_clipboard
        case .notes: return .tab_notes
        case .record: return .tab_record
        case .system: return .tab_system
        case .ai: return .tab_ai
        }
    }

    var icon: String {
        switch self {
        case .todos: return "checklist"
        case .focus: return "timer"
        case .shortcuts: return "square.grid.2x2.fill"
        case .automate: return "wand.and.stars"
        case .clipboard: return "doc.on.clipboard"
        case .notes: return "note.text"
        case .record: return "record.circle"
        case .system: return "cpu"
        case .ai: return "sparkles"
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .todos: return "1"
        case .focus: return "2"
        case .shortcuts: return "3"
        case .automate: return "4"
        case .clipboard: return "5"
        case .notes: return "6"
        case .record: return "7"
        case .system: return "8"
        case .ai: return "9"
        }
    }

    var accent: Color {
        switch self {
        case .todos: return .blue
        case .focus: return .orange
        case .shortcuts: return .teal
        case .automate: return .pink
        case .clipboard: return .cyan
        case .notes: return .yellow
        case .record: return .red
        case .system: return .green
        case .ai: return .purple
        }
    }
}

struct MainView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var l10n: Localization
    @State private var tab: Tab = .todos
    @State private var showSettings = false
    @State private var showPalette = false
    @State private var showSplash = true
    @Namespace private var tabNS

    var isPoppedOut: Bool = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.3)
                content
                Divider().opacity(0.3)
                tabBar
            }

            // Global keyboard shortcut sink — invisible buttons.
            keyboardShortcutLayer
                .allowsHitTesting(false)
        }
        .onAppear {
            // Mutex: if the big window is open and the user clicks the menu
            // bar, close the window so only one surface is visible.
            if !isPoppedOut && WindowManager.shared.isBigWindowOpen {
                WindowManager.shared.closeMainWindow()
            }
        }
        .background(backdrop)
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environmentObject(store.settings)
                .environmentObject(l10n)
        }
        .overlay {
            if showPalette {
                CommandPalette(isPresented: $showPalette, tab: $tab)
                    .environmentObject(store)
                    .environmentObject(l10n)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .overlay {
            // Branded splash only when popped out — quick delight moment, then
            // fades out after ~0.9s.
            if isPoppedOut && showSplash {
                BrandSplash()
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                            withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.22, bounce: 0.12), value: showPalette)
        .animation(.easeOut(duration: 0.4), value: showSplash)
    }

    // MARK: - Backdrop

    @ViewBuilder
    private var backdrop: some View {
        ZStack {
            if isPoppedOut {
                // Big window: opaque adaptive base + sidebar material so text
                // stays readable no matter what's behind the window.
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                Rectangle().fill(.regularMaterial).ignoresSafeArea()
            } else {
                // Popover sits on top of the desktop/wallpaper — the ultra-thin
                // material already looks right against the system backdrop.
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            }
            // Branded gradient wash — kept subtle so it tints without hurting
            // text contrast.
            BrandWatermark()
                .opacity(isPoppedOut ? 0.45 : 0.55)
                .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: NB.sp3) {
            LogoView(size: 22, animated: true)

            VStack(alignment: .leading, spacing: 0) {
                Text(l10n.t(.appName))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(subtitleForTab)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            headerButton(icon: "command", help: l10n.t(.commandPalette)) {
                showPalette = true
            }
            if !isPoppedOut {
                headerButton(icon: "arrow.up.left.and.arrow.down.right", help: "Open in window") {
                    WindowManager.shared.openMainWindow(store: store, l10n: l10n)
                }
            }
            headerButton(icon: "gearshape.fill", help: l10n.t(.settings)) {
                showSettings = true
            }
            if !isPoppedOut {
                headerButton(icon: "power", help: l10n.t(.quit)) {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(.horizontal, NB.sp5)
        .padding(.vertical, NB.sp4)
    }

    private func headerButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .nbHoverHighlight(cornerRadius: 6, intensity: 0.1)
        .help(help)
    }

    private var subtitleForTab: String {
        switch tab {
        case .todos: return l10n.t(.subtitle_todos)
        case .focus: return l10n.t(.subtitle_focus)
        case .shortcuts: return l10n.t(.subtitle_shortcuts)
        case .automate: return l10n.t(.subtitle_automate)
        case .clipboard: return l10n.t(.subtitle_clipboard)
        case .notes: return l10n.t(.subtitle_notes)
        case .record: return l10n.t(.subtitle_record)
        case .system: return l10n.t(.subtitle_system)
        case .ai: return l10n.t(.subtitle_ai)
        }
    }

    // MARK: - Content

    private var content: some View {
        Group {
            switch tab {
            case .todos:     TodoView().environmentObject(store.todos)
            case .focus:     PomodoroView().environmentObject(store.pomodoro)
            case .shortcuts: ShortcutsView().environmentObject(store.shortcuts)
            case .automate:  AutomationView()
            case .clipboard: ClipboardView().environmentObject(store.clipboard)
            case .notes:     NotesView().environmentObject(store.notes)
            case .system:    SystemView().environmentObject(store.system)
            case .record:    RecordView().environmentObject(store.recording)
            case .ai:        AssistantView()
                                .environmentObject(store.settings)
                                .environmentObject(store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, NB.sp5)
        .padding(.vertical, NB.sp4)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 4)),
            removal: .opacity
        ))
        .id(tab)
        .animation(.spring(duration: 0.28, bounce: 0.15), value: tab)
    }

    // MARK: - Tab bar (polished, matched-geometry indicator)

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { t in
                tabButton(t)
            }
        }
        .padding(.horizontal, NB.sp2)
        .padding(.vertical, NB.sp2)
    }

    private func tabButton(_ t: Tab) -> some View {
        let selected = tab == t
        return Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                tab = t
            }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    if selected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(t.accent.opacity(0.18))
                            .matchedGeometryEffect(id: "tab.bg", in: tabNS)
                    }
                    Image(systemName: t.icon)
                        .font(.system(size: 13, weight: selected ? .bold : .medium))
                        .foregroundStyle(selected ? t.accent : .secondary)
                        .scaleEffect(selected ? 1.05 : 1.0)
                        .symbolEffect(.bounce, value: selected ? tab : nil)
                }
                .frame(height: 22)

                Text(l10n.t(t.titleKey))
                    .font(.system(size: 9, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? t.accent : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(Text("\(l10n.t(t.titleKey)) (⌘\(String(t.shortcutKey.character)))"))
    }

    // MARK: - Keyboard shortcuts

    private var keyboardShortcutLayer: some View {
        VStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                Button("") {
                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) { tab = t }
                }
                .keyboardShortcut(t.shortcutKey, modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
            }
            Button("") { showPalette.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
            Button("") { showSettings = true }
                .keyboardShortcut(",", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }
}
