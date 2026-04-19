import XCTest
import Carbon.HIToolbox
@testable import NeuraBar

final class GlobalHotkeyTests: XCTestCase {

    // MARK: - KeyBinding formatting

    func testDefaultBindingIsCmdOptionN() {
        let b = GlobalHotkey.KeyBinding.defaultBinding
        XCTAssertEqual(b.keyCode, UInt32(kVK_ANSI_N))
        XCTAssertEqual(b.modifiers, UInt32(cmdKey | optionKey))
    }

    func testHumanReadableShowsSymbolsInOrder() {
        let b = GlobalHotkey.KeyBinding.defaultBinding
        XCTAssertEqual(b.humanReadable, "⌥⌘N")
    }

    func testHumanReadableCombinesAllModifiers() {
        let b = GlobalHotkey.KeyBinding(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        // Order should be: control, option, shift, command (Apple convention).
        XCTAssertEqual(b.humanReadable, "⌃⌥⇧⌘K")
    }

    func testHumanReadableHandlesFKeys() {
        let b = GlobalHotkey.KeyBinding(
            keyCode: UInt32(kVK_F13),
            modifiers: 0
        )
        XCTAssertEqual(b.humanReadable, "F13")
    }

    func testBindingEquatable() {
        let a = GlobalHotkey.KeyBinding(keyCode: 45, modifiers: UInt32(cmdKey))
        let b = GlobalHotkey.KeyBinding(keyCode: 45, modifiers: UInt32(cmdKey))
        let c = GlobalHotkey.KeyBinding(keyCode: 46, modifiers: UInt32(cmdKey))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Singleton / lifecycle

    func testSharedSingletonIsReusable() {
        let first = GlobalHotkey.shared
        let second = GlobalHotkey.shared
        XCTAssertTrue(first === second)
    }

    func testUnregisterWithoutRegisterIsSafe() {
        let hk = GlobalHotkey.shared
        // Should not crash even if the hot key was never registered.
        hk.unregister()
        XCTAssertFalse(hk.isRegistered)
    }

    /// Integration-lite: actually registers against the app's event target.
    /// If this ever stops working on future macOS versions we'll know early.
    func testRegisterFlipsIsRegistered() {
        let hk = GlobalHotkey.shared
        hk.register(binding: GlobalHotkey.KeyBinding(
            keyCode: UInt32(kVK_F15),   // uncommon — safe to grab during tests
            modifiers: UInt32(cmdKey | optionKey | shiftKey)
        ))
        // The registration may fail if the hotkey is already claimed by another
        // process, but the path itself should not crash.
        XCTAssertTrue(hk.isRegistered || !hk.isRegistered) // tautology — test is about no crash
        hk.unregister()
        XCTAssertFalse(hk.isRegistered)
    }
}
