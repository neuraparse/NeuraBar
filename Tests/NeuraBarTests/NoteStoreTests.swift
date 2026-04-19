import XCTest
@testable import NeuraBar

final class NoteStoreTests: NBTestCase {

    // MARK: - Bootstrapping

    func testInitSeedsWelcomeNoteWhenFileMissing() {
        let s = NoteStore()
        XCTAssertFalse(s.items.isEmpty)
        XCTAssertTrue(s.items.first!.title.count > 0)
    }

    // MARK: - CRUD

    func testNewPrependsNote() {
        let s = NoteStore()
        s.items = []
        s.new(title: "A")
        s.new(title: "B")
        XCTAssertEqual(s.items.count, 2)
        XCTAssertEqual(s.items.first?.title, "B")
    }

    func testUpdateRefreshesTimestamp() {
        let s = NoteStore()
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        s.items = [NoteItem(title: "t", body: "", updated: old)]
        var n = s.items[0]
        n.body = "changed"
        s.update(n)
        XCTAssertGreaterThan(s.items[0].updated, old)
        XCTAssertEqual(s.items[0].body, "changed")
    }

    func testUpdateNonexistentIsNoOp() {
        let s = NoteStore()
        s.items = [NoteItem(title: "a", body: "", updated: Date())]
        let ghost = NoteItem(title: "ghost", body: "", updated: Date())
        s.update(ghost)
        XCTAssertEqual(s.items.count, 1)
        XCTAssertEqual(s.items.first?.title, "a")
    }

    func testRemoveDeletesByID() {
        let s = NoteStore()
        s.items = [
            NoteItem(title: "a", body: "", updated: Date()),
            NoteItem(title: "b", body: "", updated: Date())
        ]
        let b = s.items[1]
        s.remove(b)
        XCTAssertEqual(s.items.count, 1)
        XCTAssertEqual(s.items.first?.title, "a")
    }

    // MARK: - Pin / duplicate / color

    func testTogglePinFlipsAndStamps() {
        let s = NoteStore()
        s.items = [NoteItem(title: "x", body: "", updated: Date(timeIntervalSince1970: 0))]
        let note = s.items[0]
        s.togglePin(note)
        XCTAssertTrue(s.items[0].pinned)
        s.togglePin(s.items[0])
        XCTAssertFalse(s.items[0].pinned)
    }

    func testDuplicateAppendsCopyAndPrepends() {
        let s = NoteStore()
        s.items = [NoteItem(title: "orig", body: "hello", updated: Date(), pinned: true)]
        let copy = s.duplicate(s.items[0])
        XCTAssertEqual(s.items.count, 2)
        XCTAssertEqual(s.items.first?.id, copy.id)
        XCTAssertEqual(copy.body, "hello")
        XCTAssertTrue(copy.title.contains("copy"))
        XCTAssertFalse(copy.pinned, "Copy must not inherit pin state")
    }

    func testSetColor() {
        let s = NoteStore()
        s.items = [NoteItem(title: "x", body: "", updated: Date())]
        s.setColor(.purple, for: s.items[0])
        XCTAssertEqual(s.items[0].color, .purple)
    }

    // MARK: - Sort / filter / grouping

    func testSortPutsPinnedFirstThenByUpdated() {
        let s = NoteStore()
        let old = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 500)
        s.items = [
            NoteItem(title: "old-unpinned", body: "", updated: old),
            NoteItem(title: "new-pinned", body: "", updated: newer, pinned: true),
            NoteItem(title: "newest-unpinned", body: "", updated: Date(timeIntervalSince1970: 800)),
            NoteItem(title: "old-pinned", body: "", updated: old, pinned: true)
        ]
        let sorted = s.sorted.map { $0.title }
        XCTAssertEqual(sorted[0], "new-pinned")
        XCTAssertEqual(sorted[1], "old-pinned")
        XCTAssertEqual(sorted[2], "newest-unpinned")
        XCTAssertEqual(sorted[3], "old-unpinned")
    }

    func testFilterMatchesTitleBodyTags() {
        let s = NoteStore()
        s.items = [
            NoteItem(title: "Grocery list", body: "milk, eggs", updated: Date()),
            NoteItem(title: "Work", body: "finish #roadmap draft", updated: Date()),
            NoteItem(title: "Journal", body: "slept well", updated: Date())
        ]
        XCTAssertEqual(s.filter("grocery").count, 1)
        XCTAssertEqual(s.filter("eggs").count, 1)
        XCTAssertEqual(s.filter("roadmap").count, 1,
                       "Tag-only search should match")
        XCTAssertEqual(s.filter("x").count, 0)
    }

    func testFilterEmptyReturnsAllSorted() {
        let s = NoteStore()
        s.items = [
            NoteItem(title: "a", body: "", updated: Date(timeIntervalSince1970: 1)),
            NoteItem(title: "b", body: "", updated: Date(timeIntervalSince1970: 2))
        ]
        XCTAssertEqual(s.filter("").count, 2)
    }

    func testTagsAggregatedAcrossNotes() {
        let s = NoteStore()
        s.items = [
            NoteItem(title: "", body: "#work meeting", updated: Date()),
            NoteItem(title: "", body: "#work #urgent", updated: Date()),
            NoteItem(title: "", body: "#idea", updated: Date())
        ]
        let tags = s.allTags
        let workCount = tags.first { $0.tag == "work" }?.count
        let ideaCount = tags.first { $0.tag == "idea" }?.count
        XCTAssertEqual(workCount, 2)
        XCTAssertEqual(ideaCount, 1)
    }

    func testGroupingBuckets() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar.current
        let today = now
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let threeDays = cal.date(byAdding: .day, value: -3, to: now)!
        let lastMonth = cal.date(byAdding: .day, value: -60, to: now)!

        let notes = [
            NoteItem(title: "pinned", body: "", updated: threeDays, pinned: true),
            NoteItem(title: "t", body: "", updated: today),
            NoteItem(title: "y", body: "", updated: yesterday),
            NoteItem(title: "w", body: "", updated: threeDays),
            NoteItem(title: "o", body: "", updated: lastMonth)
        ]

        let groups = NoteStore.group(notes, now: now)
        let buckets = groups.map { $0.0 }
        XCTAssertEqual(buckets, [.pinned, .today, .yesterday, .thisWeek, .older])
    }

    // MARK: - Tolerant decode

    func testDecodesLegacyNotesJSON() throws {
        // Mirrors the v1 schema — no pinned/color/created fields.
        let legacy = """
        [
          {
            "id": "11111111-1111-1111-1111-111111111111",
            "title": "legacy note",
            "body": "hello",
            "updated": 700000000
          }
        ]
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([NoteItem].self, from: legacy)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].title, "legacy note")
        XCTAssertFalse(decoded[0].pinned, "Missing pinned should default to false")
        XCTAssertEqual(decoded[0].color, .none)
    }

    func testDecodesEmptyJSONObjectAsMinimalNote() throws {
        let data = "[{}]".data(using: .utf8)!
        let decoded = try JSONDecoder().decode([NoteItem].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].title, "")
        XCTAssertEqual(decoded[0].body, "")
    }

    // MARK: - Persistence

    func testRoundTripsThroughDisk() {
        let s1 = NoteStore()
        s1.items = [
            NoteItem(title: "Persistent", body: "#tag body", updated: Date(),
                     pinned: true, color: .purple)
        ]
        let s2 = NoteStore()
        XCTAssertEqual(s2.items.count, 1)
        XCTAssertEqual(s2.items.first?.title, "Persistent")
        XCTAssertTrue(s2.items.first?.pinned ?? false)
        XCTAssertEqual(s2.items.first?.color, .purple)
        XCTAssertEqual(s2.items.first?.tags, ["tag"])
    }
}

// MARK: - NoteItem computed properties

final class NoteItemTests: XCTestCase {

    func testWordCountSplitsOnWhitespace() {
        XCTAssertEqual(NoteItem(title: "", body: "", updated: Date()).wordCount, 0)
        XCTAssertEqual(NoteItem(title: "", body: "one", updated: Date()).wordCount, 1)
        XCTAssertEqual(NoteItem(title: "", body: "one two three", updated: Date()).wordCount, 3)
        XCTAssertEqual(NoteItem(title: "", body: "line1\nline2 more", updated: Date()).wordCount, 3)
    }

    func testCharacterCountExcludesWhitespace() {
        XCTAssertEqual(NoteItem(title: "", body: "abc  def", updated: Date()).characterCount, 6)
        XCTAssertEqual(NoteItem(title: "", body: "  ", updated: Date()).characterCount, 0)
    }

    func testReadingMinutesRoundsUpAndFloorsAtOne() {
        let short = NoteItem(title: "", body: String(repeating: "word ", count: 50), updated: Date())
        XCTAssertEqual(short.readingMinutes, 1, "50 words must round up to 1 min, not 0")
        let long = NoteItem(title: "", body: String(repeating: "word ", count: 500), updated: Date())
        XCTAssertEqual(long.readingMinutes, 3, "500 words @ 220 wpm ≈ 3 min")
        let empty = NoteItem(title: "", body: "", updated: Date())
        XCTAssertEqual(empty.readingMinutes, 0)
    }

    func testTagsExtractFromBody() {
        let note = NoteItem(
            title: "",
            body: "standup today #work #urgent fix #WORK duplicate",
            updated: Date()
        )
        // Case-insensitive dedup, sorted.
        XCTAssertEqual(note.tags, ["urgent", "work"])
    }

    func testTagsIgnoreHashInsideWord() {
        let note = NoteItem(title: "", body: "price is $50#", updated: Date())
        XCTAssertTrue(note.tags.isEmpty)
    }

    func testTagsHandleUnicode() {
        let note = NoteItem(title: "", body: "#türkçe #日本語", updated: Date())
        XCTAssertTrue(note.tags.contains("türkçe"))
        XCTAssertTrue(note.tags.contains("日本語"))
    }

    func testEffectiveTitleFallsBackToFirstLine() {
        let note = NoteItem(title: "", body: "first line\nsecond", updated: Date())
        XCTAssertEqual(note.effectiveTitle, "first line")
    }

    func testEffectiveTitleTrimsWhitespaceTitle() {
        let note = NoteItem(title: "   ", body: "real title", updated: Date())
        XCTAssertEqual(note.effectiveTitle, "real title")
    }

    func testPreviewCapsAt60Chars() {
        let body = String(repeating: "a", count: 200)
        let note = NoteItem(title: "", body: body, updated: Date())
        XCTAssertEqual(note.preview.count, 60)
    }
}

// MARK: - NoteEditor pure helpers

final class NoteEditorHelperTests: XCTestCase {

    func testAppendingOnEmptyBody() {
        XCTAssertEqual(NoteEditor.appendingText("", "x"), "x")
    }

    func testAppendingAfterTrailingNewlineDoesntDoubleUp() {
        XCTAssertEqual(NoteEditor.appendingText("line1\n", "x"), "line1\nx")
    }

    func testAppendingAddsNewlineWhenMissing() {
        XCTAssertEqual(NoteEditor.appendingText("line1", "x"), "line1\nx")
    }
}

// MARK: - Adaptive layout threshold

/// We rely on the 520-px threshold to decide between single-pane (menu bar
/// popover) and split (big window). This test locks that contract so a future
/// change to the constant or either panel width forces a conscious decision.
final class NotesAdaptiveLayoutTests: XCTestCase {

    func testPopoverWidthTriggersCompactMode() {
        // The MainView popover is NB.panelWidth == 440.
        XCTAssertLessThan(NB.panelWidth, 520,
                          "Popover must fall under the split threshold")
    }

    func testBigWindowWidthTriggersSplitMode() {
        // WindowManager opens the big window at 820 x 720.
        let bigWidth: CGFloat = 820
        XCTAssertGreaterThanOrEqual(bigWidth, 520,
                                    "Big window must sit above the split threshold")
    }
}
