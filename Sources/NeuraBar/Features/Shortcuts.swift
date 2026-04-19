import SwiftUI
import AppKit

struct ShortcutItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var path: String    // file path for .app or folder, or URL
    var icon: String    // SF Symbol name
    var kind: Kind

    enum Kind: String, Codable { case app, folder, url, command }
}

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
        .init(name: "Cursor",  path: "/Applications/Cursor.app",
              icon: "chevron.left.slash.chevron.right", kind: .app),
        .init(name: "Terminal", path: "/System/Applications/Utilities/Terminal.app",
              icon: "terminal", kind: .app),
        .init(name: "Safari", path: "/Applications/Safari.app", icon: "safari", kind: .app),
        .init(name: "Masaüstü", path: NSString(string: "~/Desktop").expandingTildeInPath,
              icon: "menubar.dock.rectangle", kind: .folder),
        .init(name: "Downloads", path: NSString(string: "~/Downloads").expandingTildeInPath,
              icon: "arrow.down.circle", kind: .folder),
        .init(name: "Projects", path: NSString(string: "~/Desktop/Projects").expandingTildeInPath,
              icon: "folder.fill", kind: .folder),
        .init(name: "GitHub", path: "https://github.com", icon: "cat.fill", kind: .url),
        .init(name: "Claude", path: "https://claude.ai", icon: "sparkles", kind: .url)
    ]

    func launch(_ item: ShortcutItem) {
        switch item.kind {
        case .app, .folder:
            let url = URL(fileURLWithPath: item.path)
            NSWorkspace.shared.open(url)
        case .url:
            if let url = URL(string: item.path) {
                NSWorkspace.shared.open(url)
            }
        case .command:
            runShell(item.path)
        }
    }

    func runShell(_ cmd: String) {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c", cmd]
        try? task.run()
    }

    func add(_ item: ShortcutItem) { items.append(item) }
    func remove(_ item: ShortcutItem) { items.removeAll { $0.id == item.id } }
}

struct ShortcutsView: View {
    @EnvironmentObject var store: ShortcutStore
    @EnvironmentObject var l10n: Localization
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(l10n.t(.shortcut_quickAccess))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            if store.items.isEmpty {
                EmptyState(icon: "square.grid.2x2", text: l10n.t(.shortcut_empty))
                    .padding(.top, 40)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                        ForEach(store.items) { item in
                            ShortcutTile(item: item)
                                .environmentObject(store)
                                .environmentObject(l10n)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddShortcutSheet()
                .environmentObject(store)
                .environmentObject(l10n)
        }
    }
}

struct ShortcutTile: View {
    let item: ShortcutItem
    @EnvironmentObject var store: ShortcutStore
    @EnvironmentObject var l10n: Localization
    @State private var hover = false

    var body: some View {
        Button {
            store.launch(item)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .top, endPoint: .bottom
                    ))
                Text(item.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 66)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(hover ? 0.1 : 0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            Button(l10n.t(.shortcut_remove), role: .destructive) {
                store.remove(item)
            }
        }
    }
}

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
