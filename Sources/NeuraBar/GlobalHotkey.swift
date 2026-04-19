import Foundation
import AppKit
import Carbon.HIToolbox

/// System-wide hotkey registration using the Carbon `RegisterEventHotKey` API.
///
/// Why Carbon: it's the only public API that registers a process-scoped hotkey
/// receiver without requiring Accessibility permission. The key press is
/// delivered to our app even when another app is focused, but the originating
/// keystroke still reaches the focused app's shortcut handler too, so we stay
/// well-behaved and don't intercept common chords.
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    /// Default shortcut: ⌘⌥N — not used by Finder, system, browsers, or major
    /// apps (picked specifically so NeuraBar doesn't steal existing user
    /// muscle memory).
    struct KeyBinding: Equatable {
        let keyCode: UInt32   // Virtual key code (kVK_* from HIToolbox)
        let modifiers: UInt32 // Carbon modifier mask (cmdKey, optionKey, …)

        static let defaultBinding = KeyBinding(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(cmdKey | optionKey)
        )

        var humanReadable: String {
            var parts: [String] = []
            if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
            if modifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
            if modifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
            if modifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
            parts.append(Self.keyName(for: keyCode))
            return parts.joined()
        }

        private static func keyName(for code: UInt32) -> String {
            switch Int(code) {
            case kVK_ANSI_N: return "N"
            case kVK_ANSI_B: return "B"
            case kVK_ANSI_J: return "J"
            case kVK_ANSI_K: return "K"
            case kVK_Space: return "Space"
            case kVK_F13: return "F13"
            case kVK_F14: return "F14"
            case kVK_F15: return "F15"
            default: return "?"
            }
        }
    }

    private(set) var isRegistered = false
    private(set) var binding: KeyBinding = .defaultBinding
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    var onTrigger: (() -> Void)?

    private static let signature: OSType = 0x4E425242 // 'NBRB' — NeuraBar
    private static let hotKeyID: UInt32 = 1

    func register(binding: KeyBinding = .defaultBinding) {
        unregister()
        self.binding = binding

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Install a process-level event handler that forwards hotkey presses
        // to `onTrigger` on the main queue.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, eventRef: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
                guard let userData = userData else { return noErr }
                let instance = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { instance.onTrigger?() }
                _ = eventRef
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &handlerRef
        )
        guard status == noErr else { return }

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let regStatus = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if regStatus == noErr {
            hotKeyRef = ref
            isRegistered = true
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let h = handlerRef {
            RemoveEventHandler(h)
            handlerRef = nil
        }
        isRegistered = false
    }

    deinit { unregister() }
}
