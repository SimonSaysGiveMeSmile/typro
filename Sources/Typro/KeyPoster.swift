import Foundation
import Carbon.HIToolbox
import CoreGraphics

/// Posts synthetic key events to move the caret and select text.
enum KeyPoster {
    /// Select N characters to the LEFT of the current caret by posting Shift+LeftArrow.
    /// Called after a word boundary has been typed, and after we have already
    /// moved the caret back past that boundary character.
    static func selectLeft(_ count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            post(keyCode: CGKeyCode(kVK_LeftArrow), flags: .maskShift)
        }
    }

    /// Move caret left one (no selection) — used to skip back past the just-typed boundary char.
    static func arrowLeft() {
        post(keyCode: CGKeyCode(kVK_LeftArrow), flags: [])
    }

    static func backspace(_ count: Int = 1) {
        guard count > 0 else { return }
        for _ in 0..<count {
            post(keyCode: CGKeyCode(kVK_Delete), flags: [])
            usleep(8_000)
        }
    }

    static func type(_ string: String) {
        let delay: useconds_t = 8_000
        for scalar in string.unicodeScalars {
            var c = UniChar(scalar.value)
            // Passing nil source is accepted and works in most apps including terminals.
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else { continue }
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            down.post(tap: .cghidEventTap)

            guard let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { continue }
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            up.post(tap: .cghidEventTap)

            usleep(delay)
        }
    }

    // Total synthetic events posted: used by TypoEngine to count what to suppress.
    static func syntheticEventCount(deleteCount: Int, typeString: String) -> Int {
        deleteCount * 2 + typeString.unicodeScalars.count * 2
    }

    private static func post(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
