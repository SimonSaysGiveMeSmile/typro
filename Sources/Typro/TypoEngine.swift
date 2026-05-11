import Foundation
import AppKit

final class TypoEngine {
    private let monitor = KeyMonitor()
    private let suggester = SuggestionEngine()

    private var buffer: String = ""
    private var precededBySpace: Bool = false

    // Pending fix waiting for a backspace to confirm.
    private var pending: (typed: String, correction: String, boundary: String)?

    // Count of synthetic keyDown events still in flight — ignore that many incoming events.
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

        // Backspace with a pending fix → apply it.
        if case .backspace = event.kind, let p = pending {
            pending = nil
            applyFix(typed: p.typed, correction: p.correction, boundary: p.boundary)
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

        case .backspace:
            if !buffer.isEmpty { buffer.removeLast() }

        case .caretMove, .modifierCombo:
            buffer.removeAll()
            precededBySpace = false

        case .wordBoundary(let boundary):
            let word = buffer
            let wasSpace = precededBySpace
            buffer.removeAll()
            precededBySpace = (boundary == " ")

            // Space-before-punctuation: buffer is empty (user typed " ,")
            // The space is already in the doc; we need to delete it + retype boundary.
            if word.isEmpty && wasSpace && PunctuationFixer.isSpaceBeforePunct(boundary) {
                NSLog("[Typro] space-before-punct: deleting space, retyping '\(boundary)'")
                pending = (" ", boundary, "")
                return
            }

            guard word.count >= TyproSettings.shared.minWordLength else { return }

            // Punctuation fix (apostrophe, stray chars) — synchronous, no spell check needed.
            if let fixed = PunctuationFixer.fix(word: word, boundary: boundary) {
                let isCapitalized = fixed.first?.isUppercase == true
                guard wasSpace || isCapitalized else { return }
                NSLog("[Typro] punct pending: '\(word)' → '\(fixed)'")
                pending = (word, fixed, boundary)
                return
            }

            // Spell-check fix — async.
            let language = TyproSettings.shared.language
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                guard let s = self.suggester.suggest(for: word, language: language) else { return }
                let isCapitalized = s.suggestion.first?.isUppercase == true
                guard wasSpace || isCapitalized else { return }
                DispatchQueue.main.async {
                    NSLog("[Typro] spell pending: '\(s.typed)' → '\(s.suggestion)'")
                    self.pending = (s.typed, s.suggestion, boundary)
                }
            }
        }
    }

    private func applyFix(typed: String, correction: String, boundary: String) {
        // Special case: space-before-punct — typed is " ", correction is boundary, boundary is "".
        if typed == " " && boundary.isEmpty {
            NSLog("[Typro] applying space-before-punct fix")
            // Delete the space (1 char), retype the punctuation.
            let deleteCount = 1
            suppressCount = deleteCount * 2 + correction.unicodeScalars.count * 2
            KeyPoster.backspace(deleteCount)
            KeyPoster.type(correction)
            return
        }

        NSLog("[Typro] applying fix: '\(typed)' → '\(correction)'")
        // Delete: typed word + boundary char (1). Then retype correction + boundary.
        let deleteCount = typed.count + (boundary.isEmpty ? 0 : 1)
        let retyped = correction + boundary
        suppressCount = deleteCount * 2 + retyped.unicodeScalars.count * 2
        KeyPoster.backspace(deleteCount)
        KeyPoster.type(retyped)
    }
}
