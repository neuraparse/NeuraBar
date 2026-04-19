import XCTest
@testable import NeuraBar

final class AIConversationTests: NBTestCase {

    // MARK: - CRUD

    func testNewConversationBecomesCurrent() {
        let s = AIConversationStore()
        s.items = []
        let conv = s.newConversation()
        XCTAssertEqual(s.currentID, conv.id)
        XCTAssertEqual(s.items.count, 1)
    }

    func testNewConversationInsertsAtTop() {
        let s = AIConversationStore()
        s.items = [AIConversation(title: "old")]
        _ = s.newConversation(title: "fresh")
        XCTAssertEqual(s.items.first?.title, "fresh")
    }

    func testDeleteRemovesAndAdvancesCurrent() {
        let s = AIConversationStore()
        s.items = [
            AIConversation(title: "a"),
            AIConversation(title: "b")
        ]
        s.currentID = s.items[0].id
        s.delete(s.items[0].id)
        XCTAssertEqual(s.items.count, 1)
        XCTAssertEqual(s.currentID, s.items[0].id,
                       "Deleting current should fall through to another")
    }

    func testDeleteLastClearsCurrent() {
        let s = AIConversationStore()
        let only = AIConversation(title: "solo")
        s.items = [only]
        s.currentID = only.id
        s.delete(only.id)
        XCTAssertTrue(s.items.isEmpty)
        XCTAssertNil(s.currentID)
    }

    func testRenameTrimsAndFallsBackToPlaceholder() {
        let s = AIConversationStore()
        let c = AIConversation(title: "orig")
        s.items = [c]
        s.rename(c.id, to: "   New name   ")
        XCTAssertEqual(s.items[0].title, "New name")
        s.rename(c.id, to: "   ")
        XCTAssertEqual(s.items[0].title, AIConversationStore.placeholderTitle,
                       "Empty rename should fall back to placeholder")
    }

    func testTogglePin() {
        let s = AIConversationStore()
        let c = AIConversation(title: "x")
        s.items = [c]
        XCTAssertFalse(s.items[0].pinned)
        s.togglePin(c.id)
        XCTAssertTrue(s.items[0].pinned)
    }

    func testDuplicateCopiesMessagesAndBecomesCurrent() {
        let s = AIConversationStore()
        let original = AIConversation(
            title: "proj",
            messages: [ChatMessage(role: .user, text: "hello")]
        )
        s.items = [original]
        guard let copy = s.duplicate(original.id) else {
            return XCTFail("duplicate returned nil")
        }
        XCTAssertEqual(s.items.count, 2)
        XCTAssertTrue(copy.title.contains("copy"))
        XCTAssertEqual(copy.messages.count, 1)
        XCTAssertEqual(s.currentID, copy.id)
    }

    // MARK: - Append / auto-title

    func testAppendCreatesConversationIfNoneSelected() {
        let s = AIConversationStore()
        s.items = []
        s.currentID = nil
        s.append(ChatMessage(role: .user, text: "hi"))
        XCTAssertEqual(s.items.count, 1)
        XCTAssertNotNil(s.currentID)
        XCTAssertEqual(s.items[0].messages.count, 1)
    }

    func testAppendAutoTitlesFromFirstUserMessage() {
        let s = AIConversationStore()
        s.items = []
        s.append(ChatMessage(role: .user, text: "Help me refactor the auth module"))
        XCTAssertEqual(s.items[0].title, "Help me refactor the auth module")
    }

    func testAppendKeepsExistingTitleAfterFirstMessage() {
        let s = AIConversationStore()
        let c = s.newConversation(title: "Custom name")
        s.append(ChatMessage(role: .user, text: "first user message"))
        XCTAssertEqual(s.items.first(where: { $0.id == c.id })?.title, "Custom name",
                       "Non-placeholder titles must not be auto-overwritten")
    }

    func testAutoTitleTruncatesWithEllipsis() {
        let long = String(repeating: "abcdef ", count: 20) // >40 chars
        let title = AIConversationStore.autoTitle(for: long, maxLength: 40)
        XCTAssertEqual(title.count, 40)
        XCTAssertTrue(title.hasSuffix("…"))
    }

    func testAutoTitleUsesFirstLineOnly() {
        let text = "short subject\n\nBody lines that should not appear"
        XCTAssertEqual(AIConversationStore.autoTitle(for: text), "short subject")
    }

    func testAutoTitleTrimsWhitespace() {
        XCTAssertEqual(AIConversationStore.autoTitle(for: "   hi   "), "hi")
    }

    // MARK: - Update / remove message

    func testUpdateMessageAppliesTransform() {
        let s = AIConversationStore()
        let msg = ChatMessage(role: .assistant, text: "")
        s.append(msg)
        s.updateMessage(id: msg.id) { $0.text = "streamed content" }
        XCTAssertEqual(s.currentMessages.first?.text, "streamed content")
    }

    func testRemoveMessageDeletes() {
        let s = AIConversationStore()
        let msg = ChatMessage(role: .assistant, text: "x")
        s.append(msg)
        s.removeMessage(id: msg.id)
        XCTAssertTrue(s.currentMessages.isEmpty)
    }

    // MARK: - Sorting + filtering

    func testSortedPinnedFirstThenByUpdated() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 500)
        let s = AIConversationStore()
        s.items = [
            AIConversation(title: "a", createdAt: older, updatedAt: older),
            AIConversation(title: "b", createdAt: newer, updatedAt: newer),
            AIConversation(title: "c-pinned", createdAt: older, updatedAt: older, pinned: true)
        ]
        let sorted = s.sorted.map { $0.title }
        XCTAssertEqual(sorted, ["c-pinned", "b", "a"])
    }

    func testFilterMatchesTitleOrMessageBody() {
        let s = AIConversationStore()
        s.items = [
            AIConversation(title: "Work", messages: [ChatMessage(role: .user, text: "meeting notes")]),
            AIConversation(title: "Grocery", messages: [ChatMessage(role: .user, text: "milk eggs")])
        ]
        XCTAssertEqual(s.filter("work").count, 1)
        XCTAssertEqual(s.filter("meeting").count, 1)
        XCTAssertEqual(s.filter("milk").count, 1)
        XCTAssertEqual(s.filter("").count, 2)
        XCTAssertEqual(s.filter("xyz").count, 0)
    }

    // MARK: - Persistence

    func testConversationsPersistAcrossInstances() {
        let s1 = AIConversationStore()
        s1.items = [
            AIConversation(
                title: "persistent",
                messages: [
                    ChatMessage(role: .user, text: "q"),
                    ChatMessage(role: .assistant, text: "a")
                ],
                pinned: true
            )
        ]
        // Persist is debounced — wait it out.
        let exp = XCTestExpectation(description: "persist")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            let s2 = AIConversationStore()
            XCTAssertEqual(s2.items.count, 1)
            XCTAssertEqual(s2.items.first?.title, "persistent")
            XCTAssertEqual(s2.items.first?.messages.count, 2)
            XCTAssertTrue(s2.items.first?.pinned ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3.0)
    }

    // MARK: - ChatMessage Codable

    func testChatMessageCodableRoundTrip() throws {
        let msg = ChatMessage(
            role: .assistant,
            text: "hello",
            providerID: "claude-cli"
        )
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(decoded.role, .assistant)
        XCTAssertEqual(decoded.text, "hello")
        XCTAssertEqual(decoded.providerID, "claude-cli")
    }

    func testChatMessageTolerantDecodeMinimal() throws {
        let data = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(decoded.role, .assistant,
                       "Missing role falls back to .assistant")
        XCTAssertEqual(decoded.text, "")
    }

    // MARK: - AIConversation Codable

    func testConversationDecodesMinimalJSON() throws {
        // Only title + one message — everything else should default.
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "title": "legacy",
          "messages": [{"role": "user", "text": "hi"}]
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AIConversation.self, from: json)
        XCTAssertEqual(decoded.title, "legacy")
        XCTAssertEqual(decoded.messages.count, 1)
        XCTAssertFalse(decoded.pinned)
        XCTAssertNil(decoded.providerName)
    }
}
