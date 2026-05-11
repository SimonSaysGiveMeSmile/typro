import Foundation
import AppKit

final class TypoEngine {
    private let monitor = KeyMonitor()
    private let suggester = SuggestionEngine()

    private let stateQueue = DispatchQueue(label: "typro.state")
    private var buffer: String = ""

    private var pending: (typed: String, correction: String, boundary: String)?
    private var suppressCount: Int = 0

    // Guard the space we just appended after an autofix. If the user hits backspace
    // within this window, they likely meant to trigger an older fix — preserve the space.
    private var spaceGuardUntil: Date?
    private let spaceGuardWindow: TimeInterval = 0.35

    private let autoFixConfidenceThreshold: Double = 0.8

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
            buffer.removeAll(); pending = nil; spaceGuardUntil = nil; return false
        }

        if case .backspace = event.kind {
            // Double-BS guard: within the window after an autofix with a trailing space,
            // the user's second BS is almost certainly hitting our inserted space.
            // Swallow it so the space stays.
            if let until = spaceGuardUntil, Date() < until {
                NSLog("[Typro] space-guard: swallowing backspace to preserve inserted space")
                spaceGuardUntil = nil
                return true
            }

            if let p = pending {
                pending = nil
                swallowAndApply(typed: p.typed, correction: p.correction, boundary: p.boundary, addedSpace: false)
                return true
            }

            // Mid-word: swallow and either fix or delete whole word.
            let word = buffer
            guard word.count >= TyproSettings.shared.minWordLength else {
                if !buffer.isEmpty { buffer.removeLast() }
                return false
            }
            buffer.removeAll()
            if let s = suggester.suggest(for: word, language: TyproSettings.shared.language) {
                swallowAndApply(typed: word, correction: s.suggestion, boundary: "", addedSpace: false)
            } else {
                deleteWholeWord(word)
            }
            return true
        }

        pending = nil
        spaceGuardUntil = nil

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
                // Punctuation fixes are high-confidence by nature — auto-apply.
                autoApply(typed: word, correction: fixed, boundary: boundary)
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
            if s.confidence >= self.autoFixConfidenceThreshold {
                NSLog("[Typro] auto-apply (conf \(String(format: "%.2f", s.confidence))): '\(s.typed)' → '\(s.suggestion)'")
                self.autoApply(typed: s.typed, correction: s.suggestion, boundary: boundary)
            } else {
                self.stateQueue.async {
                    NSLog("[Typro] pending (conf \(String(format: "%.2f", s.confidence))): '\(s.typed)' → '\(s.suggestion)'")
                    self.pending = (s.typed, s.suggestion, boundary)
                }
            }
        }
    }

    // Auto-apply without requiring a backspace. User has just typed the boundary char;
    // the word and boundary are already in the doc. Delete them and retype correction + boundary.
    private func autoApply(typed: String, correction: String, boundary: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let deleteCount = typed.count + (boundary.isEmpty ? 0 : 1)
            let retyped = correction + boundary
            self.stateQueue.sync { self.suppressCount += deleteCount + retyped.unicodeScalars.count }
            KeyPoster.backspace(deleteCount)
            KeyPoster.type(retyped)
            // Protect the appended space from an immediate follow-up BS.
            if boundary == " " {
                self.stateQueue.async { self.spaceGuardUntil = Date().addingTimeInterval(self.spaceGuardWindow) }
            }
        }
    }

    private func swallowAndApply(typed: String, correction: String, boundary: String, addedSpace: Bool) {
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
        if boundary == " " {
            stateQueue.async { self.spaceGuardUntil = Date().addingTimeInterval(self.spaceGuardWindow) }
        }
    }

    private func deleteWholeWord(_ word: String) {
        NSLog("[Typro] no suggestion, deleting whole word '\(word)'")
        DispatchQueue.global(qos: .userInitiated).async {
            self.stateQueue.sync { self.suppressCount += word.count }
            KeyPoster.backspace(word.count)
        }
    }
}
