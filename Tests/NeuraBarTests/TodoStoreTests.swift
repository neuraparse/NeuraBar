import XCTest
@testable import NeuraBar

final class TodoStoreTests: NBTestCase {

    // MARK: - CRUD

    func testAddInsertsAtTopAndTrims() {
        let s = TodoStore()
        s.items = []
        s.add("  hello  ")
        s.add("world")
        XCTAssertEqual(s.items.first?.title, "world")
        XCTAssertEqual(s.items.last?.title, "hello")
        XCTAssertEqual(s.items.count, 2)
    }

    func testAddIgnoresBlanks() {
        let s = TodoStore()
        s.items = []
        s.add("   ")
        s.add("\n\t")
        s.add("")
        XCTAssertTrue(s.items.isEmpty)
    }

    func testToggleFlipsDoneAndStampsCompletedAt() {
        let s = TodoStore()
        s.items = []
        s.add("task")
        let item = s.items.first!
        XCTAssertFalse(item.done)
        XCTAssertNil(item.completedAt)
        s.toggle(item)
        XCTAssertTrue(s.items.first!.done)
        XCTAssertNotNil(s.items.first!.completedAt)
        s.toggle(s.items.first!)
        XCTAssertFalse(s.items.first!.done)
        XCTAssertNil(s.items.first!.completedAt)
    }

    func testRemove() {
        let s = TodoStore()
        s.items = []
        s.add("a"); s.add("b"); s.add("c")
        let middle = s.items[1]
        s.remove(middle)
        XCTAssertEqual(s.items.count, 2)
        XCTAssertFalse(s.items.contains(where: { $0.id == middle.id }))
    }

    func testClearCompleted() {
        let s = TodoStore()
        s.items = []
        s.add("keep-1"); s.add("done-1"); s.add("keep-2")
        s.toggle(s.items.first(where: { $0.title == "done-1" })!)
        s.clearCompleted()
        XCTAssertEqual(s.items.count, 2)
        XCTAssertTrue(s.items.allSatisfy { !$0.done })
    }

    // MARK: - Priority

    func testSetPriorityUpdatesItem() {
        let s = TodoStore()
        s.items = [TodoItem(title: "x")]
        s.setPriority(.high, for: s.items[0])
        XCTAssertEqual(s.items[0].priority, .high)
    }

    func testPrioritySortWeight() {
        XCTAssertLessThan(TodoPriority.high.sortWeight, TodoPriority.normal.sortWeight)
        XCTAssertLessThan(TodoPriority.normal.sortWeight, TodoPriority.low.sortWeight)
    }

    func testSortPutsHighFirstAndDonesLast() {
        let items = [
            TodoItem(title: "low", priority: .low),
            TodoItem(title: "high", priority: .high),
            TodoItem(title: "done", done: true),
            TodoItem(title: "normal", priority: .normal)
        ]
        let sorted = TodoStore.sort(items)
        XCTAssertEqual(sorted[0].title, "high")
        XCTAssertEqual(sorted[1].title, "normal")
        XCTAssertEqual(sorted[2].title, "low")
        XCTAssertEqual(sorted[3].title, "done")
    }

    // MARK: - Due date

    func testSetDueDate() {
        let s = TodoStore()
        s.items = [TodoItem(title: "x")]
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        s.setDueDate(d, for: s.items[0])
        XCTAssertEqual(s.items[0].dueDate, d)
        s.setDueDate(nil, for: s.items[0])
        XCTAssertNil(s.items[0].dueDate)
    }

    func testSortPrefersEarliestDueWithinSamePriority() {
        let earlier = Date(timeIntervalSince1970: 100)
        let later   = Date(timeIntervalSince1970: 500)
        let items = [
            TodoItem(title: "later-due", dueDate: later, priority: .normal),
            TodoItem(title: "earlier-due", dueDate: earlier, priority: .normal),
            TodoItem(title: "no-due", priority: .normal)
        ]
        let sorted = TodoStore.sort(items)
        XCTAssertEqual(sorted[0].title, "earlier-due")
        XCTAssertEqual(sorted[1].title, "later-due")
        XCTAssertEqual(sorted[2].title, "no-due")
    }

    // MARK: - Grouping

    func testGroupingBuckets() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar.current
        let today = now
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let dayAfter = cal.date(byAdding: .day, value: 2, to: now)!
        let nextMonth = cal.date(byAdding: .day, value: 30, to: now)!
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!

        let items = [
            TodoItem(title: "overdue", dueDate: yesterday),
            TodoItem(title: "today", dueDate: today),
            TodoItem(title: "tomorrow", dueDate: tomorrow),
            TodoItem(title: "this-week", dueDate: dayAfter),
            TodoItem(title: "later", dueDate: nextMonth),
            TodoItem(title: "no-date"),
            TodoItem(title: "completed", done: true)
        ]
        let groups = NeuraBar.TodoStore.group(items, now: now)
        let buckets = groups.map { $0.0 }
        XCTAssertEqual(buckets, [.overdue, .today, .tomorrow, .thisWeek, .later, .noDate, .completed])
    }

    // MARK: - Tags

    func testTagsExtractedFromTitle() {
        let item = TodoItem(title: "standup #work #URGENT please")
        XCTAssertEqual(item.tags, ["urgent", "work"])
    }

    func testTagsIncludeExplicitLegacyTagField() {
        let item = TodoItem(title: "plain title", tag: "personal")
        XCTAssertTrue(item.tags.contains("personal"))
    }

    func testFilterMatchesTitleOrTag() {
        let s = TodoStore()
        s.items = [
            TodoItem(title: "buy milk #grocery"),
            TodoItem(title: "write code", tag: "work"),
            TodoItem(title: "clean fridge")
        ]
        XCTAssertEqual(s.filter("milk").count, 1)
        XCTAssertEqual(s.filter("grocery").count, 1)
        XCTAssertEqual(s.filter("work").count, 1)
        XCTAssertEqual(s.filter("").count, 3)
        XCTAssertEqual(s.filter("xyz").count, 0)
    }

    func testAllTagsAggregateAcrossActiveItems() {
        let s = TodoStore()
        s.items = [
            TodoItem(title: "a #work"),
            TodoItem(title: "b #work"),
            TodoItem(title: "c #idea"),
            TodoItem(title: "d #work", done: true) // completed → excluded
        ]
        let tags = s.allTags
        XCTAssertEqual(tags.first { $0.tag == "work" }?.count, 2)
        XCTAssertEqual(tags.first { $0.tag == "idea" }?.count, 1)
    }

    // MARK: - Progress

    func testProgressCounts() {
        let s = TodoStore()
        s.items = [
            TodoItem(title: "a", done: true),
            TodoItem(title: "b"),
            TodoItem(title: "c", done: true)
        ]
        let (done, total) = s.progress
        XCTAssertEqual(done, 2)
        XCTAssertEqual(total, 3)
    }

    // MARK: - Tolerant decode

    func testDecodesLegacyTodoJSON() throws {
        let legacy = """
        [
          {
            "id": "11111111-1111-1111-1111-111111111111",
            "title": "legacy task",
            "done": false,
            "createdAt": 700000000,
            "tag": "errand"
          }
        ]
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([TodoItem].self, from: legacy)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].title, "legacy task")
        XCTAssertEqual(decoded[0].priority, .normal, "Missing priority defaults to .normal")
        XCTAssertNil(decoded[0].dueDate)
        XCTAssertEqual(decoded[0].tag, "errand")
    }

    func testDecodesEmptyObjectGracefully() throws {
        let data = "[{}]".data(using: .utf8)!
        let decoded = try JSONDecoder().decode([TodoItem].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].title, "")
        XCTAssertFalse(decoded[0].done)
    }

    // MARK: - Persistence

    func testRoundTripsThroughDisk() {
        let s1 = TodoStore()
        s1.items = [
            TodoItem(title: "persistent #deep",
                     priority: .high,
                     tag: "keep"),
            TodoItem(title: "c")
        ]
        let s2 = TodoStore()
        XCTAssertEqual(s2.items.count, 2)
        XCTAssertEqual(s2.items.first?.priority, .high)
        XCTAssertEqual(s2.items.first?.tag, "keep")
        XCTAssertTrue(s2.items.first?.tags.contains("deep") ?? false)
    }
}
