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

    // MARK: - Modes

    func testDefaultModeIsClassic() {
        let p = PomodoroTimer()
        XCTAssertEqual(p.mode, .classic)
        XCTAssertEqual(p.focusMinutes, 25)
        XCTAssertEqual(p.shortBreakMinutes, 5)
        XCTAssertEqual(p.longBreakMinutes, 15)
    }

    func testSwitchingToDeepModeUpdatesDurations() {
        let p = PomodoroTimer()
        p.mode = .deep
        XCTAssertEqual(p.focusMinutes, 90)
        XCTAssertEqual(p.shortBreakMinutes, 20)
        XCTAssertEqual(p.longBreakMinutes, 45)
    }

    func testCustomModeUsesCustomValues() {
        let p = PomodoroTimer()
        p.customFocusMinutes = 45
        p.customShortBreakMinutes = 7
        p.customLongBreakMinutes = 25
        p.mode = .custom
        XCTAssertEqual(p.focusMinutes, 45)
        XCTAssertEqual(p.shortBreakMinutes, 7)
        XCTAssertEqual(p.longBreakMinutes, 25)
    }

    func testModeChangeUpdatesIdleRemaining() {
        let p = PomodoroTimer()
        XCTAssertEqual(p.remaining, 25 * 60)
        p.mode = .deep
        XCTAssertEqual(p.remaining, 90 * 60,
                       "Idle remaining should reflect new mode duration")
    }

    // MARK: - Skip / extend

    func testExtendAddsMinutesClampedAt60() {
        let p = PomodoroTimer()
        p.startFocus()
        let before = p.remaining
        p.extend(minutes: 5)
        XCTAssertEqual(p.remaining, before + 300)
        p.extend(minutes: 120) // should clamp to 60
        XCTAssertEqual(p.remaining, before + 300 + 3600)
        p.pause()
    }

    func testSkipWhileIdleDoesNothing() {
        let p = PomodoroTimer()
        p.skip()
        XCTAssertEqual(p.phase, .idle)
        XCTAssertTrue(p.sessions.isEmpty)
    }

    // MARK: - Stats

    func testSessionsTodayCountsFocusOnly() {
        let p = PomodoroTimer()
        let now = Date()
        p.sessions = [
            PomodoroSession(phase: PomodoroTimer.Phase.focus.rawValue,
                            startedAt: now, endedAt: now.addingTimeInterval(1500)),
            PomodoroSession(phase: PomodoroTimer.Phase.focus.rawValue,
                            startedAt: now, endedAt: now.addingTimeInterval(1500)),
            PomodoroSession(phase: PomodoroTimer.Phase.shortBreak.rawValue,
                            startedAt: now, endedAt: now.addingTimeInterval(300))
        ]
        XCTAssertEqual(p.sessionsToday(now: now), 2,
                       "Breaks should not count towards sessionsToday")
    }

    func testFocusMinutesTodayAggregates() {
        let p = PomodoroTimer()
        let now = Date()
        p.sessions = [
            PomodoroSession(phase: PomodoroTimer.Phase.focus.rawValue,
                            startedAt: now, endedAt: now.addingTimeInterval(1500)), // 25
            PomodoroSession(phase: PomodoroTimer.Phase.focus.rawValue,
                            startedAt: now, endedAt: now.addingTimeInterval(900))   // 15
        ]
        XCTAssertEqual(p.focusMinutesToday(now: now), 40)
    }

    func testStreakCountsConsecutiveDays() {
        let p = PomodoroTimer()
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!
        let fiveDaysAgo = cal.date(byAdding: .day, value: -5, to: today)!

        p.sessions = [
            PomodoroSession(phase: PomodoroTimer.Phase.focus.rawValue,
                            startedAt: today, endedAt: today.addingTimeInterval(1500)),
            PomodoroSession(phase: PomodoroTimer.Phase.focus.rawValue,
                            startedAt: yesterday, endedAt: yesterday.addingTimeInterval(1500)),
            PomodoroSession(phase: PomodoroTimer.Phase.focus.rawValue,
                            startedAt: twoDaysAgo, endedAt: twoDaysAgo.addingTimeInterval(1500)),
            // Gap — old session shouldn't extend the streak
            PomodoroSession(phase: PomodoroTimer.Phase.focus.rawValue,
                            startedAt: fiveDaysAgo, endedAt: fiveDaysAgo.addingTimeInterval(1500))
        ]
        XCTAssertEqual(p.streakDays(now: now), 3)
    }

    func testStreakZeroWhenNoSessionToday() {
        let p = PomodoroTimer()
        let cal = Calendar.current
        let now = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))!
        p.sessions = [
            PomodoroSession(phase: PomodoroTimer.Phase.focus.rawValue,
                            startedAt: yesterday, endedAt: yesterday.addingTimeInterval(1500))
        ]
        XCTAssertEqual(p.streakDays(now: now), 0,
                       "Streak requires a session for today")
    }

    // MARK: - Session persistence

    func testSessionsPersistAcrossInstances() {
        let p1 = PomodoroTimer()
        p1.sessions = [
            PomodoroSession(phase: PomodoroTimer.Phase.focus.rawValue,
                            startedAt: Date(), endedAt: Date().addingTimeInterval(1500))
        ]
        let p2 = PomodoroTimer()
        XCTAssertEqual(p2.sessions.count, 1)
    }

    // MARK: - Config persistence

    func testConfigPersistsAcrossInstances() {
        let p1 = PomodoroTimer()
        p1.mode = .deep
        p1.dailyGoal = 7
        p1.autoStartBreak = false
        p1.autoStartNextFocus = true

        let p2 = PomodoroTimer()
        XCTAssertEqual(p2.mode, .deep)
        XCTAssertEqual(p2.dailyGoal, 7)
        XCTAssertFalse(p2.autoStartBreak)
        XCTAssertTrue(p2.autoStartNextFocus)
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
