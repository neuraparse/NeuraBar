import XCTest
@testable import NeuraBar

final class ClipboardManagerTests: NBTestCase {

    // ClipboardManager's `tick()` polls NSPasteboard so it isn't easy to
    // exercise deterministically in tests. We focus instead on the publicly
    // mutable state: insertion via direct items manipulation, copy(),
    // togglePin(), remove(), clear(), and persistence.

    func testCopyMovesItemToTop() {
        let c = ClipboardManager()
        c.items = [
            ClipItem(text: "a", date: Date(timeIntervalSinceNow: -3)),
            ClipItem(text: "b", date: Date(timeIntervalSinceNow: -2)),
            ClipItem(text: "c", date: Date(timeIntervalSinceNow: -1))
        ]
        let bItem = c.items[1]
        c.copy(bItem)
        XCTAssertEqual(c.items.first?.text, "b",
                       "copy() must move existing item to the top")
    }

    func testTogglePinFlipsFlag() {
        let c = ClipboardManager()
        let item = ClipItem(text: "pin me", date: Date())
        c.items = [item]
        XCTAssertFalse(c.items.first!.pinned)
        c.togglePin(c.items.first!)
        XCTAssertTrue(c.items.first!.pinned)
        c.togglePin(c.items.first!)
        XCTAssertFalse(c.items.first!.pinned)
    }

    func testRemoveDeletesByID() {
        let c = ClipboardManager()
        c.items = [
            ClipItem(text: "x", date: Date()),
            ClipItem(text: "y", date: Date()),
            ClipItem(text: "z", date: Date())
        ]
        c.remove(c.items[1])
        XCTAssertEqual(c.items.count, 2)
        XCTAssertFalse(c.items.contains(where: { $0.text == "y" }))
    }

    func testClearKeepsPinned() {
        let c = ClipboardManager()
        c.items = [
            ClipItem(text: "ephemeral", date: Date(), pinned: false),
            ClipItem(text: "forever", date: Date(), pinned: true),
            ClipItem(text: "also-ephemeral", date: Date(), pinned: false)
        ]
        c.clear()
        XCTAssertEqual(c.items.count, 1)
        XCTAssertEqual(c.items.first?.text, "forever")
    }

    func testPersistenceRoundTrip() {
        let expectation = XCTestExpectation(description: "persist")
        let c1 = ClipboardManager()
        c1.items = [ClipItem(text: "persist", date: Date(), pinned: true)]
        // ClipboardManager uses a 0.6s debounce timer; wait for it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let c2 = ClipboardManager()
            XCTAssertEqual(c2.items.count, 1)
            XCTAssertEqual(c2.items.first?.text, "persist")
            XCTAssertTrue(c2.items.first?.pinned ?? false)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
    }

    func testCopyOfNonexistentItemDoesNotCrash() {
        let c = ClipboardManager()
        c.items = [ClipItem(text: "real", date: Date())]
        let ghost = ClipItem(text: "ghost", date: Date())
        c.copy(ghost) // must not crash — just writes to pasteboard
        XCTAssertEqual(c.items.count, 1)
    }
}
