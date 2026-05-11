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
        }
    }

    static func type(_ string: String) {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        for scalar in string.unicodeScalars {
            guard let event = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) else { continue }
            var c = UniChar(scalar.value)
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            event.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            up?.post(tap: .cghidEventTap)
        }
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
