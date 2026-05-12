import Foundation
import Carbon.HIToolbox
import CoreGraphics

struct KeyEvent {
    enum Kind {
        case character(String)
        case wordBoundary(String)
        case backspace
        case tab
        case escape
        case caretMove
        case modifierCombo
    }
    let kind: Kind
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

extension KeyEvent {
    init?(cgEvent: CGEvent) {
        let keyCode = CGKeyCode(cgEvent.getIntegerValueField(.keyboardEventKeycode))
        let flags = cgEvent.flags

        let command = flags.contains(.maskCommand)
        let control = flags.contains(.maskControl)
        let option = flags.contains(.maskAlternate)

        if command || control {
            self = KeyEvent(kind: .modifierCombo, keyCode: keyCode, flags: flags)
            return
        }

        switch Int(keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            self = KeyEvent(kind: .backspace, keyCode: keyCode, flags: flags)
            return
        case kVK_Tab:
            self = KeyEvent(kind: .tab, keyCode: keyCode, flags: flags)
            return
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
             kVK_Return, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown:
            self = KeyEvent(kind: .caretMove, keyCode: keyCode, flags: flags)
            return
        case kVK_Escape:
            self = KeyEvent(kind: .escape, keyCode: keyCode, flags: flags)
            return
        default:
            break
        }

        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        cgEvent.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else {
            self = KeyEvent(kind: .caretMove, keyCode: keyCode, flags: flags)
            return
        }
        let s = String(utf16CodeUnits: chars, count: length)

        if option && s.count == 1 {
            self = KeyEvent(kind: .modifierCombo, keyCode: keyCode, flags: flags)
            return
        }

        if let scalar = s.unicodeScalars.first, Self.isWordBoundary(scalar) {
            self = KeyEvent(kind: .wordBoundary(s), keyCode: keyCode, flags: flags)
        } else {
            self = KeyEvent(kind: .character(s), keyCode: keyCode, flags: flags)
        }
    }

    private static func isWordBoundary(_ scalar: Unicode.Scalar) -> Bool {
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return true }
        let punct: Set<Unicode.Scalar> = [".", ",", "!", "?", ";", ":", ")", "]", "}", "\"", "'", "—", "–", "-", "/"]
        return punct.contains(scalar)
    }
}

final class KeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var onEvent: ((KeyEvent) -> Void)?
    // Called synchronously. Return true to swallow the event (drop it).
    var shouldSwallow: ((KeyEvent) -> Bool)?

    func start() -> Bool {
        stop()
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                // Ignore events we posted ourselves — they carry our tag.
                if event.getIntegerValueField(.eventSourceUserData) == KeyPoster.typroTag {
                    return Unmanaged.passUnretained(event)
                }
                if type == .keyDown, let ke = KeyEvent(cgEvent: event) {
                    // Run synchronously on the tap thread so we can swallow the event.
                    if monitor.shouldSwallow?(ke) == true {
                        return nil
                    }
                    monitor.onEvent?(ke)
                } else if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.eventTap = tap
        self.runLoopSource = source
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }

    deinit { stop() }
}
