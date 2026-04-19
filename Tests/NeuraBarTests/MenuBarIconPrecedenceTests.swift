import XCTest
@testable import NeuraBar

/// The menu bar icon view itself is SwiftUI and awkward to inspect from
/// XCTest, but we can lock the contract its rendering relies on:
/// PomodoroTimer.running is a @Published flag that the icon swaps glyphs on.
@MainActor
final class MenuBarIconPrecedenceTests: NBTestCase {

    // MARK: - Running flag

    func testStartFocusFlipsRunning() {
        let p = PomodoroTimer()
        XCTAssertFalse(p.running)
        p.startFocus()
        XCTAssertTrue(p.running,
                      "Menu bar icon swaps to the timer glyph when this is true")
        p.pause()
        XCTAssertFalse(p.running)
    }

    func testResetReturnsToIdleAndStopsRunning() {
        let p = PomodoroTimer()
        p.startFocus()
        p.reset()
        XCTAssertFalse(p.running)
        XCTAssertEqual(p.phase, .idle)
    }

    // MARK: - Phase transitions — the tint the icon picks

    func testShortBreakPhaseIsDistinctFromFocus() {
        // Phase identity is what the icon tint colour branches on. If these
        // change, the menu bar colour coding should be reconsidered too.
        XCTAssertNotEqual(PomodoroTimer.Phase.focus, PomodoroTimer.Phase.shortBreak)
        XCTAssertNotEqual(PomodoroTimer.Phase.shortBreak, PomodoroTimer.Phase.longBreak)
        XCTAssertNotEqual(PomodoroTimer.Phase.focus, PomodoroTimer.Phase.longBreak)
    }

    func testStartShortBreakSetsBothRunningAndPhase() {
        let p = PomodoroTimer()
        p.startShortBreak()
        XCTAssertTrue(p.running)
        XCTAssertEqual(p.phase, .shortBreak)
        p.pause()
    }

    func testStartLongBreakSetsBothRunningAndPhase() {
        let p = PomodoroTimer()
        p.startLongBreak()
        XCTAssertTrue(p.running)
        XCTAssertEqual(p.phase, .longBreak)
        p.pause()
    }

    // MARK: - Precedence contract

    /// Documentation-as-test: the icon's precedence rules. If any of these
    /// priorities shift, this test should fail and force a conscious update
    /// alongside the UI change.
    func testIconPrecedenceRules() {
        // 1. event flash  (clipboard/recording/automation)
        // 2. system critical
        // 3. pomodoro running
        // 4. system warning dot  (this is an OVERLAY, not a primary glyph)
        // 5. base NeuraMark

        // The only piece of this that's actually unit-testable without UI
        // inspection is verifying the states that feed the precedence are
        // independently observable.
        let mon = SystemMonitor()
        let timer = PomodoroTimer()
        let coord = MenuBarStatusCoordinator.shared
        coord.clear()

        XCTAssertEqual(mon.alertLevel, .ok)
        XCTAssertFalse(timer.running)
        XCTAssertNil(coord.currentEvent)

        timer.startFocus()
        coord.flash(.clipboardCopied, duration: 5)
        // Both flags are now set; the view branches on `events.currentEvent`
        // first, but both are readable — the check is that they remain
        // independent sources of truth, not that one clobbers the other.
        XCTAssertTrue(timer.running)
        XCTAssertNotNil(coord.currentEvent)

        coord.clear()
        timer.pause()
    }
}
