import SwiftUI
import AppKit

struct ClipItem: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    let text: String
    let date: Date
    var pinned: Bool = false
}

final class ClipboardManager: ObservableObject {
    @Published var items: [ClipItem] = [] {
        didSet { schedulePersist() }
    }
    private var lastChange: Int = -1
    private var timer: Timer?
    private var persistTimer: Timer?
    let maxItems = 200
    private let file = "clipboard.json"

    init() {
        if let saved = Persistence.load([ClipItem].self, from: file) {
            self.items = saved
        }
    }

    func start() {
        timer?.invalidate()
        lastChange = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        guard let s = pb.string(forType: .string) else { return }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 100_000 else { return }
        // Dedupe: if this exact text already exists, move it to the top.
        if let idx = items.firstIndex(where: { $0.text == trimmed }) {
            let existing = items.remove(at: idx)
            items.insert(existing, at: 0)
            return
        }
        items.insert(ClipItem(text: trimmed, date: Date()), at: 0)
        trim()
        // Status feedback is delivered via the menu bar icon (brief animation)
        // instead of an in-app toast. See MenuBarStatusCoordinator.
        Task { @MainActor in
            MenuBarStatusCoordinator.shared.flash(.clipboardCopied)
        }
    }

    private func trim() {
        // Keep all pinned + most recent unpinned up to maxItems total.
        let pinned = items.filter { $0.pinned }
        let unpinned = items.filter { !$0.pinned }
        let keepUnpinned = Array(unpinned.prefix(max(0, maxItems - pinned.count)))
        let merged = items.filter { i in
            pinned.contains(where: { $0.id == i.id }) || keepUnpinned.contains(where: { $0.id == i.id })
        }
        if merged.count != items.count { items = merged }
    }

    func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        lastChange = pb.changeCount
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            let c = items.remove(at: idx)
            items.insert(c, at: 0)
        }
        Task { @MainActor in
            MenuBarStatusCoordinator.shared.flash(.clipboardCopied)
        }
    }

    func togglePin(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].pinned.toggle()
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll { !$0.pinned }
    }

    // Coalesce rapid writes; clipboard ticks every second.
    private func schedulePersist() {
        persistTimer?.invalidate()
        persistTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Persistence.save(self.items, to: self.file)
        }
    }
}

struct ClipboardView: View {
    @EnvironmentObject var clip: ClipboardManager
    @EnvironmentObject var l10n: Localization
    @State private var search: String = ""

    var filtered: [ClipItem] {
        let base = clip.items
        let ordered = base.sorted { (a, b) in
            if a.pinned != b.pinned { return a.pinned && !b.pinned }
            return a.date > b.date
        }
        guard !search.isEmpty else { return ordered }
        return ordered.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(l10n.t(.clip_searchPlaceholder), text: $search).textFieldStyle(.plain)
                if !clip.items.isEmpty {
                    Button { clip.clear() } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.t(.auto_clearHistory))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))

            HStack(spacing: 10) {
                Text("\(clip.items.count)").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if clip.items.contains(where: { $0.pinned }) {
                    HStack(spacing: 2) {
                        Image(systemName: "pin.fill").font(.system(size: 9))
                        Text("\(clip.items.filter { $0.pinned }.count)")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.orange)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            if filtered.isEmpty {
                EmptyState(icon: "doc.on.clipboard", text: l10n.t(.clip_empty))
                    .multilineTextAlignment(.center)
                    .padding(.top, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filtered) { item in
                            ClipRow(item: item).environmentObject(clip)
                        }
                    }
                }
            }
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    @EnvironmentObject var clip: ClipboardManager
    @State private var hover = false
    @State private var copied = false

    var body: some View {
        Button {
            clip.copy(item)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { copied = false }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text)
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.date, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if hover {
                    Button {
                        clip.togglePin(item)
                    } label: {
                        Image(systemName: item.pinned ? "pin.slash" : "pin")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(copied ? .green : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hover ? 0.08 : 0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            Button(item.pinned ? "Unpin" : "Pin") { clip.togglePin(item) }
            Button("Delete", role: .destructive) { clip.remove(item) }
        }
    }
}
