import SwiftUI

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var done: Bool = false
    var createdAt: Date = Date()
    var tag: String = ""
}

final class TodoStore: ObservableObject {
    @Published var items: [TodoItem] {
        didSet { Persistence.save(items, to: "todos.json") }
    }

    init() {
        self.items = Persistence.load([TodoItem].self, from: "todos.json") ?? []
    }

    func add(_ title: String, tag: String = "") {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.insert(TodoItem(title: trimmed, tag: tag), at: 0)
    }

    func toggle(_ item: TodoItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].done.toggle()
    }

    func remove(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
    }

    func clearCompleted() {
        items.removeAll { $0.done }
    }
}

struct TodoView: View {
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var l10n: Localization
    @State private var newText: String = ""
    @State private var newTag: String = ""
    @State private var filter: Filter = .active

    enum Filter: String, CaseIterable { case active, all, done }

    func filterTitle(_ f: Filter) -> String {
        switch f {
        case .active: return l10n.t(.todo_filter_active)
        case .all: return l10n.t(.todo_filter_all)
        case .done: return l10n.t(.todo_filter_done)
        }
    }

    var filtered: [TodoItem] {
        switch filter {
        case .active: return store.items.filter { !$0.done }
        case .all: return store.items
        case .done: return store.items.filter { $0.done }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inputRow

            Picker("", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Text(filterTitle(f)).tag(f)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                LazyVStack(spacing: 6) {
                    if filtered.isEmpty {
                        EmptyState(icon: "checkmark.circle", text: l10n.t(.todo_empty))
                            .padding(.top, 40)
                    }
                    ForEach(filtered) { item in
                        TodoRow(item: item)
                            .environmentObject(store)
                    }
                }
            }

            HStack {
                Text("\(store.items.filter { !$0.done }.count) \(l10n.t(.todo_countActive))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(l10n.t(.todo_clearCompleted)) { store.clearCompleted() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }

    private var inputRow: some View {
        HStack(spacing: 6) {
            TextField(l10n.t(.todo_newPlaceholder), text: $newText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
                .onSubmit { add() }

            TextField(l10n.t(.todo_tagPlaceholder), text: $newTag)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(width: 70)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )

            Button {
                add()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    private func add() {
        store.add(newText, tag: newTag)
        newText = ""
        newTag = ""
    }
}

struct TodoRow: View {
    let item: TodoItem
    @EnvironmentObject var store: TodoStore

    var body: some View {
        HStack(spacing: 10) {
            Button {
                store.toggle(item)
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(item.done ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13))
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? .secondary : .primary)
                if !item.tag.isEmpty {
                    Text(item.tag)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.14))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            Button {
                store.remove(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

struct EmptyState: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
