import Foundation
import AppKit

final class TypoEngine {
    private let monitor = KeyMonitor()
    private let suggester = SuggestionEngine()

    private var buffer: String = ""
    private var precededBySpace: Bool = false

    // Set after a word boundary when a typo is detected.
    // Cleared on the next keystroke (consumed or dismissed).
    private var pending: (suggestion: TypoSuggestion, boundary: String)?

    // Suppress our own synthetic events from re-entering the handler.
    private var ignoreEventsUntil: Date?

    func start() {
        monitor.onEvent = { [weak self] in self?.handle($0) }
        guard monitor.start() else {
            NSLog("[Typro] Failed to create event tap. Accessibility permission likely missing.")
            return
        }
        NSLog("[Typro] Key monitor started.")
    }

    func stop() {
        monitor.stop()
        buffer.removeAll()
        pending = nil
    }

    func settingsChanged() {
        if TyproSettings.shared.enabled {
            _ = monitor.start()
        } else {
            stop()
        }
    }

    private func handle(_ event: KeyEvent) {
        if let until = ignoreEventsUntil, Date() < until { return }
        ignoreEventsUntil = nil

        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard TyproSettings.shared.shouldActivate(forBundleID: frontBundleID) else {
            buffer.removeAll(); pending = nil
            return
        }

        // If a suggestion is waiting and the user hits backspace, auto-fix.
        if case .backspace = event.kind, let p = pending {
            pending = nil
            applyFix(p.suggestion, boundary: p.boundary)
            return
        }

        // Any other key dismisses the pending suggestion without acting.
        pending = nil

        switch event.kind {
        case .character(let s):
            if s.count == 1, s.first?.isLetter == true {
                buffer.append(s)
            } else {
                buffer.removeAll()
                precededBySpace = false
            }
        case .backspace:
            if !buffer.isEmpty { buffer.removeLast() }
        case .caretMove, .modifierCombo:
            buffer.removeAll()
            precededBySpace = false
        case .wordBoundary(let boundary):
            let word = buffer
            let waspreceded = precededBySpace
            buffer.removeAll()
            precededBySpace = boundary == " "
            if word.count >= TyproSettings.shared.minWordLength {
                evaluate(word: word, boundary: boundary, precededBySpace: waspreceded)
            }
        }
    }

    private func evaluate(word: String, boundary: String, precededBySpace: Bool) {
        let language = TyproSettings.shared.language
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let suggestion = self.suggester.suggest(for: word, language: language) else { return }
            // Skip if not preceded by a space, unless the suggestion is capitalized (start of sentence / proper noun)
            let suggestionIsCapitalized = suggestion.suggestion.first?.isUppercase == true
            guard precededBySpace || suggestionIsCapitalized else { return }
            DispatchQueue.main.async {
                NSLog("[Typro] pending fix: '\(suggestion.typed)' → '\(suggestion.suggestion)'")
                self.pending = (suggestion, boundary)
            }
        }
    }

    private func applyFix(_ suggestion: TypoSuggestion, boundary: String) {
        NSLog("[Typro] applying fix: '\(suggestion.typed)' → '\(suggestion.suggestion)'")
        // Suppress the synthetic events we're about to post.
        // typed.count + 1 (boundary) backspaces, then type correction + boundary.
        let deleteCount = suggestion.typed.count + 1
        ignoreEventsUntil = Date().addingTimeInterval(Double(deleteCount + suggestion.suggestion.count + 1) * 0.02 + 0.1)
        KeyPoster.backspace(deleteCount)
        KeyPoster.type(suggestion.suggestion + boundary)
    }
}
