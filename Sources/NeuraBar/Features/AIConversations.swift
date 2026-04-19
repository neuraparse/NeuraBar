import Foundation
import SwiftUI

// MARK: - Model

struct AIConversation: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var providerName: String?
    var pinned: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, messages, createdAt, updatedAt, providerName, pinned
    }

    init(
        id: UUID = UUID(),
        title: String,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        providerName: String? = nil,
        pinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.providerName = providerName
        self.pinned = pinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        messages = (try? c.decode([ChatMessage].self, forKey: .messages)) ?? []
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? createdAt
        providerName = try? c.decode(String.self, forKey: .providerName)
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
    }

    /// Convenience: last text the user sent, for preview in list.
    var preview: String {
        messages
            .last(where: { $0.role == .user || $0.role == .assistant })
            .map { $0.text.replacingOccurrences(of: "\n", with: " ") } ?? ""
    }
}

// MARK: - Store

final class AIConversationStore: ObservableObject {
    @Published var items: [AIConversation] {
        didSet { persist() }
    }
    @Published var currentID: UUID?

    private let file = "conversations.json"
    private var persistTimer: Timer?

    init() {
        let loaded = Persistence.load([AIConversation].self, from: "conversations.json") ?? []
        self.items = loaded
        self.currentID = loaded.sorted(by: { $0.updatedAt > $1.updatedAt }).first?.id
    }

    // Streaming messages fire this setter many times per second — coalesce.
    private func persist() {
        persistTimer?.invalidate()
        persistTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Persistence.save(self.items, to: self.file)
        }
    }

    // MARK: - CRUD

    @discardableResult
    func newConversation(title: String? = nil, providerName: String? = nil) -> AIConversation {
        let conv = AIConversation(
            title: title ?? Self.placeholderTitle,
            providerName: providerName
        )
        items.insert(conv, at: 0)
        currentID = conv.id
        return conv
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        if currentID == id {
            currentID = items.first?.id
        }
    }

    func rename(_ id: UUID, to newTitle: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        items[idx].title = trimmed.isEmpty ? Self.placeholderTitle : trimmed
    }

    func togglePin(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinned.toggle()
    }

    func duplicate(_ id: UUID) -> AIConversation? {
        guard let src = items.first(where: { $0.id == id }) else { return nil }
        let copy = AIConversation(
            title: src.title + " (copy)",
            messages: src.messages,
            providerName: src.providerName
        )
        items.insert(copy, at: 0)
        currentID = copy.id
        return copy
    }

    // MARK: - Current conversation helpers

    var current: AIConversation? {
        guard let id = currentID else { return nil }
        return items.first(where: { $0.id == id })
    }

    /// Returns the current conversation's messages, or empty if none selected.
    var currentMessages: [ChatMessage] {
        current?.messages ?? []
    }

    /// Append a message to the current conversation, creating one on demand.
    /// Auto-titles from the first user message if the conversation is still
    /// using the placeholder title.
    @discardableResult
    func append(_ message: ChatMessage, providerName: String? = nil) -> UUID {
        if currentID == nil {
            newConversation(providerName: providerName)
        }
        guard let cid = currentID,
              let idx = items.firstIndex(where: { $0.id == cid }) else {
            return message.id
        }
        items[idx].messages.append(message)
        items[idx].updatedAt = Date()
        if let p = providerName { items[idx].providerName = p }
        // Auto-generate title after first user message
        if items[idx].title == Self.placeholderTitle && message.role == .user {
            items[idx].title = Self.autoTitle(for: message.text)
        }
        return message.id
    }

    /// Update an existing message (used while streaming chunks into an
    /// assistant bubble).
    func updateMessage(id: UUID, transform: (inout ChatMessage) -> Void) {
        guard let cid = currentID,
              let ci = items.firstIndex(where: { $0.id == cid }),
              let mi = items[ci].messages.firstIndex(where: { $0.id == id }) else { return }
        transform(&items[ci].messages[mi])
        items[ci].updatedAt = Date()
    }

    func removeMessage(id: UUID) {
        guard let cid = currentID,
              let ci = items.firstIndex(where: { $0.id == cid }) else { return }
        items[ci].messages.removeAll { $0.id == id }
    }

    /// Sort: pinned first, then most-recently updated.
    var sorted: [AIConversation] {
        items.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.updatedAt > b.updatedAt
        }
    }

    /// Filter by free-text (title, message bodies).
    func filter(_ query: String) -> [AIConversation] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sorted }
        return sorted.filter { conv in
            conv.title.lowercased().contains(q)
                || conv.messages.contains(where: { $0.text.lowercased().contains(q) })
        }
    }

    // MARK: - Helpers

    /// Placeholder name used for a freshly created conversation before the user
    /// types a first message. Also the trigger for auto-rename.
    static let placeholderTitle = "New chat"

    /// Derive a conversation title from the given user input. Pure for tests.
    static func autoTitle(for text: String, maxLength: Int = 40) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed
            .split(whereSeparator: { $0.isNewline })
            .first
            .map(String.init) ?? ""
        if firstLine.count <= maxLength { return firstLine }
        return String(firstLine.prefix(maxLength - 1)) + "…"
    }
}
