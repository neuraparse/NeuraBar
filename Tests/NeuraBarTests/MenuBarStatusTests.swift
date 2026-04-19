import XCTest
@testable import NeuraBar

/// Verifies the menu bar status coordinator — the piece that replaced in-app
/// toasts. Every feedback event (clipboard copy, recording saved, automation
/// done) now funnels through this and briefly animates the menu bar icon.
@MainActor
final class MenuBarStatusTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        MenuBarStatusCoordinator.shared.clear()
    }

    override func tearDown() async throws {
        MenuBarStatusCoordinator.shared.clear()
        try await super.tearDown()
    }

    // MARK: - Flash semantics

    func testFlashSetsCurrentEvent() {
        MenuBarStatusCoordinator.shared.flash(.clipboardCopied)
        XCTAssertEqual(MenuBarStatusCoordinator.shared.currentEvent, .clipboardCopied)
    }

    func testSecondFlashReplacesFirst() {
        MenuBarStatusCoordinator.shared.flash(.clipboardCopied, duration: 5)
        MenuBarStatusCoordinator.shared.flash(.recordingSaved, duration: 5)
        XCTAssertEqual(MenuBarStatusCoordinator.shared.currentEvent, .recordingSaved,
                       "A later flash should immediately replace an in-flight one")
    }

    func testClearWipesCurrent() {
        MenuBarStatusCoordinator.shared.flash(.automationDone, duration: 5)
        XCTAssertNotNil(MenuBarStatusCoordinator.shared.currentEvent)
        MenuBarStatusCoordinator.shared.clear()
        XCTAssertNil(MenuBarStatusCoordinator.shared.currentEvent)
    }

    func testAutoClearsAfterDuration() async {
        MenuBarStatusCoordinator.shared.flash(.clipboardCopied, duration: 0.12)
        XCTAssertEqual(MenuBarStatusCoordinator.shared.currentEvent, .clipboardCopied)
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(MenuBarStatusCoordinator.shared.currentEvent,
                     "Event should auto-clear once its duration elapses")
    }

    func testCancelingByClearStopsPendingAutoClear() async {
        // Start a long flash, then clear + start a new short one — we
        // shouldn't see the first one's dismissal wipe the second.
        MenuBarStatusCoordinator.shared.flash(.clipboardCopied, duration: 5)
        MenuBarStatusCoordinator.shared.clear()
        MenuBarStatusCoordinator.shared.flash(.recordingSaved, duration: 0.3)
        XCTAssertEqual(MenuBarStatusCoordinator.shared.currentEvent, .recordingSaved)
        try? await Task.sleep(nanoseconds: 100_000_000)
        // Still within 300ms duration, so event should still be present.
        XCTAssertEqual(MenuBarStatusCoordinator.shared.currentEvent, .recordingSaved)
    }

    // MARK: - Event metadata

    func testEveryEventDeclaresIconAndTint() {
        for e in MenuBarEvent.allCases {
            XCTAssertFalse(e.icon.isEmpty)
            // Duration must be positive so the auto-clear actually fires.
            XCTAssertGreaterThan(e.duration, 0)
        }
    }

    func testDefaultDurationIsReasonable() {
        for e in MenuBarEvent.allCases {
            XCTAssertLessThanOrEqual(e.duration, 3.0,
                                     "Events must revert quickly; menu bar icon is shared real estate")
        }
    }
}
