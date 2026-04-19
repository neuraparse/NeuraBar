import SwiftUI
import AppKit

struct PaletteItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let section: String
    let action: () -> Void
}

struct CommandPalette: View {
    @Binding var isPresented: Bool
    @Binding var tab: Tab
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var l10n: Localization
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var queryFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                searchField
                Divider().opacity(0.2)
                resultsList
            }
            .frame(width: 380, height: 380)
            .nbGlass(cornerRadius: NB.rXl)
            .overlay {
                RoundedRectangle(cornerRadius: NB.rXl, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(0.35), radius: 30, y: 8)
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            selection = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                queryFocused = true
            }
        }
        .background(keyboardHandler)
    }

    private var keyboardHandler: some View {
        VStack(spacing: 0) {
            Button("") { isPresented = false }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0).opacity(0)
            Button("") { moveSelection(+1) }
                .keyboardShortcut(.downArrow, modifiers: [])
                .frame(width: 0, height: 0).opacity(0)
            Button("") { moveSelection(-1) }
                .keyboardShortcut(.upArrow, modifiers: [])
                .frame(width: 0, height: 0).opacity(0)
            Button("") { activate() }
                .keyboardShortcut(.return, modifiers: [])
                .frame(width: 0, height: 0).opacity(0)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(l10n.t(.palette_searchPlaceholder), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($queryFocused)
                .onSubmit { activate() }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            Text("ESC")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, NB.sp5)
        .padding(.vertical, NB.sp4)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let filtered = items
                    if filtered.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 24))
                                .foregroundStyle(.secondary)
                            Text(l10n.t(.palette_noResults))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 50)
                    } else {
                        let grouped = Dictionary(grouping: filtered) { $0.section }
                        ForEach(sectionOrder(from: grouped), id: \.self) { section in
                            if let rows = grouped[section] {
                                Text(section)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .kerning(0.5)
                                    .padding(.horizontal, NB.sp5)
                                    .padding(.top, NB.sp3)
                                    .padding(.bottom, 2)
                                ForEach(Array(rows.enumerated()), id: \.element.id) { _, row in
                                    let globalIdx = filtered.firstIndex { $0.id == row.id } ?? 0
                                    PaletteRow(item: row, selected: selection == globalIdx)
                                        .id(row.id)
                                        .onTapGesture {
                                            selection = globalIdx
                                            activate()
                                        }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, NB.sp3)
            }
            .onChange(of: selection) { _, _ in
                let list = items
                if selection < list.count {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(list[selection].id, anchor: .center)
                    }
                }
            }
        }
    }

    private func sectionOrder(from grouped: [String: [PaletteItem]]) -> [String] {
        let preferred = [
            l10n.t(.palette_section_tab),
            l10n.t(.palette_section_todo),
            l10n.t(.palette_section_note),
            l10n.t(.palette_section_shortcut),
            l10n.t(.palette_section_clip),
            l10n.t(.palette_section_action)
        ]
        var result: [String] = []
        for key in preferred where grouped[key] != nil { result.append(key) }
        for key in grouped.keys.sorted() where !result.contains(key) { result.append(key) }
        return result
    }

    private func moveSelection(_ delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func activate() {
        let list = items
        guard selection < list.count else { return }
        let item = list[selection]
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            item.action()
        }
    }

    private var items: [PaletteItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out: [PaletteItem] = []

        // Tabs
        for t in Tab.allCases {
            let title = l10n.t(t.titleKey)
            if q.isEmpty || title.lowercased().contains(q) || t.rawValue.contains(q) {
                out.append(PaletteItem(
                    icon: t.icon,
                    title: "\(title) \(l10n.t(.palette_tabSuffix))",
                    subtitle: "⌘\(String(t.shortcutKey.character))",
                    section: l10n.t(.palette_section_tab)
                ) {
                    tab = t
                })
            }
        }

        // Todos
        for todo in store.todos.items where !todo.done {
            if q.isEmpty ? out.count < 20 : todo.title.lowercased().contains(q) {
                out.append(PaletteItem(
                    icon: "circle",
                    title: todo.title,
                    subtitle: todo.tag.isEmpty ? l10n.t(.palette_taskLabel) : "\(l10n.t(.palette_taskLabel)) · \(todo.tag)",
                    section: l10n.t(.palette_section_todo)
                ) {
                    tab = .todos
                })
            }
        }

        // Notes
        for note in store.notes.items {
            if q.isEmpty ? out.count < 30 : (note.title.lowercased().contains(q) || note.body.lowercased().contains(q)) {
                out.append(PaletteItem(
                    icon: "note.text",
                    title: note.title.isEmpty ? l10n.t(.notes_untitled) : note.title,
                    subtitle: note.body.prefix(50).replacingOccurrences(of: "\n", with: " "),
                    section: l10n.t(.palette_section_note)
                ) {
                    tab = .notes
                })
            }
        }

        // Shortcuts
        for s in store.shortcuts.items {
            if q.isEmpty ? out.count < 40 : s.name.lowercased().contains(q) {
                out.append(PaletteItem(
                    icon: s.icon,
                    title: s.name,
                    subtitle: s.kind.rawValue.capitalized,
                    section: l10n.t(.palette_section_shortcut)
                ) { [store] in
                    store.shortcuts.launch(s)
                })
            }
        }

        // Clipboard
        for item in store.clipboard.items.prefix(20) {
            let single = item.text.replacingOccurrences(of: "\n", with: " ")
            if q.isEmpty || single.lowercased().contains(q) {
                out.append(PaletteItem(
                    icon: "doc.on.clipboard",
                    title: String(single.prefix(60)),
                    subtitle: l10n.t(.palette_pasteAction),
                    section: l10n.t(.palette_section_clip)
                ) { [store] in
                    store.clipboard.copy(item)
                })
            }
        }

        // Actions
        let actions: [PaletteItem] = [
            .init(icon: "play.fill", title: l10n.t(.palette_startFocus), subtitle: "25 min", section: l10n.t(.palette_section_action)) { [store] in
                store.pomodoro.startFocus()
                tab = .focus
            },
            .init(icon: "pause.fill", title: l10n.t(.palette_pauseFocus), subtitle: "", section: l10n.t(.palette_section_action)) { [store] in
                store.pomodoro.pause()
            },
            .init(icon: "trash.slash", title: l10n.t(.palette_clearCompleted), subtitle: l10n.t(.todo_filter_done), section: l10n.t(.palette_section_action)) { [store] in
                store.todos.clearCompleted()
            },
            .init(icon: "sparkles", title: l10n.t(.palette_askAI), subtitle: "", section: l10n.t(.palette_section_action)) {
                tab = .ai
            }
        ]
        for a in actions {
            if q.isEmpty || a.title.lowercased().contains(q) { out.append(a) }
        }

        return out
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if selected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, NB.sp5)
        .padding(.vertical, NB.sp3)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .padding(.horizontal, 6)
            }
        }
        .contentShape(Rectangle())
    }
}
