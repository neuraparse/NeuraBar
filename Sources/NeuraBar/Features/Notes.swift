import SwiftUI

struct NoteItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var body: String
    var updated: Date
}

final class NoteStore: ObservableObject {
    @Published var items: [NoteItem] {
        didSet { Persistence.save(items, to: "notes.json") }
    }

    init() {
        self.items = Persistence.load([NoteItem].self, from: "notes.json") ?? [
            NoteItem(title: L.t(.notes_new), body: "", updated: Date())
        ]
    }

    func new() {
        items.insert(NoteItem(title: L.t(.notes_new), body: "", updated: Date()), at: 0)
    }

    func update(_ note: NoteItem) {
        if let i = items.firstIndex(where: { $0.id == note.id }) {
            items[i] = note
            items[i].updated = Date()
        }
    }

    func remove(_ note: NoteItem) {
        items.removeAll { $0.id == note.id }
    }
}

struct NotesView: View {
    @EnvironmentObject var store: NoteStore
    @EnvironmentObject var l10n: Localization
    @State private var selected: NoteItem?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(l10n.t(.notes_title)).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).textCase(.uppercase)
                    Spacer()
                    Button {
                        store.new()
                        selected = store.items.first
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.items) { note in
                            Button {
                                selected = note
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(note.title.isEmpty ? l10n.t(.notes_untitled) : note.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    Text(note.body)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selected?.id == note.id ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(l10n.t(.delete), role: .destructive) { store.remove(note) }
                            }
                        }
                    }
                }
            }
            .frame(width: 150)

            if let sel = selected ?? store.items.first {
                NoteEditor(note: sel)
                    .environmentObject(store)
                    .environmentObject(l10n)
                    .id(sel.id)
            } else {
                EmptyState(icon: "note.text", text: l10n.t(.notes_empty))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selected == nil { selected = store.items.first }
        }
    }
}

struct NoteEditor: View {
    @State var note: NoteItem
    @EnvironmentObject var store: NoteStore
    @EnvironmentObject var l10n: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(l10n.t(.notes_titlePlaceholder), text: $note.title)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .onChange(of: note.title) { store.update(note) }

            TextEditor(text: $note.body)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)
                .onChange(of: note.body) { store.update(note) }
        }
    }
}
