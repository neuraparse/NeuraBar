import XCTest
@testable import NeuraBar

/// Contract-level tests for AssistantView's observable surface. These don't
/// render SwiftUI but verify the store-level invariants the UI relies on:
/// streaming chunks append through a single method, deleting a placeholder
/// cleans up, switching conversations preserves message state, etc.
final class AssistantBehaviorTests: NBTestCase {

    // MARK: - Streaming

    func testStreamingChunksAccumulateOnSameMessage() {
        let s = AIConversationStore()
        s.newConversation()
        let bubble = ChatMessage(role: .assistant, text: "", providerID: "claude-cli")
        s.append(bubble)
        s.updateMessage(id: bubble.id) { $0.text += "Hello" }
        s.updateMessage(id: bubble.id) { $0.text += ", " }
        s.updateMessage(id: bubble.id) { $0.text += "world" }
        XCTAssertEqual(s.currentMessages.last?.text, "Hello, world")
    }

    func testStreamingErrorPathRemovesEmptyBubble() {
        let s = AIConversationStore()
        s.newConversation()
        let bubble = ChatMessage(role: .assistant, text: "", providerID: "claude-cli")
        s.append(bubble)
        // Simulate "CLI errored before any chunk landed" — text still empty
        let empty = s.currentMessages.first(where: { $0.id == bubble.id })
        XCTAssertEqual(empty?.text, "")
        // Caller would now remove the bubble
        s.removeMessage(id: bubble.id)
        XCTAssertFalse(s.currentMessages.contains(where: { $0.id == bubble.id }))
    }

    func testStreamingKeepsBubbleWhenAnyChunkArrived() {
        // Contract: we only remove the bubble when it's still empty at the end.
        let s = AIConversationStore()
        s.newConversation()
        let bubble = ChatMessage(role: .assistant, text: "", providerID: "claude-cli")
        s.append(bubble)
        s.updateMessage(id: bubble.id) { $0.text = "partial output" }
        // Even if onDone reports an error, a populated bubble must survive.
        if let msg = s.currentMessages.first(where: { $0.id == bubble.id }),
           msg.text.isEmpty {
            s.removeMessage(id: bubble.id)
        }
        XCTAssertTrue(s.currentMessages.contains(where: { $0.id == bubble.id }),
                      "Populated bubble must survive the error-cleanup branch")
    }

    // MARK: - Switching conversations

    func testSwitchingConversationsSwapsCurrentMessagesView() {
        let s = AIConversationStore()
        let a = s.newConversation(title: "A")
        s.append(ChatMessage(role: .user, text: "from A"))
        let b = s.newConversation(title: "B")
        s.append(ChatMessage(role: .user, text: "from B"))
        s.currentID = a.id
        XCTAssertEqual(s.currentMessages.map(\.text), ["from A"])
        s.currentID = b.id
        XCTAssertEqual(s.currentMessages.map(\.text), ["from B"])
    }

    func testNewConversationReturnsCurrentEmpty() {
        let s = AIConversationStore()
        s.newConversation()
        XCTAssertTrue(s.currentMessages.isEmpty)
    }

    // MARK: - Provider name stamping

    func testAppendStampsProviderNameWhenGiven() {
        let s = AIConversationStore()
        s.append(ChatMessage(role: .user, text: "hi"),
                 providerName: "Claude Code")
        XCTAssertEqual(s.current?.providerName, "Claude Code")
    }

    func testAppendDoesntOverwriteProviderNameWhenNil() {
        let s = AIConversationStore()
        s.append(ChatMessage(role: .user, text: "a"),
                 providerName: "Claude Code")
        s.append(ChatMessage(role: .user, text: "b"), providerName: nil)
        XCTAssertEqual(s.current?.providerName, "Claude Code",
                       "Existing providerName must not be cleared by later append with nil")
    }

    // MARK: - Pin ordering

    func testPinnedBubblesToTopAndNewNotPinned() {
        let s = AIConversationStore()
        let older = s.newConversation(title: "older")
        let newer = s.newConversation(title: "newer")
        s.togglePin(older.id)
        XCTAssertEqual(s.sorted.first?.id, older.id,
                       "Pinned conversation should rise above newer unpinned")
        XCTAssertFalse(newer.pinned)
    }

    // MARK: - Filter interactions

    func testFilterFindsOnlyMatchingTitlesAndBodies() {
        let s = AIConversationStore()
        s.items = [
            AIConversation(title: "roadmap", messages: [
                ChatMessage(role: .user, text: "Q1 priorities")
            ]),
            AIConversation(title: "billing", messages: [
                ChatMessage(role: .user, text: "invoice 101")
            ])
        ]
        XCTAssertEqual(s.filter("roadmap").count, 1)
        XCTAssertEqual(s.filter("Q1").count, 1)
        XCTAssertEqual(s.filter("invoice").count, 1)
        XCTAssertEqual(s.filter("").count, 2)
        XCTAssertEqual(s.filter("nothing-matches-this").count, 0)
    }

    // MARK: - Auto-title edge cases

    func testAutoTitleEmptyStringProducesEmptyTitle() {
        XCTAssertEqual(AIConversationStore.autoTitle(for: "   "), "")
    }

    func testAutoTitleMaxLengthBoundary() {
        let exactly40 = String(repeating: "a", count: 40)
        XCTAssertEqual(AIConversationStore.autoTitle(for: exactly40), exactly40,
                       "40 chars should not trigger truncation at maxLength=40")
        let fortyOne = String(repeating: "a", count: 41)
        XCTAssertTrue(AIConversationStore.autoTitle(for: fortyOne).hasSuffix("…"))
    }

    // MARK: - Persistence bookkeeping

    func testCurrentIDSurvivesDecodeIfLatestUpdated() {
        let s1 = AIConversationStore()
        let older = AIConversation(title: "older",
                                   updatedAt: Date(timeIntervalSince1970: 100))
        let newer = AIConversation(title: "newer",
                                   updatedAt: Date(timeIntervalSince1970: 500))
        s1.items = [older, newer]

        let exp = XCTestExpectation(description: "persist")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            let s2 = AIConversationStore()
            // The store picks the most-recently-updated conversation on load.
            XCTAssertEqual(s2.currentID, newer.id)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3.0)
    }
}
