import Foundation
import AppKit

final class TypoEngine {
    private let monitor = KeyMonitor()
    private let suggester = SuggestionEngine()

    private let stateQueue = DispatchQueue(label: "typro.state")
    private var buffer: String = ""
    private var precededBySpace: Bool = false

    // Pending fix waiting for a backspace to trigger.
    private var pending: (typed: String, correction: String, boundary: String)?

    // Remaining synthetic keyDown events to ignore.
    private var suppressCount: Int = 0

    func start() {
        // shouldSwallow runs synchronously on the tap thread.
        monitor.shouldSwallow = { [weak self] event in
            guard let self else { return false }
            return self.stateQueue.sync { self.handleSync(event) }
        }
        guard monitor.start() else {
            NSLog("[Typro] Failed to create event tap. Accessibility permission likely missing.")
            return
        }
        NSLog("[Typro] Key monitor started.")
    }

    func stop() {
        monitor.stop()
        stateQueue.sync { buffer.removeAll(); pending = nil }
    }

    func settingsChanged() {
        if TyproSettings.shared.enabled { _ = monitor.start() } else { stop() }
    }

    // Called on tap thread. Returns true to swallow the event.
    private func handleSync(_ event: KeyEvent) -> Bool {
        if suppressCount > 0 { suppressCount -= 1; return false }

        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard TyproSettings.shared.shouldActivate(forBundleID: frontBundleID) else {
            buffer.removeAll(); pending = nil; return false
        }

        if case .backspace = event.kind, let p = pending {
            // Swallow the user's backspace entirely. We replace the text ourselves.
            pending = nil
            let typed = p.typed, correction = p.correction, boundary = p.boundary
            DispatchQueue.global(qos: .userInitiated).async {
                self.applyFix(typed: typed, correction: correction, boundary: boundary)
            }
            return true
        }

        pending = nil

        switch event.kind {
        case .backspace:
            let preBuffer = buffer
            if !buffer.isEmpty { buffer.removeLast() }
            if preBuffer.count >= TyproSettings.shared.minWordLength, precededBySpace {
                scheduleMidWordSuggest(word: preBuffer)
            }

        case .character(let s):
            if s.count == 1, s.first?.isLetter == true {
                buffer.append(s)
            } else {
                buffer.removeAll()
                precededBySpace = false
            }

        case .caretMove, .modifierCombo:
            buffer.removeAll()
            precededBySpace = false

        case .wordBoundary(let boundary):
            let word = buffer
            let wasSpace = precededBySpace
            buffer.removeAll()
            precededBySpace = (boundary == " ")

            if word.isEmpty && wasSpace && PunctuationFixer.isSpaceBeforePunct(boundary) {
                pending = (" ", boundary, "")
                return false
            }

            guard word.count >= TyproSettings.shared.minWordLength else { return false }

            if let fixed = PunctuationFixer.fix(word: word, boundary: boundary) {
                let isCap = fixed.first?.isUppercase == true
                if wasSpace || isCap {
                    pending = (word, fixed, boundary)
                }
                return false
            }

            scheduleSpellSuggest(word: word, boundary: boundary, wasSpace: wasSpace)
        }
        return false
    }

    private func scheduleMidWordSuggest(word: String) {
        let language = TyproSettings.shared.language
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let s = self.suggester.suggest(for: word, language: language) else { return }
            self.stateQueue.async {
                NSLog("[Typro] mid-word pending: '\(s.typed)' → '\(s.suggestion)'")
                // One char was already deleted. Typed-in-doc is word.dropLast().
                self.pending = (String(s.typed.dropLast()), s.suggestion, "")
            }
        }
    }

    private func scheduleSpellSuggest(word: String, boundary: String, wasSpace: Bool) {
        let language = TyproSettings.shared.language
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let s = self.suggester.suggest(for: word, language: language) else { return }
            let isCap = s.suggestion.first?.isUppercase == true
            guard wasSpace || isCap else { return }
            self.stateQueue.async {
                NSLog("[Typro] spell pending: '\(s.typed)' → '\(s.suggestion)'")
                self.pending = (s.typed, s.suggestion, boundary)
            }
        }
    }

    // Runs off tap thread. User's backspace was swallowed — we control the text entirely.
    private func applyFix(typed: String, correction: String, boundary: String) {
        // Space-before-punct: " ," with user's BS swallowed. The punct is still there.
        // Delete punct + space (2), retype punct.
        if typed == " " && boundary.isEmpty {
            NSLog("[Typro] apply space-before-punct")
            stateQueue.sync { suppressCount += 2 }
            KeyPoster.backspace(2)
            KeyPoster.type(correction)
            return
        }

        // Normal post-boundary fix: "teh " with user's BS swallowed — "teh " still in doc.
        // Delete typed.count + (boundary ? 1 : 0), retype correction + boundary.
        let deleteCount = typed.count + (boundary.isEmpty ? 0 : 1)
        let retyped = correction + boundary
        NSLog("[Typro] apply fix: delete \(deleteCount), type '\(retyped)'")
        stateQueue.sync { suppressCount += deleteCount + retyped.unicodeScalars.count }
        KeyPoster.backspace(deleteCount)
        KeyPoster.type(retyped)
    }
}
