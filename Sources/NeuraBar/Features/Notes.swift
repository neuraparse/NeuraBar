import SwiftUI
import AppKit

// MARK: - Model

enum NoteColor: String, CaseIterable, Codable, Identifiable {
    case none, red, orange, yellow, green, teal, blue, purple, pink
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .none:   return .clear
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .teal:   return .teal
        case .blue:   return .blue
        case .purple: return .purple
        case .pink:   return .pink
        }
    }
}

struct NoteItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var body: String
    var updated: Date
    var created: Date = Date()
    var pinned: Bool = false
    var color: NoteColor = .none

    /// Pulls hashtag tokens out of the body (`#work`, `#idea`) — recomputed on
    /// access so tags can't drift from content.
    var tags: [String] {
        let pattern = #"#([\p{L}\d_-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        var out = Set<String>()
        regex.enumerateMatches(in: body, options: [], range: range) { match, _, _ in
            if let m = match, let r = Range(m.range(at: 1), in: body) {
                out.insert(String(body[r]).lowercased())
            }
        }
        return Array(out).sorted()
    }

    /// Counts Unicode scalars trimmed of whitespace — approximates character
    /// count for mixed-language notes without over-counting combining marks.
    var characterCount: Int {
        body.unicodeScalars.filter { !$0.properties.isWhitespace }.count
    }

    /// Splits on any whitespace. Empty body returns 0.
    var wordCount: Int {
        body.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Rough reading time in minutes, assuming 220 wpm. Always at least 1 when
    /// there is any content.
    var readingMinutes: Int {
        guard wordCount > 0 else { return 0 }
        return max(1, Int((Double(wordCount) / 220.0).rounded(.up)))
    }

    /// First non-empty line for list previews, capped at 60 chars.
    var preview: String {
        let first = body
            .split(whereSeparator: { $0.isNewline })
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map(String.init)
            ?? ""
        return String(first.prefix(60))
    }

    /// The title shown in the list — explicit title wins, else first non-blank
    /// line of the body, else a localized "untitled" fallback.
    var effectiveTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let p = preview.trimmingCharacters(in: .whitespaces)
        return p.isEmpty ? L.t(.notes_untitled) : p
    }

    // Tolerant decoder — older notes.json files lack `pinned`, `color`,
    // `created`; fall through to sensible defaults.
    enum CodingKeys: String, CodingKey {
        case id, title, body, updated, created, pinned, color
    }

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        updated: Date,
        created: Date = Date(),
        pinned: Bool = false,
        color: NoteColor = .none
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.updated = updated
        self.created = created
        self.pinned = pinned
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        body = (try? c.decode(String.self, forKey: .body)) ?? ""
        updated = (try? c.decode(Date.self, forKey: .updated)) ?? Date()
        created = (try? c.decode(Date.self, forKey: .created)) ?? updated
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
        color = (try? c.decode(NoteColor.self, forKey: .color)) ?? .none
    }
}

// MARK: - Store

final class NoteStore: ObservableObject {
    @Published var items: [NoteItem] {
        didSet { Persistence.save(items, to: "notes.json") }
    }

    init() {
        self.items = Persistence.load([NoteItem].self, from: "notes.json") ?? [
            NoteItem(
                title: L.t(.notes_welcomeTitle),
                body: L.t(.notes_welcomeBody),
                updated: Date()
            )
        ]
    }

    /// Creates a new note and returns it so the caller can select it.
    @discardableResult
    func new(title: String = "", body: String = "") -> NoteItem {
        let note = NoteItem(
            title: title.isEmpty ? L.t(.notes_new) : title,
            body: body,
            updated: Date()
        )
        items.insert(note, at: 0)
        return note
    }

    /// Creates a new note prefilled with the current clipboard contents.
    @discardableResult
    func newFromClipboard() -> NoteItem? {
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string) else { return nil }
        return new(title: "", body: text)
    }

    func update(_ note: NoteItem) {
        if let i = items.firstIndex(where: { $0.id == note.id }) {
            var updated = note
            updated.updated = Date()
            items[i] = updated
        }
    }

    func remove(_ note: NoteItem) {
        items.removeAll { $0.id == note.id }
    }

    func togglePin(_ note: NoteItem) {
        if let i = items.firstIndex(where: { $0.id == note.id }) {
            items[i].pinned.toggle()
            items[i].updated = Date()
        }
    }

    func setColor(_ color: NoteColor, for note: NoteItem) {
        if let i = items.firstIndex(where: { $0.id == note.id }) {
            items[i].color = color
            items[i].updated = Date()
        }
    }

    @discardableResult
    func duplicate(_ note: NoteItem) -> NoteItem {
        let copy = NoteItem(
            title: note.title.isEmpty ? "" : note.title + " (copy)",
            body: note.body,
            updated: Date(),
            pinned: false,
            color: note.color
        )
        items.insert(copy, at: 0)
        return copy
    }

    /// Sort: pinned first, then by updated desc. Pure — used by UI.
    var sorted: [NoteItem] {
        items.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.updated > b.updated
        }
    }

    /// Filter by free-text query (matches title, body, tags).
    func filter(_ query: String) -> [NoteItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sorted }
        return sorted.filter { n in
            n.title.lowercased().contains(q)
                || n.body.lowercased().contains(q)
                || n.tags.contains(where: { $0.contains(q) })
        }
    }

    /// Aggregate tags across all notes, counted.
    var allTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in items {
            for t in item.tags { counts[t, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}

// MARK: - Time grouping

enum NoteTimeBucket: String, CaseIterable {
    case pinned, today, yesterday, thisWeek, older

    var titleKey: Loc {
        switch self {
        case .pinned:    return .notes_group_pinned
        case .today:     return .notes_group_today
        case .yesterday: return .notes_group_yesterday
        case .thisWeek:  return .notes_group_thisWeek
        case .older:     return .notes_group_older
        }
    }
}

extension NoteStore {
    /// Buckets the already-filtered list into pinned / today / yesterday / week / older.
    /// Day boundaries are measured relative to the provided `now`, so tests
    /// can pin a reference date and get deterministic buckets.
    static func group(_ notes: [NoteItem], now: Date = Date()) -> [(NoteTimeBucket, [NoteItem])] {
        var pinned: [NoteItem] = []
        var today: [NoteItem] = []
        var yesterday: [NoteItem] = []
        var week: [NoteItem] = []
        var older: [NoteItem] = []

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let startOfYesterday = cal.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = cal.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday

        for n in notes {
            if n.pinned {
                pinned.append(n)
                continue
            }
            if n.updated >= startOfToday {
                today.append(n)
            } else if n.updated >= startOfYesterday {
                yesterday.append(n)
            } else if n.updated >= startOfWeek {
                week.append(n)
            } else {
                older.append(n)
            }
        }

        var out: [(NoteTimeBucket, [NoteItem])] = []
        if !pinned.isEmpty { out.append((.pinned, pinned)) }
        if !today.isEmpty { out.append((.today, today)) }
        if !yesterday.isEmpty { out.append((.yesterday, yesterday)) }
        if !week.isEmpty { out.append((.thisWeek, week)) }
        if !older.isEmpty { out.append((.older, older)) }
        return out
    }
}

// MARK: - Views

struct NotesView: View {
    @EnvironmentObject var store: NoteStore
    @EnvironmentObject var l10n: Localization

    @State private var selected: NoteItem?
    @State private var search: String = ""
    @State private var activeTag: String?
    @State private var isPreviewing: Bool = false
    @Namespace private var selectionNS

    /// Below this width we flip from split (sidebar + editor) to a single-pane
    /// navigation layout — the 420 px menu-bar popover can't fit both panels.
    private static let splitThreshold: CGFloat = 520

    var body: some View {
        GeometryReader { geo in
            let isCompact = geo.size.width < Self.splitThreshold
            Group {
                if isCompact {
                    compactLayout
                } else {
                    splitLayout
                }
            }
            .animation(.spring(duration: 0.24, bounce: 0.15), value: isCompact)
        }
        .onAppear {
            if selected == nil { selected = nil } // keep list visible in compact on first open
        }
        .background(keyboardShortcuts)
    }

    // MARK: - Layouts

    private var splitLayout: some View {
        HStack(spacing: 8) {
            sidebar
                .frame(minWidth: 170, idealWidth: 180, maxWidth: 200)
            Divider().opacity(0.3)
            editorPane
        }
        .onAppear {
            // Split view always needs a selection, pick the first if missing.
            if selected == nil { selected = store.sorted.first }
        }
    }

    private var compactLayout: some View {
        ZStack {
            if selected == nil {
                sidebar
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Button {
                            withAnimation(.spring(duration: 0.24, bounce: 0.18)) {
                                selected = nil
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 10, weight: .bold))
                                Text(l10n.t(.notes_title))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .nbHoverHighlight(cornerRadius: 5, intensity: 0.08)
                        Spacer()
                    }
                    editorPane
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(duration: 0.24, bounce: 0.18), value: selected?.id)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            searchField
            tagChips
            notesList
            footer
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(l10n.t(.search), text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !search.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { search = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var tagChips: some View {
        let tags = store.allTags
        return Group {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        chip(label: "All", active: activeTag == nil) {
                            withAnimation(.spring(duration: 0.2)) { activeTag = nil }
                        }
                        ForEach(tags.prefix(10), id: \.tag) { entry in
                            chip(label: "#\(entry.tag)", active: activeTag == entry.tag) {
                                withAnimation(.spring(duration: 0.2)) {
                                    activeTag = (activeTag == entry.tag) ? nil : entry.tag
                                }
                            }
                        }
                    }
                }
                .frame(height: 22)
            }
        }
    }

    private func chip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(active ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(PressableStyle())
    }

    private var notesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                let filtered = filteredNotes
                if filtered.isEmpty {
                    emptyNotesHint
                } else {
                    ForEach(NoteStore.group(filtered), id: \.0) { bucket, notes in
                        Text(l10n.t(bucket.titleKey))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .kerning(0.4)
                            .padding(.top, 6)
                            .padding(.bottom, 2)
                        ForEach(notes) { note in
                            NoteRow(
                                note: note,
                                selected: selected?.id == note.id,
                                ns: selectionNS
                            )
                            .environmentObject(store)
                            .onTapGesture {
                                select(note)
                            }
                            .contextMenu { rowContextMenu(for: note) }
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -4)),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            ))
                        }
                    }
                }
            }
            .animation(.spring(duration: 0.28, bounce: 0.15), value: store.items)
        }
    }

    private var emptyNotesHint: some View {
        VStack(spacing: 4) {
            Image(systemName: "note.text")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text(search.isEmpty && activeTag == nil
                 ? l10n.t(.notes_empty)
                 : l10n.t(.notes_noMatch))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.spring(duration: 0.24, bounce: 0.2)) {
                    selected = store.new()
                }
            } label: {
                Label(l10n.t(.notes_new), systemImage: "plus")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.accentColor)
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button {
                if let n = store.newFromClipboard() {
                    withAnimation(.spring(duration: 0.24, bounce: 0.2)) { selected = n }
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(PressableStyle())
            .help(l10n.t(.notes_newFromClipboard))

            Spacer()
            Text("\(store.items.count)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Editor pane

    @ViewBuilder
    private var editorPane: some View {
        if let sel = selected, let index = store.items.firstIndex(where: { $0.id == sel.id }) {
            NoteEditor(
                note: $store.items[index],
                isPreviewing: $isPreviewing
            )
            .environmentObject(store)
            .environmentObject(l10n)
            .id(sel.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                Text(l10n.t(.notes_empty))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(l10n.t(.notes_new)) {
                    selected = store.new()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Filtering + actions

    private var filteredNotes: [NoteItem] {
        var list = store.filter(search)
        if let t = activeTag {
            list = list.filter { $0.tags.contains(t) }
        }
        return list
    }

    private func select(_ note: NoteItem) {
        withAnimation(.spring(duration: 0.22, bounce: 0.2)) { selected = note }
    }

    @ViewBuilder
    private func rowContextMenu(for note: NoteItem) -> some View {
        Button(note.pinned ? l10n.t(.notes_unpin) : l10n.t(.notes_pin)) {
            store.togglePin(note)
        }
        Button(l10n.t(.notes_duplicate)) {
            let copy = store.duplicate(note)
            select(copy)
        }
        Button(l10n.t(.notes_copyBody)) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(note.body, forType: .string)
        }
        Menu(l10n.t(.notes_color)) {
            ForEach(NoteColor.allCases) { c in
                Button {
                    store.setColor(c, for: note)
                } label: {
                    HStack {
                        Circle().fill(c.color).frame(width: 10, height: 10)
                        Text(c.rawValue.capitalized)
                    }
                }
            }
        }
        Divider()
        Button(l10n.t(.delete), role: .destructive) {
            if selected?.id == note.id { selected = nil }
            withAnimation(.spring(duration: 0.22, bounce: 0.15)) {
                store.remove(note)
            }
        }
    }

    // MARK: - Keyboard shortcuts

    private var keyboardShortcuts: some View {
        VStack(spacing: 0) {
            Button("") { isPreviewing.toggle() }
                .keyboardShortcut("/", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)
            Button("") {
                if let sel = selected {
                    let copy = store.duplicate(sel)
                    select(copy)
                }
            }
            .keyboardShortcut("d", modifiers: .command)
            .frame(width: 0, height: 0).opacity(0)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Note row

struct NoteRow: View {
    let note: NoteItem
    let selected: Bool
    let ns: Namespace.ID
    @EnvironmentObject var store: NoteStore
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Color stripe
            RoundedRectangle(cornerRadius: 1.5)
                .fill(note.color == .none ? Color.primary.opacity(0.1) : note.color.color)
                .frame(width: 2.5)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if note.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                    }
                    Text(note.effectiveTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(shortDate(note.updated))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                if !note.preview.isEmpty && note.preview != note.effectiveTitle {
                    Text(note.preview)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !note.tags.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(note.tags.prefix(3), id: \.self) { t in
                            Text("#\(t)")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.18))
                    .matchedGeometryEffect(id: "note.selection", in: ns)
            } else if hover {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .onHover { hover = $0 }
        .contentShape(Rectangle())
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            f.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            return "yday"
        } else {
            f.dateFormat = "MMM d"
        }
        return f.string(from: date)
    }
}

// MARK: - Editor

struct NoteEditor: View {
    @Binding var note: NoteItem
    @Binding var isPreviewing: Bool

    @EnvironmentObject var store: NoteStore
    @EnvironmentObject var l10n: Localization
    @State private var showSaved = false
    @State private var lastBodyLength = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            Divider().opacity(0.3)
            content
            Divider().opacity(0.3)
            statusBar
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: note.body) { _, newValue in
            // Surface a momentary "saved" flash the first few times the user
            // types — just enough to signal auto-save is working without being
            // intrusive.
            if abs(newValue.count - lastBodyLength) > 0 {
                lastBodyLength = newValue.count
                store.update(note)
                withAnimation { showSaved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation { showSaved = false }
                }
            }
        }
        .onChange(of: note.title) {
            store.update(note)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 5) {
            toolbarButton(icon: "bold", help: "Bold (⌘B)") { wrapSelection(with: "**") }
                .keyboardShortcut("b", modifiers: .command)
            toolbarButton(icon: "italic", help: "Italic (⌘I)") { wrapSelection(with: "_") }
                .keyboardShortcut("i", modifiers: .command)
            toolbarButton(icon: "chevron.left.slash.chevron.right", help: "Inline code") { wrapSelection(with: "`") }
            toolbarButton(icon: "list.bullet", help: "Bulleted list") { insertLinePrefix("- ") }
            toolbarButton(icon: "checklist", help: "Checklist") { insertLinePrefix("- [ ] ") }
            toolbarButton(icon: "number", help: "Heading") { insertLinePrefix("## ") }
            Divider().frame(height: 14)
            toolbarButton(icon: "clock", help: "Insert timestamp (⌘;)") {
                insert(timestamp())
            }
            .keyboardShortcut(";", modifiers: .command)
            toolbarButton(icon: "doc.on.doc", help: l10n.t(.notes_copyBody)) { copyAll() }

            Spacer()

            // Color indicator
            Menu {
                ForEach(NoteColor.allCases) { c in
                    Button {
                        store.setColor(c, for: note)
                    } label: {
                        HStack {
                            Circle().fill(c.color).frame(width: 10, height: 10)
                            Text(c.rawValue.capitalized)
                        }
                    }
                }
            } label: {
                Circle()
                    .fill(note.color == .none ? Color.primary.opacity(0.15) : note.color.color)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                store.togglePin(note)
            } label: {
                Image(systemName: note.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(note.pinned ? .orange : .secondary)
                    .symbolEffect(.bounce, value: note.pinned)
            }
            .buttonStyle(PressableStyle())
            .help(note.pinned ? l10n.t(.notes_unpin) : l10n.t(.notes_pin))

            Button {
                withAnimation(.spring(duration: 0.22, bounce: 0.2)) {
                    isPreviewing.toggle()
                }
            } label: {
                Image(systemName: isPreviewing ? "square.and.pencil" : "eye")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isPreviewing ? Color.accentColor : .secondary)
                    .symbolEffect(.bounce, value: isPreviewing)
            }
            .buttonStyle(PressableStyle())
            .help(isPreviewing ? l10n.t(.notes_edit) : l10n.t(.notes_preview))
        }
    }

    private func toolbarButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .nbHoverHighlight(cornerRadius: 4, intensity: 0.08)
        .help(help)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 4) {
            TextField(l10n.t(.notes_titlePlaceholder), text: $note.title)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.top, 6)

            if isPreviewing {
                previewPane
            } else {
                editorPane
            }
        }
    }

    private var editorPane: some View {
        TextEditor(text: $note.body)
            .font(.system(size: 12))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            .transition(.opacity)
    }

    /// Live markdown preview using Foundation's AttributedString(markdown:).
    /// Works on macOS 14+ and handles bold/italic/code/lists/links.
    private var previewPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let attr = try? AttributedString(markdown: note.body,
                                                   options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                    Text(attr)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                } else {
                    Text(note.body)
                        .font(.system(size: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .transition(.opacity)
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text("\(note.wordCount) \(l10n.t(.notes_words))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.snappy, value: note.wordCount)
            Text("\(note.characterCount) \(l10n.t(.notes_chars))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.snappy, value: note.characterCount)
            if note.readingMinutes > 0 {
                Text("~\(note.readingMinutes) \(l10n.t(.notes_minRead))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showSaved {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                    Text(l10n.t(.notes_saved))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .offset(x: 4)))
            }
            Text(note.updated, style: .relative)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Text edits

    /// Pure helper: given a body string, append a suffix preserving trailing
    /// whitespace semantics.
    static func appendingText(_ body: String, _ insert: String) -> String {
        if body.isEmpty { return insert }
        if body.hasSuffix("\n") { return body + insert }
        return body + "\n" + insert
    }

    private func insert(_ text: String) {
        note.body = Self.appendingText(note.body, text)
    }

    private func insertLinePrefix(_ prefix: String) {
        // If body ends mid-line, drop onto next line so the prefix lines up.
        if note.body.isEmpty {
            note.body = prefix
            return
        }
        if note.body.hasSuffix("\n") {
            note.body += prefix
        } else {
            note.body += "\n" + prefix
        }
    }

    private func wrapSelection(with delimiter: String) {
        // Without live cursor access we can't wrap a real selection, so append
        // a formatting marker the user can fill in — common pattern in
        // menu-bar note tools.
        note.body += "\(delimiter)\(delimiter)"
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }

    private func copyAll() {
        let pb = NSPasteboard.general
        pb.clearContents()
        let full = (note.title.isEmpty ? "" : "# \(note.title)\n\n") + note.body
        pb.setString(full, forType: .string)
    }
}
