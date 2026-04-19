import XCTest
@testable import NeuraBar

final class TodoStoreTests: NBTestCase {

    func testAddInsertsAtTop() {
        let s = TodoStore()
        s.items = []
        s.add("First")
        s.add("Second")
        XCTAssertEqual(s.items.first?.title, "Second")
        XCTAssertEqual(s.items.count, 2)
    }

    func testAddTrimsAndIgnoresBlank() {
        let s = TodoStore()
        s.items = []
        s.add("   ")
        s.add("\n\t")
        s.add("")
        XCTAssertTrue(s.items.isEmpty, "Blank/whitespace titles must be ignored")
    }

    func testAddTrimsWhitespaceAroundTitle() {
        let s = TodoStore()
        s.items = []
        s.add("  hello  ")
        XCTAssertEqual(s.items.first?.title, "hello")
    }

    func testToggleFlipsDoneFlag() {
        let s = TodoStore()
        s.items = []
        s.add("task")
        let item = s.items.first!
        XCTAssertFalse(item.done)
        s.toggle(item)
        XCTAssertTrue(s.items.first!.done)
        s.toggle(s.items.first!)
        XCTAssertFalse(s.items.first!.done)
    }

    func testRemoveDeletesByID() {
        let s = TodoStore()
        s.items = []
        s.add("a"); s.add("b"); s.add("c")
        let middle = s.items[1]
        s.remove(middle)
        XCTAssertEqual(s.items.count, 2)
        XCTAssertFalse(s.items.contains(where: { $0.id == middle.id }))
    }

    func testClearCompletedOnlyRemovesDone() {
        let s = TodoStore()
        s.items = []
        s.add("keep-1")
        s.add("done-1")
        s.add("keep-2")
        s.toggle(s.items.first(where: { $0.title == "done-1" })!)
        s.clearCompleted()
        XCTAssertEqual(s.items.count, 2)
        XCTAssertTrue(s.items.allSatisfy { !$0.done })
    }

    func testTagIsPreserved() {
        let s = TodoStore()
        s.items = []
        s.add("buy milk", tag: "errand")
        XCTAssertEqual(s.items.first?.tag, "errand")
    }

    func testPersistenceRoundTrip() {
        let s1 = TodoStore()
        s1.items = []
        s1.add("persist me", tag: "x")

        let s2 = TodoStore()
        XCTAssertEqual(s2.items.count, 1)
        XCTAssertEqual(s2.items.first?.title, "persist me")
        XCTAssertEqual(s2.items.first?.tag, "x")
    }
}
