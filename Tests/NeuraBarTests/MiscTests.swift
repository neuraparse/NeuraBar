import XCTest
import SwiftUI
@testable import NeuraBar

final class TabTests: XCTestCase {

    func testAllTabsHaveKeyboardShortcutsInDigitRange() {
        for t in Tab.allCases {
            let ch = String(t.shortcutKey.character)
            XCTAssertTrue("123456789".contains(ch),
                          "Tab \(t.rawValue) shortcut \(ch) is outside ⌘1..⌘9")
        }
    }

    func testTabCountMatchesExpected() {
        XCTAssertEqual(Tab.allCases.count, 9,
                       "Adding/removing tabs must be reflected in UX copy/docs")
    }

    func testRecordTabIsPresent() {
        XCTAssertTrue(Tab.allCases.contains(.record))
    }

    func testAllTabsHaveTitleKey() {
        let l = Localization()
        l.apply(override: .en)
        for t in Tab.allCases {
            let title = l.t(t.titleKey)
            XCTAssertNotEqual(title, t.titleKey.rawValue,
                              "Tab \(t.rawValue) has no English title")
        }
    }

    func testTabsHaveDistinctShortcutKeys() {
        let keys = Tab.allCases.map { String($0.shortcutKey.character) }
        XCTAssertEqual(Set(keys).count, keys.count, "Shortcut keys must be unique")
    }
}

final class PomodoroTests: NBTestCase {

    func testInitialState() {
        let p = PomodoroTimer()
        XCTAssertEqual(p.phase, .idle)
        XCTAssertFalse(p.running)
        XCTAssertEqual(p.remaining, 25 * 60)
        XCTAssertEqual(p.sessionsCompleted, 0)
    }

    func testStartFocusTransitionsToFocusPhase() {
        let p = PomodoroTimer()
        p.startFocus()
        XCTAssertEqual(p.phase, .focus)
        XCTAssertTrue(p.running)
        XCTAssertEqual(p.remaining, 25 * 60)
        p.pause()
    }

    func testPauseStopsTimer() {
        let p = PomodoroTimer()
        p.startFocus()
        p.pause()
        XCTAssertFalse(p.running)
    }

    func testResetReturnsToIdle() {
        let p = PomodoroTimer()
        p.startFocus()
        p.pause()
        p.reset()
        XCTAssertEqual(p.phase, .idle)
        XCTAssertEqual(p.remaining, 25 * 60)
    }

    func testTimeStringFormat() {
        let p = PomodoroTimer()
        p.remaining = 125 // 2:05
        XCTAssertEqual(p.timeString, "02:05")
        p.remaining = 0
        XCTAssertEqual(p.timeString, "00:00")
        p.remaining = 1500 // 25:00
        XCTAssertEqual(p.timeString, "25:00")
    }

    func testProgressReturnsZeroAtStart() {
        let p = PomodoroTimer()
        p.startFocus()
        XCTAssertEqual(p.progress, 0, accuracy: 0.01)
        p.pause()
    }
}

final class PersistenceTests: NBTestCase {

    func testOverrideDirTakesEffect() {
        XCTAssertEqual(Persistence.supportDir.path, tempDir.path)
    }

    func testSaveAndLoadRoundTrip() {
        struct Payload: Codable, Equatable {
            var name: String
            var count: Int
        }
        let original = Payload(name: "hello", count: 42)
        Persistence.save(original, to: "test.json")
        let loaded = Persistence.load(Payload.self, from: "test.json")
        XCTAssertEqual(loaded, original)
    }

    func testLoadReturnsNilForMissingFile() {
        struct P: Codable { var x: Int }
        let loaded = Persistence.load(P.self, from: "does-not-exist.json")
        XCTAssertNil(loaded)
    }

    func testLoadReturnsNilForCorruptFile() {
        let url = Persistence.supportDir.appendingPathComponent("corrupt.json")
        try? "{ not json".write(to: url, atomically: true, encoding: .utf8)
        struct P: Codable { var x: Int }
        XCTAssertNil(Persistence.load(P.self, from: "corrupt.json"))
    }
}
