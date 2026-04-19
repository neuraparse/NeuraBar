import SwiftUI
import AppKit

// MARK: - Model

enum TodoPriority: String, CaseIterable, Codable, Identifiable {
    case low, normal, high
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .low: return .gray
        case .normal: return .blue
        case .high: return .red
        }
    }

    var icon: String {
        switch self {
        case .low: return "arrow.down"
        case .normal: return "equal"
        case .high: return "exclamationmark"
        }
    }

    var sortWeight: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var done: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date? = nil
    var dueDate: Date? = nil
    var priority: TodoPriority = .normal
    var tag: String = ""

    /// Hashtag tokens extracted from the title, case-insensitive + deduped.
    var tags: [String] {
        let pattern = #"#([\p{L}\d_-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        var out = Set<String>()
        regex.enumerateMatches(in: title, options: [], range: range) { match, _, _ in
            if let m = match, let r = Range(m.range(at: 1), in: title) {
                out.insert(String(title[r]).lowercased())
            }
        }
        // Include the legacy explicit tag too for backward compatibility.
        if !tag.isEmpty { out.insert(tag.lowercased()) }
        return Array(out).sorted()
    }

    // Tolerant decoder so todos.json files from earlier versions keep working.
    enum CodingKeys: String, CodingKey {
        case id, title, done, createdAt, completedAt, dueDate, priority, tag
    }

    init(
        id: UUID = UUID(),
        title: String,
        done: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        dueDate: Date? = nil,
        priority: TodoPriority = .normal,
        tag: String = ""
    ) {
        self.id = id
        self.title = title
        self.done = done
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.dueDate = dueDate
        self.priority = priority
        self.tag = tag
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        completedAt = try? c.decode(Date.self, forKey: .completedAt)
        dueDate = try? c.decode(Date.self, forKey: .dueDate)
        priority = (try? c.decode(TodoPriority.self, forKey: .priority)) ?? .normal
        tag = (try? c.decode(String.self, forKey: .tag)) ?? ""
    }
}

enum TodoBucket: String, CaseIterable {
    case overdue, today, tomorrow, thisWeek, later, noDate, completed

    var titleKey: Loc {
        switch self {
        case .overdue:   return .todo_group_overdue
        case .today:     return .todo_group_today
        case .tomorrow:  return .todo_group_tomorrow
        case .thisWeek:  return .todo_group_thisWeek
        case .later:     return .todo_group_later
        case .noDate:    return .todo_group_noDate
        case .completed: return .todo_group_completed
        }
    }

    var accent: Color {
        switch self {
        case .overdue:  return .red
        case .today:    return .orange
        case .tomorrow: return .yellow
        case .thisWeek: return .blue
        case .later:    return .teal
        case .noDate:   return .gray
        case .completed: return .green
        }
    }
}

// MARK: - Store

final class TodoStore: ObservableObject {
    @Published var items: [TodoItem] {
        didSet { Persistence.save(items, to: "todos.json") }
    }

    init() {
        self.items = Persistence.load([TodoItem].self, from: "todos.json") ?? []
    }

    @discardableResult
    func add(_ title: String, tag: String = "", priority: TodoPriority = .normal, dueDate: Date? = nil) -> TodoItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = TodoItem(title: trimmed, priority: priority, tag: tag)
        var newItem = item
        newItem.dueDate = dueDate
        items.insert(newItem, at: 0)
        return newItem
    }

    func toggle(_ item: TodoItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].done.toggle()
        items[idx].completedAt = items[idx].done ? Date() : nil
    }

    func remove(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
    }

    func setPriority(_ priority: TodoPriority, for item: TodoItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].priority = priority
        }
    }

    func setDueDate(_ date: Date?, for item: TodoItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].dueDate = date
        }
    }

    func clearCompleted() {
        items.removeAll { $0.done }
    }

    var allTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in items where !item.done {
            for t in item.tags { counts[t, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    // MARK: - Filtering / sorting

    func filter(_ query: String) -> [TodoItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { t in
            t.title.lowercased().contains(q) || t.tags.contains(where: { $0.contains(q) })
        }
    }

    /// Sort: highest priority first, then earliest due date, then newest
    /// created. Completed items are pushed to the end.
    static func sort(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { a, b in
            if a.done != b.done { return !a.done }
            if a.priority.sortWeight != b.priority.sortWeight {
                return a.priority.sortWeight < b.priority.sortWeight
            }
            switch (a.dueDate, b.dueDate) {
            case let (da?, db?): return da < db
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.createdAt > b.createdAt
            }
        }
    }

    static func group(_ items: [TodoItem], now: Date = Date()) -> [(TodoBucket, [TodoItem])] {
        var overdue: [TodoItem] = []
        var today: [TodoItem] = []
        var tomorrow: [TodoItem] = []
        var week: [TodoItem] = []
        var later: [TodoItem] = []
        var noDate: [TodoItem] = []
        var completed: [TodoItem] = []

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        let startOfDayAfter = cal.date(byAdding: .day, value: 2, to: startOfToday) ?? startOfToday
        let startOfWeek = cal.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday

        for t in items {
            if t.done { completed.append(t); continue }
            guard let due = t.dueDate else { noDate.append(t); continue }
            if due < startOfToday { overdue.append(t) }
            else if due < startOfTomorrow { today.append(t) }
            else if due < startOfDayAfter { tomorrow.append(t) }
            else if due < startOfWeek { week.append(t) }
            else { later.append(t) }
        }

        var out: [(TodoBucket, [TodoItem])] = []
        if !overdue.isEmpty   { out.append((.overdue, overdue)) }
        if !today.isEmpty     { out.append((.today, today)) }
        if !tomorrow.isEmpty  { out.append((.tomorrow, tomorrow)) }
        if !week.isEmpty      { out.append((.thisWeek, week)) }
        if !later.isEmpty     { out.append((.later, later)) }
        if !noDate.isEmpty    { out.append((.noDate, noDate)) }
        if !completed.isEmpty { out.append((.completed, completed)) }
        return out
    }

    // MARK: - Progress

    var progress: (done: Int, total: Int) {
        let total = items.count
        let done = items.filter { $0.done }.count
        return (done, total)
    }
}

// MARK: - View

struct TodoView: View {
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var l10n: Localization

    @State private var newText: String = ""
    @State private var search: String = ""
    @State private var activeTag: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            inputRow
            tagChips
            list
            footer
        }
        .background(shortcutSink)
    }

    // MARK: Header with progress ring

    private var header: some View {
        let (done, total) = store.progress
        let fraction = total == 0 ? 0 : Double(done) / Double(total)
        return HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        LinearGradient(colors: [.blue, .purple],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: fraction)
                Text("\(total - done)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: total - done)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(total - done == 0 ? l10n.t(.todo_allDone) : "\(total - done) \(l10n.t(.todo_countActive))")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(done) / \(total) \(l10n.t(.todo_doneCountSuffix))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                TextField(l10n.t(.search), text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(minWidth: 80, idealWidth: 120)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
    }

    // MARK: Input

    private var inputRow: some View {
        HStack(spacing: 6) {
            TextField(l10n.t(.todo_newPlaceholder), text: $newText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
                .onSubmit(addNew)

            Button(action: addNew) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.bounce, value: store.items.count)
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }

    // MARK: Tag chips

    private var tagChips: some View {
        let tags = store.allTags
        return Group {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        chip(label: l10n.t(.todo_filter_all), active: activeTag == nil) {
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
                .frame(height: 20)
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

    // MARK: List

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                let filtered = filteredItems
                if filtered.isEmpty {
                    emptyHint
                } else {
                    ForEach(TodoStore.group(filtered), id: \.0) { bucket, items in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(bucket.accent)
                                .frame(width: 5, height: 5)
                            Text(l10n.t(bucket.titleKey))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .kerning(0.4)
                            Text("\(items.count)")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 6)
                        .padding(.bottom, 2)

                        ForEach(TodoStore.sort(items)) { item in
                            TodoRow(item: item)
                                .environmentObject(store)
                                .environmentObject(l10n)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: -4)),
                                    removal: .opacity.combined(with: .scale(scale: 0.95))
                                ))
                        }
                    }
                }
            }
            .animation(.spring(duration: 0.26, bounce: 0.18), value: store.items)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: search.isEmpty && activeTag == nil ? "checkmark.seal" : "magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(search.isEmpty && activeTag == nil
                 ? l10n.t(.todo_empty)
                 : l10n.t(.todo_noMatch))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if store.items.contains(where: { $0.done }) {
                Button(l10n.t(.todo_clearCompleted)) { store.clearCompleted() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            Spacer()
            Text(l10n.t(.todo_tip))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Derived

    private var filteredItems: [TodoItem] {
        var list = store.filter(search)
        if let t = activeTag {
            list = list.filter { $0.tags.contains(t) }
        }
        return list
    }

    private func addNew() {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Inline priority flag — "!!" prefix = high, "!" = high shorthand,
        // otherwise normal. Keeps the input minimal.
        var priority: TodoPriority = .normal
        var title = trimmed
        if title.hasPrefix("!!") {
            priority = .high
            title = String(title.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        } else if title.hasPrefix("!") {
            priority = .high
            title = String(title.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        store.add(title, priority: priority)
        newText = ""
    }

    // Invisible shortcuts (only active while Todos tab is visible).
    private var shortcutSink: some View {
        VStack {
            Button("") { store.clearCompleted() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .frame(width: 0, height: 0).opacity(0)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Row

struct TodoRow: View {
    let item: TodoItem
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var l10n: Localization
    @State private var hover = false
    @State private var showPriorityMenu = false

    var body: some View {
        HStack(spacing: 8) {
            // Priority indicator
            if item.priority != .normal && !item.done {
                RoundedRectangle(cornerRadius: 1)
                    .fill(item.priority.color)
                    .frame(width: 2.5)
                    .padding(.vertical, 2)
            } else {
                Spacer().frame(width: 2.5)
            }

            Button {
                withAnimation(.spring(duration: 0.3, bounce: 0.4)) {
                    store.toggle(item)
                }
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(item.done ? Color.accentColor : .secondary)
                    .symbolEffect(.bounce, value: item.done)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(renderedTitle)
                    .font(.system(size: 12))
                    .strikethrough(item.done, pattern: .solid)
                    .foregroundStyle(item.done ? .secondary : .primary)
                    .lineLimit(2)
                    .animation(.easeInOut(duration: 0.2), value: item.done)

                HStack(spacing: 6) {
                    if let due = item.dueDate, !item.done {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar")
                                .font(.system(size: 8))
                            Text(shortDueDate(due))
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(dueDateColor(due))
                    }
                    ForEach(item.tags.prefix(3), id: \.self) { t in
                        Text("#\(t)")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    if item.priority == .high && !item.done {
                        Text(l10n.t(.todo_priority_high))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            if hover && !item.done {
                Menu {
                    Picker(l10n.t(.todo_priority), selection: Binding(
                        get: { item.priority },
                        set: { store.setPriority($0, for: item) }
                    )) {
                        Text(l10n.t(.todo_priority_low)).tag(TodoPriority.low)
                        Text(l10n.t(.todo_priority_normal)).tag(TodoPriority.normal)
                        Text(l10n.t(.todo_priority_high)).tag(TodoPriority.high)
                    }
                    Divider()
                    Button(l10n.t(.todo_dueToday)) {
                        store.setDueDate(Date(), for: item)
                    }
                    Button(l10n.t(.todo_dueTomorrow)) {
                        store.setDueDate(Calendar.current.date(byAdding: .day, value: 1, to: Date()), for: item)
                    }
                    Button(l10n.t(.todo_dueNextWeek)) {
                        store.setDueDate(Calendar.current.date(byAdding: .day, value: 7, to: Date()), for: item)
                    }
                    if item.dueDate != nil {
                        Button(l10n.t(.todo_dueClear)) {
                            store.setDueDate(nil, for: item)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            if hover {
                Button {
                    withAnimation(.spring(duration: 0.2, bounce: 0.15)) {
                        store.remove(item)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hover ? 0.06 : 0.03))
        )
        .onHover { hover = $0 }
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(item.done ? l10n.t(.todo_markActive) : l10n.t(.todo_markDone)) {
            store.toggle(item)
        }
        Menu(l10n.t(.todo_priority)) {
            ForEach(TodoPriority.allCases) { p in
                Button {
                    store.setPriority(p, for: item)
                } label: {
                    Label(priorityLabel(p), systemImage: p.icon)
                }
            }
        }
        Divider()
        Button(l10n.t(.delete), role: .destructive) {
            store.remove(item)
        }
    }

    private func priorityLabel(_ p: TodoPriority) -> String {
        switch p {
        case .low: return l10n.t(.todo_priority_low)
        case .normal: return l10n.t(.todo_priority_normal)
        case .high: return l10n.t(.todo_priority_high)
        }
    }

    /// Strip hashtag tokens and the explicit tag string from the visible title.
    private var renderedTitle: String {
        var t = item.title
        t = t.replacingOccurrences(of: #"#[\p{L}\d_-]+"#, with: "",
                                   options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    private func shortDueDate(_ date: Date) -> String {
        let cal = Calendar.current
        let now = Date()
        if cal.isDateInToday(date) { return l10n.t(.todo_group_today) }
        if cal.isDateInYesterday(date) { return "yday" }
        if cal.isDate(date, inSameDayAs: cal.date(byAdding: .day, value: 1, to: now) ?? now) {
            return l10n.t(.todo_group_tomorrow)
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func dueDateColor(_ date: Date) -> Color {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        if date < startOfToday { return .red }
        if cal.isDateInToday(date) { return .orange }
        return .secondary
    }
}

// MARK: - Empty state

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
