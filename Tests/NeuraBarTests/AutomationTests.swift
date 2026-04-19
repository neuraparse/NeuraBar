import XCTest
@testable import NeuraBar

final class AutomationCatalogTests: XCTestCase {

    func testCatalogHasExpectedCount() {
        XCTAssertEqual(AutomationCatalog.all.count, 12,
                       "Catalog should have exactly 12 automations")
    }

    func testCategoriesAreAllPopulated() {
        let files = AutomationCatalog.all.filter { $0.category == .files }
        let cleanup = AutomationCatalog.all.filter { $0.category == .cleanup }
        let system = AutomationCatalog.all.filter { $0.category == .system }
        XCTAssertFalse(files.isEmpty)
        XCTAssertFalse(cleanup.isEmpty)
        XCTAssertFalse(system.isEmpty)
        XCTAssertEqual(files.count + cleanup.count + system.count, 12)
    }

    func testEveryDefHasUniqueID() {
        let ids = AutomationCatalog.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "IDs must be unique")
    }

    func testEveryDefHasNonEmptyIconAndLocalizedTitles() {
        let l = Localization()
        l.apply(override: .en)
        for def in AutomationCatalog.all {
            XCTAssertFalse(def.icon.isEmpty, "\(def.id) has no SF Symbol")
            XCTAssertFalse(l.t(def.titleKey).isEmpty, "\(def.id) title is empty")
            XCTAssertFalse(l.t(def.subtitleKey).isEmpty, "\(def.id) subtitle is empty")
            XCTAssertNotEqual(l.t(def.titleKey), def.titleKey.rawValue,
                              "\(def.id) title falls through to raw key — missing translation")
        }
    }
}

final class AutomationCounterParsingTests: XCTestCase {

    func testParseCounterReadsValue() {
        let out = """
        line one
        __MOVED:42
        line two
        """
        XCTAssertEqual(parseCounter(out, key: "__MOVED"), 42)
    }

    func testParseCounterReturnsZeroWhenMissing() {
        XCTAssertEqual(parseCounter("nothing here", key: "__X"), 0)
    }

    func testParseCounterReturnsZeroOnGarbage() {
        XCTAssertEqual(parseCounter("__X:not-a-number", key: "__X"), 0)
    }

    func testParseCounterHandlesZero() {
        XCTAssertEqual(parseCounter("__X:0", key: "__X"), 0)
    }

    func testParseCounterHandlesMultipleCounters() {
        let out = "__A:1\n__B:2\n__C:3"
        XCTAssertEqual(parseCounter(out, key: "__A"), 1)
        XCTAssertEqual(parseCounter(out, key: "__B"), 2)
        XCTAssertEqual(parseCounter(out, key: "__C"), 3)
    }

    func testStripCountersRemovesSentinels() {
        let out = """
        real line 1
        __MOVED:5
        real line 2
        __SIZE:100
        real line 3
        """
        let stripped = stripCounters(out, keys: ["__MOVED", "__SIZE"])
        XCTAssertFalse(stripped.contains("__MOVED"))
        XCTAssertFalse(stripped.contains("__SIZE"))
        XCTAssertTrue(stripped.contains("real line 1"))
        XCTAssertTrue(stripped.contains("real line 2"))
        XCTAssertTrue(stripped.contains("real line 3"))
    }

    func testStripCountersLeavesUnknownSentinels() {
        let stripped = stripCounters("__KEEP:99\n__DROP:1", keys: ["__DROP"])
        XCTAssertTrue(stripped.contains("__KEEP:99"))
        XCTAssertFalse(stripped.contains("__DROP"))
    }
}

final class AutomationStoreTests: NBTestCase {

    func testStartsWithEmptyHistoryOnFreshFilesystem() {
        let s = AutomationStore()
        XCTAssertTrue(s.history.isEmpty)
        XCTAssertNil(s.runningTaskID)
    }

    func testHistoryIsPersisted() {
        let s1 = AutomationStore()
        let run = AutomationRun(
            id: UUID(),
            taskID: "test",
            taskTitle: "Test",
            status: .succeeded,
            summary: "Did a thing",
            stats: [AutomationStat(label: "Count", value: "7")],
            details: "",
            startedAt: Date(),
            finishedAt: Date()
        )
        s1.history = [run]

        let s2 = AutomationStore()
        XCTAssertEqual(s2.history.count, 1)
        XCTAssertEqual(s2.history.first?.taskID, "test")
        XCTAssertEqual(s2.history.first?.stats.first?.value, "7")
    }

    func testClearHistoryEmptiesList() {
        let s = AutomationStore()
        s.history = [
            AutomationRun(id: UUID(), taskID: "x", taskTitle: "X",
                          status: .succeeded, summary: "",
                          stats: [], details: "",
                          startedAt: Date(), finishedAt: Date())
        ]
        s.clearHistory()
        XCTAssertTrue(s.history.isEmpty)
    }
}
