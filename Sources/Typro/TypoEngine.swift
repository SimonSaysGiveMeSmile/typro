import Foundation
import AppKit

final class TypoEngine {
    private let monitor = KeyMonitor()
    private let suggester = SuggestionEngine()

    private var buffer: String = ""
    private var precededBySpace: Bool = false

    // Pending fix waiting for a backspace to confirm.
    // typed: the misspelled word as typed; correction: replacement; boundary: boundary char typed after word (or "" for mid-word).
    private var pending: (typed: String, correction: String, boundary: String)?

    // Count of synthetic key events still in flight — ignore that many incoming events.
    private var suppressCount: Int = 0

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
        if TyproSettings.shared.enabled { _ = monitor.start() } else { stop() }
    }

    private func handle(_ event: KeyEvent) {
        if suppressCount > 0 { suppressCount -= 1; return }

        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard TyproSettings.shared.shouldActivate(forBundleID: frontBundleID) else {
            buffer.removeAll(); pending = nil; return
        }

        if case .backspace = event.kind {
            // 1. Pending from a word-boundary? Apply it.
            if let p = pending {
                pending = nil
                applyPostBoundaryFix(typed: p.typed, correction: p.correction, boundary: p.boundary)
                return
            }
            // 2. Mid-word backspace: the OS is about to delete one char from the buffer.
            //    Check if the pre-deletion buffer has a fix; if so, apply it.
            let preBuffer = buffer
            if !buffer.isEmpty { buffer.removeLast() }
            if preBuffer.count >= TyproSettings.shared.minWordLength, precededBySpace {
                evaluateMidWord(word: preBuffer)
            }
            return
        }

        pending = nil

        switch event.kind {
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

            // Space-before-punctuation: "word ," — buffer is empty after the space.
            if word.isEmpty && wasSpace && PunctuationFixer.isSpaceBeforePunct(boundary) {
                NSLog("[Typro] space-before-punct pending")
                pending = (" ", boundary, "")
                return
            }

            guard word.count >= TyproSettings.shared.minWordLength else { return }

            if let fixed = PunctuationFixer.fix(word: word, boundary: boundary) {
                let isCap = fixed.first?.isUppercase == true
                guard wasSpace || isCap else { return }
                NSLog("[Typro] punct pending: '\(word)' → '\(fixed)'")
                pending = (word, fixed, boundary)
                return
            }

            let language = TyproSettings.shared.language
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                guard let s = self.suggester.suggest(for: word, language: language) else { return }
                let isCap = s.suggestion.first?.isUppercase == true
                guard wasSpace || isCap else { return }
                DispatchQueue.main.async {
                    NSLog("[Typro] spell pending: '\(s.typed)' → '\(s.suggestion)'")
                    self.pending = (s.typed, s.suggestion, boundary)
                }
            }

        case .backspace:
            break // handled above
        }
    }

    // Mid-word backspace: user deleted the last char of `word` while typing.
    // Offer a fix — next backspace will apply it.
    private func evaluateMidWord(word: String) {
        let language = TyproSettings.shared.language
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let s = self.suggester.suggest(for: word, language: language) else { return }
            DispatchQueue.main.async {
                NSLog("[Typro] mid-word pending: '\(s.typed)' → '\(s.suggestion)'")
                // boundary is "" — mid-word, no trailing char to restore.
                // typed is the pre-deletion word, but one char is already gone from the doc.
                self.pending = (String(s.typed.dropLast()), s.suggestion, "")
            }
        }
    }

    // Apply a fix queued from a word-boundary event.
    // The user just pressed backspace, so the OS already deleted the boundary char.
    // We need to: delete the typed word chars, then type correction + boundary.
    private func applyPostBoundaryFix(typed: String, correction: String, boundary: String) {
        // Space-before-punct special case: typed is " ", correction is punct, boundary is "".
        // The user's backspace already deleted the punct. Now delete the space + retype punct.
        if typed == " " && boundary.isEmpty {
            NSLog("[Typro] apply space-before-punct")
            suppressCount = 1 * 2 + correction.unicodeScalars.count * 2
            KeyPoster.backspace(1)
            KeyPoster.type(correction)
            return
        }

        NSLog("[Typro] apply post-boundary fix: delete \(typed.count), type '\(correction + boundary)'")
        let retyped = correction + boundary
        suppressCount = typed.count * 2 + retyped.unicodeScalars.count * 2
        KeyPoster.backspace(typed.count)
        KeyPoster.type(retyped)
    }
}
