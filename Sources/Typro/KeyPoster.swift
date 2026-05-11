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

    /// Move caret right one — used to restore position past the boundary char after an early return.
    static func arrowRight() {
        post(keyCode: CGKeyCode(kVK_RightArrow), flags: [])
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
