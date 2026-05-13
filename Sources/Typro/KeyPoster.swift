import Foundation
import Carbon.HIToolbox
import CoreGraphics

/// Posts synthetic key events to move the caret and modify text.
enum KeyPoster {
    // Marker stored in `eventSourceUserData` on every event we post,
    // so KeyMonitor can skip our own events without timing-based suppression.
    static let typroTag: Int64 = 0x54595052_4F310001  // "TYPRO1\x00\x01"

    private static let interEventDelay: useconds_t = 1_000

    static func backspace(_ count: Int = 1) {
        guard count > 0, let src = CGEventSource(stateID: .hidSystemState) else { return }
        let kc = CGKeyCode(kVK_Delete)
        for _ in 0..<count {
            postKey(src: src, keyCode: kc, flags: [])
        }
    }

    static func optionBackspace(_ count: Int = 1) {
        guard count > 0, let src = CGEventSource(stateID: .hidSystemState) else { return }
        let kc = CGKeyCode(kVK_Delete)
        for _ in 0..<count {
            postKey(src: src, keyCode: kc, flags: .maskAlternate)
        }
    }

    static func type(_ string: String) {
        for scalar in string.unicodeScalars {
            var c = UniChar(scalar.value)
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
                down.setIntegerValueField(.eventSourceUserData, value: typroTag)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
                up.setIntegerValueField(.eventSourceUserData, value: typroTag)
                up.post(tap: .cghidEventTap)
            }
            usleep(interEventDelay)
        }
    }

    static func selectAllAndDelete() {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        postKey(src: src, keyCode: CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
        usleep(interEventDelay)
        postKey(src: src, keyCode: CGKeyCode(kVK_Delete), flags: [])
    }

    private static func postKey(src: CGEventSource, keyCode: CGKeyCode, flags: CGEventFlags) {
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true) {
            down.flags = flags
            down.setIntegerValueField(.eventSourceUserData, value: typroTag)
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            up.flags = flags
            up.setIntegerValueField(.eventSourceUserData, value: typroTag)
            up.post(tap: .cghidEventTap)
        }
        usleep(interEventDelay)
    }
}

