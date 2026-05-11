import Foundation
import AppKit

/// Orchestrates: keystroke buffer → spell-check on word boundary →
/// select the wrong suffix so the user can delete it with one tap.
final class TypoEngine {
    private let monitor = KeyMonitor()
    private let suggester = SuggestionEngine()

    private var buffer: String = ""
    private var lastSuggestion: TypoSuggestion?

    /// After we post selection events, the next keystrokes are our own shift+left.
    /// The system will still deliver them through our tap — ignore them to avoid
    /// feedback loops.
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
    }

    func settingsChanged() {
        if TyproSettings.shared.enabled {
            if monitor.start() == false { /* already running */ }
        } else {
            stop()
        }
    }

    private func handle(_ event: KeyEvent) {
        if let until = ignoreEventsUntil, Date() < until { return }
        ignoreEventsUntil = nil

        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard TyproSettings.shared.shouldActivate(forBundleID: frontBundleID) else {
            buffer.removeAll()
            return
        }

        switch event.kind {
        case .character(let s):
            if s.count == 1, s.first?.isLetter == true {
                buffer.append(s)
            } else {
                buffer.removeAll()
            }
        case .backspace:
            if !buffer.isEmpty { buffer.removeLast() }
        case .caretMove, .modifierCombo:
            buffer.removeAll()
        case .wordBoundary:
            let word = buffer
            buffer.removeAll()
            if word.count >= TyproSettings.shared.minWordLength {
                evaluate(word: word)
            }
        }
    }

    private func evaluate(word: String) {
        let language = TyproSettings.shared.language
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let suggestion = self.suggester.suggest(for: word, language: language) else { return }
            DispatchQueue.main.async { self.applySelection(suggestion) }
        }
    }

    private func applySelection(_ suggestion: TypoSuggestion) {
        NSLog("[Typro] typo '\(suggestion.typed)' → '\(suggestion.suggestion)', selecting last \(suggestion.wrongSuffixLength)")
        lastSuggestion = suggestion

        // Swallow our own synthetic events for a short window so the tap
        // does not loop them back into the buffer.
        ignoreEventsUntil = Date().addingTimeInterval(0.25)

        // 1. caret was just placed after the boundary char (e.g. space).
        //    Step caret back past that boundary char.
        KeyPoster.arrowLeft()
        // 2. Select the wrong suffix.
        KeyPoster.selectLeft(suggestion.wrongSuffixLength)
    }
}
