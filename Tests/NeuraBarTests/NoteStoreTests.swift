import XCTest
@testable import NeuraBar

final class NoteStoreTests: NBTestCase {

    func testInitCreatesWelcomeNoteWhenFileMissing() {
        let s = NoteStore()
        XCTAssertFalse(s.items.isEmpty, "Should seed at least a welcome note")
    }

    func testNewPrependsNote() {
        let s = NoteStore()
        s.items = []
        s.new()
        s.new()
        XCTAssertEqual(s.items.count, 2)
        // Both new notes carry the default title
        for note in s.items {
            XCTAssertFalse(note.title.isEmpty)
        }
    }

    func testUpdateRefreshesTimestamp() {
        let s = NoteStore()
        s.items = [NoteItem(title: "orig", body: "", updated: Date(timeIntervalSince1970: 0))]
        var n = s.items[0]
        n.body = "changed"
        s.update(n)
        let updated = s.items[0].updated.timeIntervalSince1970
        XCTAssertGreaterThan(updated, 1_000_000,
                             "update() must refresh the `updated` timestamp")
        XCTAssertEqual(s.items[0].body, "changed")
    }

    func testUpdateNonexistentNoteIsNoOp() {
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

    func testPersistenceRoundTrip() {
        let s1 = NoteStore()
        s1.items = [NoteItem(title: "T", body: "B", updated: Date())]
        let s2 = NoteStore()
        XCTAssertEqual(s2.items.count, 1)
        XCTAssertEqual(s2.items.first?.title, "T")
        XCTAssertEqual(s2.items.first?.body, "B")
    }
}
