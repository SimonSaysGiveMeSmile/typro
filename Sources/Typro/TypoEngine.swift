import Foundation
import AppKit

final class TypoEngine {
    private let monitor = KeyMonitor()
    private let suggester = SuggestionEngine()

    private let stateQueue = DispatchQueue(label: "typro.state")
    private var buffer: String = ""

    private var pending: (typed: String, correction: String, boundary: String)?
    private var suppressCount: Int = 0

    func start() {
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

    private func handleSync(_ event: KeyEvent) -> Bool {
        if suppressCount > 0 { suppressCount -= 1; return false }

        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard TyproSettings.shared.shouldActivate(forBundleID: frontBundleID) else {
            buffer.removeAll(); pending = nil; return false
        }

        if case .backspace = event.kind {
            // If we have a pending post-boundary fix from a prior word, apply that.
            if let p = pending {
                pending = nil
                swallowAndFix(typed: p.typed, correction: p.correction, boundary: p.boundary)
                return true
            }
            // Mid-word backspace: swallow it, pick a fix synchronously.
            let word = buffer
            guard word.count >= TyproSettings.shared.minWordLength else {
                if !buffer.isEmpty { buffer.removeLast() }
                return false
            }
            buffer.removeAll()
            let language = TyproSettings.shared.language
            if let s = suggester.suggest(for: word, language: language) {
                swallowAndFix(typed: word, correction: s.suggestion, boundary: "")
            } else {
                // Unsure — delete the whole word.
                deleteWholeWord(word)
            }
            return true
        }

        pending = nil

        switch event.kind {
        case .character(let s):
            if s.count == 1, s.first?.isLetter == true {
                buffer.append(s)
            } else {
                buffer.removeAll()
            }

        case .caretMove, .modifierCombo:
            buffer.removeAll()

        case .wordBoundary(let boundary):
            let word = buffer
            buffer.removeAll()

            if word.isEmpty && PunctuationFixer.isSpaceBeforePunct(boundary) {
                pending = (" ", boundary, "")
                return false
            }

            guard word.count >= TyproSettings.shared.minWordLength else { return false }

            if let fixed = PunctuationFixer.fix(word: word, boundary: boundary) {
                pending = (word, fixed, boundary)
                return false
            }

            scheduleSpellSuggest(word: word, boundary: boundary)

        case .backspace:
            break
        }
        return false
    }

    private func scheduleSpellSuggest(word: String, boundary: String) {
        let language = TyproSettings.shared.language
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let s = self.suggester.suggest(for: word, language: language) else { return }
            self.stateQueue.async {
                NSLog("[Typro] spell pending: '\(s.typed)' → '\(s.suggestion)'")
                self.pending = (s.typed, s.suggestion, boundary)
            }
        }
    }

    private func swallowAndFix(typed: String, correction: String, boundary: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.applyFix(typed: typed, correction: correction, boundary: boundary)
        }
    }

    private func applyFix(typed: String, correction: String, boundary: String) {
        if typed == " " && boundary.isEmpty {
            NSLog("[Typro] apply space-before-punct")
            stateQueue.sync { suppressCount += 2 }
            KeyPoster.backspace(2)
            KeyPoster.type(correction)
            return
        }

        let deleteCount = typed.count + (boundary.isEmpty ? 0 : 1)
        let retyped = correction + boundary
        NSLog("[Typro] apply fix: delete \(deleteCount), type '\(retyped)'")
        stateQueue.sync { suppressCount += deleteCount + retyped.unicodeScalars.count }
        KeyPoster.backspace(deleteCount)
        KeyPoster.type(retyped)
    }

    private func deleteWholeWord(_ word: String) {
        NSLog("[Typro] no suggestion, deleting whole word '\(word)'")
        DispatchQueue.global(qos: .userInitiated).async {
            self.stateQueue.sync { self.suppressCount += word.count }
            KeyPoster.backspace(word.count)
        }
    }
}
