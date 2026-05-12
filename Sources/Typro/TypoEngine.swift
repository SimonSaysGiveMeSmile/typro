import Foundation
import AppKit

final class TypoEngine {
    private let monitor = KeyMonitor()
    private let suggester = SuggestionEngine()

    private let stateQueue = DispatchQueue(label: "typro.state")
    private var buffer: String = ""

    private var pending: (typed: String, correction: String, boundary: String)?

    // Guard the space we just appended after an autofix. If the user hits backspace
    // within this window, their BS is likely racing the just-inserted space — swallow it.
    private var spaceGuardUntil: Date?
    private let spaceGuardWindow: TimeInterval = 0.35

    // Track rapid backspaces to promote to word-delete.
    private var backspaceHistory: [Date] = []
    private let rapidBackspaceThreshold = 2
    private let rapidBackspaceWindow: TimeInterval = 0.45

    // Last non-space punctuation boundary ("," "." "!" "?"), used to detect missing-space-after-punct.
    private var lastPunctBoundary: String?

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
        stateQueue.sync {
            buffer.removeAll(); pending = nil
            spaceGuardUntil = nil; backspaceHistory.removeAll()
            lastPunctBoundary = nil
        }
    }

    func settingsChanged() {
        if TyproSettings.shared.enabled { _ = monitor.start() } else { stop() }
    }

    private func handleSync(_ event: KeyEvent) -> Bool {
        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard TyproSettings.shared.shouldActivate(forBundleID: frontBundleID) else {
            buffer.removeAll(); pending = nil
            spaceGuardUntil = nil; backspaceHistory.removeAll()
            lastPunctBoundary = nil
            return false
        }

        if case .backspace = event.kind {
            return handleBackspace()
        }

        // Any non-backspace clears rapid-delete state.
        backspaceHistory.removeAll()
        pending = nil
        spaceGuardUntil = nil

        switch event.kind {
        case .character(let s):
            // Active apostrophe fix: ";" or ":" in a letter context becomes "'".
            if s == ";" || s == ":", !buffer.isEmpty, buffer.last?.isLetter == true {
                NSLog("[Typro] active apostrophe fix: '\(s)' → '")
                DispatchQueue.global(qos: .userInitiated).async { KeyPoster.type("'") }
                buffer.append("'")
                lastPunctBoundary = nil
                return true
            }

            if s.count == 1, s.first?.isLetter == true {
                // Missing space after punctuation: last boundary was "," "." "!" "?".
                // Insert a space before this letter.
                if let prev = lastPunctBoundary, prev != "" {
                    NSLog("[Typro] missing-space after '\(prev)' → inserting space")
                    let letter = s
                    DispatchQueue.global(qos: .userInitiated).async {
                        KeyPoster.type(" " + letter)
                    }
                    buffer = letter
                    lastPunctBoundary = nil
                    return true
                }
                buffer.append(s)
            } else {
                buffer.removeAll()
            }
            lastPunctBoundary = nil

        case .caretMove, .modifierCombo:
            buffer.removeAll()
            lastPunctBoundary = nil

        case .wordBoundary(let boundary):
            let word = buffer
            buffer.removeAll()

            // Track whether this boundary is punctuation that should be followed by a space.
            if boundary == "," || boundary == "." || boundary == "!" || boundary == "?" {
                lastPunctBoundary = boundary
            } else {
                lastPunctBoundary = nil
            }

            if word.isEmpty && PunctuationFixer.isSpaceBeforePunct(boundary) {
                pending = (" ", boundary, "")
                return false
            }

            guard word.count >= TyproSettings.shared.minWordLength else { return false }

            if let fixed = PunctuationFixer.fix(word: word, boundary: boundary) {
                autoApply(typed: word, correction: fixed, boundary: boundary)
                return false
            }

            scheduleSpellSuggest(word: word, boundary: boundary)

        case .backspace:
            break
        }
        return false
    }

    private func handleBackspace() -> Bool {
        // Any backspace invalidates missing-space-after-punct tracking.
        lastPunctBoundary = nil

        // 1. Recent space inserted by us? Swallow this BS so the space survives.
        if let until = spaceGuardUntil, Date() < until {
            NSLog("[Typro] space-guard: swallow BS")
            spaceGuardUntil = nil
            return true
        }

        // 2. A pending (low-confidence) fix waiting for confirmation?
        if let p = pending {
            pending = nil
            backspaceHistory.removeAll()
            applyFixAsync(typed: p.typed, correction: p.correction, boundary: p.boundary)
            return true
        }

        // 3. Buffer has a mid-word state — try to fix or delete the whole word.
        let word = buffer
        if word.count >= TyproSettings.shared.minWordLength {
            buffer.removeAll()
            backspaceHistory.removeAll()
            if let s = suggester.suggest(for: word, language: TyproSettings.shared.language) {
                applyFixAsync(typed: word, correction: s.suggestion, boundary: "")
            } else {
                deleteWholeWordAsync(word)
            }
            return true
        }

        // 4. No word fix available. Count rapid backspaces; after N in quick succession,
        //    promote to option+backspace (delete previous word). Otherwise pass through.
        let now = Date()
        backspaceHistory = backspaceHistory.filter { now.timeIntervalSince($0) < rapidBackspaceWindow }
        backspaceHistory.append(now)

        if backspaceHistory.count >= rapidBackspaceThreshold {
            backspaceHistory.removeAll()
            buffer.removeAll()
            NSLog("[Typro] rapid BS → delete previous word")
            DispatchQueue.global(qos: .userInitiated).async {
                KeyPoster.optionBackspace(1)
            }
            return true
        }

        // Clear one letter from buffer (mirrors the user's actual BS).
        if !buffer.isEmpty { buffer.removeLast() }
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

    /// Apply when the trailing boundary is already in the document (user just typed it).
    /// Delete word + boundary, retype correction + boundary.
    private func autoApply(typed: String, correction: String, boundary: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let deleteCount = typed.count + (boundary.isEmpty ? 0 : 1)
            let retyped = correction + boundary
            KeyPoster.backspace(deleteCount)
            KeyPoster.type(retyped)
            if boundary == " " {
                self.stateQueue.async { self.spaceGuardUntil = Date().addingTimeInterval(self.spaceGuardWindow) }
            }
        }
    }

    /// Apply when the user's backspace was swallowed. Doc state matches the word+boundary still being there.
    private func applyFixAsync(typed: String, correction: String, boundary: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            if typed == " " && boundary.isEmpty {
                // space-before-punct: delete trailing space + punct, retype punct.
                KeyPoster.backspace(2)
                KeyPoster.type(correction)
                return
            }
            let deleteCount = typed.count + (boundary.isEmpty ? 0 : 1)
            let retyped = correction + boundary
            KeyPoster.backspace(deleteCount)
            KeyPoster.type(retyped)
            if boundary == " " {
                self.stateQueue.async { self.spaceGuardUntil = Date().addingTimeInterval(self.spaceGuardWindow) }
            }
        }
    }

    private func deleteWholeWordAsync(_ word: String) {
        NSLog("[Typro] no suggestion, deleting whole word '\(word)'")
        DispatchQueue.global(qos: .userInitiated).async {
            KeyPoster.backspace(word.count)
        }
    }
}
