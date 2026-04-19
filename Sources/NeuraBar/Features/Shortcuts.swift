import SwiftUI
import AppKit

// MARK: - Model

struct ShortcutItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var path: String
    var icon: String     // SF Symbol fallback
    var kind: Kind
    var pinned: Bool = false
    var launchCount: Int = 0
    var lastLaunched: Date? = nil

    enum Kind: String, Codable, CaseIterable, Identifiable {
        case app, folder, url, command
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .app: return "app.fill"
            case .folder: return "folder.fill"
            case .url: return "link"
            case .command: return "terminal"
            }
        }

        var labelKey: Loc {
            switch self {
            case .app: return .shortcut_kind_app
            case .folder: return .shortcut_kind_folder
            case .url: return .shortcut_kind_url
            case .command: return .shortcut_kind_command
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, path, icon, kind, pinned, launchCount, lastLaunched
    }

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        icon: String,
        kind: Kind,
        pinned: Bool = false,
        launchCount: Int = 0,
        lastLaunched: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.icon = icon
        self.kind = kind
        self.pinned = pinned
        self.launchCount = launchCount
        self.lastLaunched = lastLaunched
    }

    // Tolerant decoder — old shortcuts.json lacks pinned/launchCount/lastLaunched.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        path = (try? c.decode(String.self, forKey: .path)) ?? ""
        icon = (try? c.decode(String.self, forKey: .icon)) ?? "star"
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .app
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
        launchCount = (try? c.decode(Int.self, forKey: .launchCount)) ?? 0
        lastLaunched = try? c.decode(Date.self, forKey: .lastLaunched)
    }
}

enum ShortcutFilter: String, CaseIterable, Identifiable {
    case all, app, folder, url, command
    var id: String { rawValue }

    var labelKey: Loc {
        switch self {
        case .all: return .todo_filter_all
        case .app: return .shortcut_kind_app
        case .folder: return .shortcut_kind_folder
        case .url: return .shortcut_kind_url
        case .command: return .shortcut_kind_command
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .app: return "app"
        case .folder: return "folder"
        case .url: return "link"
        case .command: return "terminal"
        }
    }
}

// MARK: - Store

final class ShortcutStore: ObservableObject {
    @Published var items: [ShortcutItem] {
        didSet { Persistence.save(items, to: "shortcuts.json") }
    }

    init() {
        if let loaded = Persistence.load([ShortcutItem].self, from: "shortcuts.json") {
            self.items = loaded
        } else {
            self.items = ShortcutStore.defaultItems
        }
    }

    static let defaultItems: [ShortcutItem] = [
        .init(name: "Cursor", path: "/Applications/Cursor.app",
              icon: "chevron.left.slash.chevron.right", kind: .app),
        .init(name: "Terminal", path: "/System/Applications/Utilities/Terminal.app",
              icon: "terminal", kind: .app),
        .init(name: "Safari", path: "/Applications/Safari.app", icon: "safari", kind: .app),
        .init(name: "Desktop", path: NSString(string: "~/Desktop").expandingTildeInPath,
              icon: "menubar.dock.rectangle", kind: .folder),
        .init(name: "Downloads", path: NSString(string: "~/Downloads").expandingTildeInPath,
              icon: "arrow.down.circle", kind: .folder),
        .init(name: "Projects", path: NSString(string: "~/Desktop/Projects").expandingTildeInPath,
              icon: "folder.fill", kind: .folder),
        .init(name: "GitHub", path: "https://github.com", icon: "cat.fill", kind: .url),
        .init(name: "Claude", path: "https://claude.ai", icon: "sparkles", kind: .url)
    ]

    func launch(_ item: ShortcutItem) {
        recordLaunch(item)
        switch item.kind {
        case .app, .folder:
            let url = URL(fileURLWithPath: item.path)
            NSWorkspace.shared.open(url)
        case .url:
            if let url = URL(string: item.path) { NSWorkspace.shared.open(url) }
        case .command:
            runShell(item.path)
        }
    }

    private func runShell(_ cmd: String) {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c", cmd]
        try? task.run()
    }

    private func recordLaunch(_ item: ShortcutItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].launchCount += 1
            items[idx].lastLaunched = Date()
        }
    }

    func add(_ item: ShortcutItem) { items.append(item) }
    func remove(_ item: ShortcutItem) { items.removeAll { $0.id == item.id } }

    func togglePin(_ item: ShortcutItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].pinned.toggle()
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Sort / filter

    /// Sort: pinned → highest launch count → most recently launched → original order.
    static func sort(_ items: [ShortcutItem]) -> [ShortcutItem] {
        items.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.launchCount != b.launchCount { return a.launchCount > b.launchCount }
            switch (a.lastLaunched, b.lastLaunched) {
            case let (la?, lb?): return la > lb
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return false
            }
        }
    }

    func filter(query: String, kind: ShortcutFilter) -> [ShortcutItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            let kindMatch: Bool
            switch kind {
            case .all: kindMatch = true
            case .app: kindMatch = item.kind == .app
            case .folder: kindMatch = item.kind == .folder
            case .url: kindMatch = item.kind == .url
            case .command: kindMatch = item.kind == .command
            }
            guard kindMatch else { return false }
            if q.isEmpty { return true }
            return item.name.lowercased().contains(q) || item.path.lowercased().contains(q)
        }
    }

    // MARK: - Icon fetching

    /// Returns an NSImage for app / folder shortcuts, backed by the real file
    /// system icon (app icon or folder custom icon). Pure function — safe for
    /// tests that pass synthetic paths.
    static func systemIcon(for item: ShortcutItem) -> NSImage? {
        guard item.kind == .app || item.kind == .folder else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: item.path) else { return nil }
        return NSWorkspace.shared.icon(forFile: item.path)
    }
}

// MARK: - View

struct ShortcutsView: View {
    @EnvironmentObject var store: ShortcutStore
    @EnvironmentObject var l10n: Localization

    @State private var search: String = ""
    @State private var filter: ShortcutFilter = .all
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 8) {
            searchRow
            filterChips
            grid
        }
        .sheet(isPresented: $showAdd) {
            AddShortcutSheet()
                .environmentObject(store)
                .environmentObject(l10n)
        }
    }

    private var searchRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(l10n.t(.search), text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 6)
            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(PressableStyle())
            .help(l10n.t(.shortcut_addTitle))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06))
        )
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ShortcutFilter.allCases) { f in
                    filterChip(f)
                }
            }
        }
        .frame(height: 22)
    }

    private func filterChip(_ f: ShortcutFilter) -> some View {
        let active = filter == f
        return Button {
            withAnimation(.spring(duration: 0.22, bounce: 0.2)) { filter = f }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: f.icon)
                    .font(.system(size: 9, weight: .medium))
                Text(l10n.t(f.labelKey))
                    .font(.system(size: 10, weight: active ? .semibold : .medium))
            }
            .foregroundStyle(active ? Color.accentColor : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(active ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(PressableStyle())
    }

    private var grid: some View {
        let filtered = ShortcutStore.sort(
            store.filter(query: search, kind: filter)
        )
        return Group {
            if filtered.isEmpty {
                EmptyState(icon: "square.grid.2x2", text: l10n.t(.shortcut_empty))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 86), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                            ShortcutTile(item: item, quickLaunchIndex: index < 9 ? index + 1 : nil)
                                .environmentObject(store)
                                .environmentObject(l10n)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity.combined(with: .scale(scale: 0.9))
                                ))
                        }
                    }
                    .padding(.vertical, 4)
                    .animation(.spring(duration: 0.26, bounce: 0.18), value: store.items)
                }
            }
        }
    }
}

// MARK: - Tile

struct ShortcutTile: View {
    let item: ShortcutItem
    let quickLaunchIndex: Int?
    @EnvironmentObject var store: ShortcutStore
    @EnvironmentObject var l10n: Localization
    @State private var hover = false

    var body: some View {
        Button {
            store.launch(item)
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    if let nsImage = ShortcutStore.systemIcon(for: item) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: item.icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .frame(width: 32, height: 32)
                    }
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Circle().fill(.orange))
                            .offset(x: 12, y: -12)
                    }
                }

                Text(item.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                if let n = quickLaunchIndex, hover {
                    Text("⌘\(n)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(hover ? 0.1 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(item.pinned ? Color.orange.opacity(0.35) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .contextMenu {
            Button(item.pinned ? l10n.t(.shortcut_unpin) : l10n.t(.shortcut_pin)) {
                store.togglePin(item)
            }
            if item.launchCount > 0 {
                Text("\(l10n.t(.shortcut_launches)): \(item.launchCount)")
                    .foregroundStyle(.secondary)
            }
            Button("Copy path") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(item.path, forType: .string)
            }
            Divider()
            Button(l10n.t(.shortcut_remove), role: .destructive) {
                store.remove(item)
            }
        }
        .background(quickLaunchShortcut)
    }

    @ViewBuilder
    private var quickLaunchShortcut: some View {
        if let n = quickLaunchIndex,
           let key = KeyEquivalent(String(n).first ?? "0") as KeyEquivalent? {
            Button("") { store.launch(item) }
                .keyboardShortcut(key, modifiers: [.command])
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }
}

// MARK: - Add sheet

struct AddShortcutSheet: View {
    @EnvironmentObject var store: ShortcutStore
    @EnvironmentObject var l10n: Localization
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var path = ""
    @State private var icon = "star"
    @State private var kind: ShortcutItem.Kind = .app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t(.shortcut_addTitle))
                .font(.system(size: 16, weight: .semibold))

            Picker(l10n.t(.shortcut_type), selection: $kind) {
                Text(l10n.t(.shortcut_kind_app)).tag(ShortcutItem.Kind.app)
                Text(l10n.t(.shortcut_kind_folder)).tag(ShortcutItem.Kind.folder)
                Text(l10n.t(.shortcut_kind_url)).tag(ShortcutItem.Kind.url)
                Text(l10n.t(.shortcut_kind_command)).tag(ShortcutItem.Kind.command)
            }
            .pickerStyle(.segmented)
            .onChange(of: kind) { _, new in icon = new.icon }

            TextField(l10n.t(.shortcut_name), text: $name).textFieldStyle(.roundedBorder)
            TextField(l10n.t(.shortcut_pathOrUrl), text: $path).textFieldStyle(.roundedBorder)
            TextField(l10n.t(.shortcut_symbol), text: $icon).textFieldStyle(.roundedBorder)

            if kind == .app || kind == .folder {
                Button(l10n.t(.shortcut_pick)) { pickFile() }
            }

            HStack {
                Spacer()
                Button(l10n.t(.cancel)) { dismiss() }
                Button(l10n.t(.add)) {
                    store.add(.init(name: name, path: path, icon: icon, kind: kind))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || path.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = (kind == .folder)
        panel.canChooseFiles = (kind == .app)
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
            if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
        }
    }
}
