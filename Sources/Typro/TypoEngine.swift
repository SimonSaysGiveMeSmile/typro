import Foundation
import AppKit

final class TypoEngine {
    private let monitor = KeyMonitor()
    private let suggester = SuggestionEngine()
    private let predictor = PredictionEngine()

    private let stateQueue = DispatchQueue(label: "typro.state")
    private var buffer: String = ""

    private var pending: (typed: String, correction: String, boundary: String)?

    // Active prediction: if non-nil, Tab will commit these remaining characters.
    private var predictionRemainder: String?

    // Track the previous character to detect double-space and i-alone fixes.
    private var lastChar: Character?

    // Guard the space we just appended after an autofix. If the user hits backspace
    // within this window, their BS is likely racing the just-inserted space — swallow it.
    private var spaceGuardUntil: Date?
    private let spaceGuardWindow: TimeInterval = 0.35

    // Track rapid backspaces to promote to word-delete.
    private var backspaceHistory: [Date] = []
    private let rapidBackspaceThreshold = 2
    private let rapidBackspaceWindow: TimeInterval = 0.45

    // Triple-Esc to clear the field.
    private var escHistory: [Date] = []
    private let tripleEscWindow: TimeInterval = 0.6

    // Last non-space punctuation boundary ("," "." "!" "?"), used to detect missing-space-after-punct.
    private var lastPunctBoundary: String?

    // True when the last boundary emitted was a sentence-ender followed by a space
    // (". ", "! ", "? "). Drives auto-capitalize of the next letter.
    private var pendingSentenceCap: Bool = false

    // Short rolling context fed to Foundation Models for contextual re-rank.
    // Only built when prediction is enabled; cheap ring-buffer cap.
    private var recentContext: String = ""
    private let recentContextCap = 240

    private let autoFixConfidenceThreshold: Double = 0.8
    private let contextRerankMinConfidence: Double = 0.35

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
            predictionRemainder = nil
            lastChar = nil
            pendingSentenceCap = false
            recentContext.removeAll()
            escHistory.removeAll()
            predictor.clearCache()
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
            predictionRemainder = nil; lastChar = nil
            return false
        }

        if case .escape = event.kind {
            let now = Date()
            escHistory = escHistory.filter { now.timeIntervalSince($0) < tripleEscWindow }
            escHistory.append(now)
            if escHistory.count >= 3 {
                escHistory.removeAll()
                buffer.removeAll(); pending = nil; predictionRemainder = nil
                lastChar = nil; lastPunctBoundary = nil; pendingSentenceCap = false
                NSLog("[Typro] triple-Esc → clear field")
                CorrectionLog.shared.record(.clearField, typed: "", correction: "", app: frontBundleID)
                DispatchQueue.global(qos: .userInitiated).async { KeyPoster.selectAllAndDelete() }
                return true
            }
            // First/second Esc: pass through (lets apps dismiss dialogs etc.) but reset word state.
            buffer.removeAll(); pending = nil; predictionRemainder = nil
            lastChar = nil; lastPunctBoundary = nil; pendingSentenceCap = false
            return false
        }

        if case .backspace = event.kind {
            predictionRemainder = nil
            return handleBackspace(app: frontBundleID)
        }

        if case .tab = event.kind {
            if let remainder = predictionRemainder, !remainder.isEmpty {
                let committed = buffer + remainder
                NSLog("[Typro] prediction commit via Tab: '\(buffer)' → '\(committed)'")
                CorrectionLog.shared.record(.prediction, typed: buffer, correction: committed, app: frontBundleID)
                predictionRemainder = nil
                let copy = remainder
                DispatchQueue.global(qos: .userInitiated).async { KeyPoster.type(copy) }
                buffer.append(copy)
                lastChar = copy.last
                return true
            }
            // No active prediction — let Tab do its normal thing, but clear word state.
            buffer.removeAll(); lastChar = nil
            lastPunctBoundary = nil
            return false
        }

        // Any non-backspace, non-tab clears rapid-delete state.
        backspaceHistory.removeAll()
        pending = nil
        spaceGuardUntil = nil

        switch event.kind {
        case .character(let s):
            // Active apostrophe fix: ";" or ":" in a letter context becomes "'".
            // Also fires when buffer is empty but the last typed char was a letter (e.g. "said;hello").
            if s == ";" || s == ":",
               buffer.last?.isLetter == true || (buffer.isEmpty && lastChar?.isLetter == true) {
                NSLog("[Typro] active apostrophe fix: '\(s)' → '")
                CorrectionLog.shared.record(.activeApostrophe, typed: s, correction: "'", app: frontBundleID)
                DispatchQueue.global(qos: .userInitiated).async { KeyPoster.type("'") }
                buffer.append("'")
                lastPunctBoundary = nil
                lastChar = "'"
                predictionRemainder = nil
                return true
            }

            if s.count == 1, s.first?.isLetter == true {
                if let prev = lastPunctBoundary, prev != "" {
                    NSLog("[Typro] missing-space after '\(prev)' → inserting space")
                    CorrectionLog.shared.record(.missingSpaceAfterPunct, typed: prev + s, correction: prev + " " + s, app: frontBundleID)
                    let letter = s
                    DispatchQueue.global(qos: .userInitiated).async {
                        KeyPoster.type(" " + letter)
                    }
                    buffer = letter
                    lastPunctBoundary = nil
                    lastChar = letter.last
                    predictionRemainder = nil
                    pendingSentenceCap = false
                    appendContext(" " + letter)
                    return true
                }

                // Auto-capitalize first letter after ". " / "! " / "? ".
                if pendingSentenceCap, TyproSettings.shared.sentenceCapEnabled,
                   let ch = s.first, ch.isLowercase {
                    let upper = String(ch).uppercased()
                    NSLog("[Typro] sentence cap: '\(s)' → '\(upper)'")
                    CorrectionLog.shared.record(.sentenceCap, typed: s, correction: upper, app: frontBundleID)
                    DispatchQueue.global(qos: .userInitiated).async {
                        KeyPoster.type(upper)
                    }
                    buffer.append(upper)
                    lastChar = upper.last
                    pendingSentenceCap = false
                    appendContext(upper)
                    return true
                }

                buffer.append(s)
                lastChar = s.last
                pendingSentenceCap = false
                appendContext(s)
                schedulePrediction(app: frontBundleID)
            } else {
                buffer.removeAll()
                predictionRemainder = nil
                lastChar = s.last
                pendingSentenceCap = false
                appendContext(s)
            }
            lastPunctBoundary = nil

        case .caretMove, .modifierCombo, .escape:
            buffer.removeAll()
            lastPunctBoundary = nil
            predictionRemainder = nil
            lastChar = nil

        case .tab:
            break

        case .wordBoundary(let boundary):
            let word = buffer
            buffer.removeAll()
            predictionRemainder = nil
            if !word.isEmpty { appendContext(word) }

            // Double space collapse: user pressed space twice.
            if boundary == " " && lastChar == " " {
                NSLog("[Typro] double space → collapsing")
                CorrectionLog.shared.record(.doubleSpace, typed: "  ", correction: " ", app: frontBundleID)
                DispatchQueue.global(qos: .userInitiated).async { KeyPoster.backspace(1) }
                lastChar = " "
                lastPunctBoundary = nil
                return true
            }

            // Capital-I fix: lone lowercase "i" followed by space/punct boundary → "I".
            if TyproSettings.shared.capitalizeI,
               word == "i",
               boundary == " " || boundary == "." || boundary == "," || boundary == "!" || boundary == "?" {
                NSLog("[Typro] capital I fix: 'i' → 'I'")
                CorrectionLog.shared.record(.capitalI, typed: "i" + boundary, correction: "I" + boundary, boundary: boundary, app: frontBundleID)
                autoApply(typed: "i", correction: "I", boundary: boundary)
                lastChar = boundary.last
                if boundary == "," || boundary == "." || boundary == "!" || boundary == "?" {
                    lastPunctBoundary = boundary
                } else {
                    lastPunctBoundary = nil
                }
                return false
            }

            if boundary == "," || boundary == "." || boundary == "!" || boundary == "?" {
                lastPunctBoundary = boundary
            } else {
                lastPunctBoundary = nil
            }

            // After ". ", "! ", or "? " a new sentence begins — arm sentence cap.
            if boundary == " ",
               let prev = lastChar,
               prev == "." || prev == "!" || prev == "?" {
                pendingSentenceCap = true
            } else if boundary != "." && boundary != "!" && boundary != "?" {
                pendingSentenceCap = false
            }

            lastChar = boundary.last
            appendContext(boundary)

            if word.isEmpty && PunctuationFixer.isSpaceBeforePunct(boundary) {
                pending = (" ", boundary, "")
                return false
            }

            // Punctuation fix (apostrophe, etc.) — apply even for short words.
            if let fixed = PunctuationFixer.fix(word: word, boundary: boundary) {
                CorrectionLog.shared.record(.punctuation, typed: word, correction: fixed, boundary: boundary, app: frontBundleID)
                autoApply(typed: word, correction: fixed, boundary: boundary)
                return false
            }

            if boundary == " " {
                scheduleNextWordPrediction(context: recentContext)
            }

            guard word.count >= TyproSettings.shared.minWordLength else { return false }

            scheduleSpellSuggest(word: word, boundary: boundary, app: frontBundleID)

        case .backspace:
            break
        }
        return false
    }

    private func handleBackspace(app: String?) -> Bool {
        lastPunctBoundary = nil

        if let until = spaceGuardUntil, Date() < until {
            NSLog("[Typro] space-guard: swallow BS")
            spaceGuardUntil = nil
            return true
        }

        if let p = pending {
            pending = nil
            backspaceHistory.removeAll()
            if p.typed == " " && p.boundary.isEmpty {
                CorrectionLog.shared.record(.spaceBeforePunct, typed: " " + p.correction, correction: p.correction, app: app)
            } else {
                CorrectionLog.shared.record(.applyFromBackspace, typed: p.typed, correction: p.correction, boundary: p.boundary, app: app)
            }
            applyFixAsync(typed: p.typed, correction: p.correction, boundary: p.boundary)
            return true
        }

        let word = buffer
        if word.count >= TyproSettings.shared.minWordLength {
            buffer.removeAll()
            backspaceHistory.removeAll()
            if let s = suggester.suggest(for: word, language: TyproSettings.shared.language) {
                CorrectionLog.shared.record(.applyFromBackspace, typed: word, correction: s.suggestion, confidence: s.confidence, app: app)
                applyFixAsync(typed: word, correction: s.suggestion, boundary: "")
            } else {
                CorrectionLog.shared.record(.deleteWholeWord, typed: word, correction: "", app: app)
                deleteWholeWordAsync(word)
            }
            return true
        }

        let now = Date()
        backspaceHistory = backspaceHistory.filter { now.timeIntervalSince($0) < rapidBackspaceWindow }
        backspaceHistory.append(now)

        if backspaceHistory.count >= rapidBackspaceThreshold {
            backspaceHistory.removeAll()
            buffer.removeAll()
            NSLog("[Typro] rapid BS → delete previous word")
            CorrectionLog.shared.record(.rapidWordDelete, typed: "", correction: "", app: app)
            DispatchQueue.global(qos: .userInitiated).async {
                KeyPoster.optionBackspace(1)
            }
            return true
        }

        if !buffer.isEmpty { buffer.removeLast() }
        return false
    }

    private func scheduleSpellSuggest(word: String, boundary: String, app: String?) {
        let language = TyproSettings.shared.language
        let context = recentContext
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let s = self.suggester.suggest(for: word, language: language) else { return }
            if s.confidence >= self.autoFixConfidenceThreshold {
                NSLog("[Typro] auto-apply (conf \(String(format: "%.2f", s.confidence))): '\(s.typed)' → '\(s.suggestion)'")
                CorrectionLog.shared.record(.autoApply, typed: s.typed, correction: s.suggestion, boundary: boundary, confidence: s.confidence, app: app)
                self.autoApply(typed: s.typed, correction: s.suggestion, boundary: boundary)
            } else {
                self.stageSuggestion(s, boundary: boundary, app: app)
                self.maybeContextRerank(word: word, candidates: s.candidates,
                                        boundary: boundary, context: context, app: app)
            }
        }
    }

    private func stageSuggestion(_ s: TypoSuggestion, boundary: String, app: String?) {
        stateQueue.async {
            NSLog("[Typro] pending (conf \(String(format: "%.2f", s.confidence))): '\(s.typed)' → '\(s.suggestion)'")
            CorrectionLog.shared.record(.pending, typed: s.typed, correction: s.suggestion, boundary: boundary, confidence: s.confidence, app: app)
            self.pending = (s.typed, s.suggestion, boundary)
        }
    }

    private func maybeContextRerank(word: String, candidates: [String], boundary: String,
                                    context: String, app: String?) {
        guard TyproSettings.shared.contextRerank,
              ContextualLM.shared.isAvailable,
              candidates.count >= 2 else { return }
        ContextualLM.shared.rerank(candidates: candidates, context: context) { [weak self] choice in
            guard let self, let pick = choice else { return }
            self.stateQueue.async {
                // Only swap if the staged pending is still this word and the LM picked
                // something different from the spell-checker's top suggestion.
                guard let p = self.pending, p.typed == word,
                      p.correction.lowercased() != pick.lowercased() else { return }
                NSLog("[Typro] context rerank: '\(p.correction)' → '\(pick)'")
                CorrectionLog.shared.record(.contextRerank, typed: word, correction: pick, boundary: boundary, app: app)
                self.pending = (word, pick, boundary)
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

    private func schedulePrediction(app: String?) {
        guard TyproSettings.shared.predictionsEnabled else {
            predictionRemainder = nil
            return
        }
        let snapshot = buffer
        let language = TyproSettings.shared.language
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let remainder = self.predictor.remainder(forPrefix: snapshot, language: language)
            self.stateQueue.async {
                guard self.buffer == snapshot else { return }
                self.predictionRemainder = remainder
            }
        }
    }

    // After a word boundary + space, ask FM to predict the next word.
    // Stored as predictionRemainder so Tab commits it (typed as a full new word).
    private func scheduleNextWordPrediction(context: String) {
        guard TyproSettings.shared.predictionsEnabled,
              TyproSettings.shared.contextRerank,
              ContextualLM.shared.isAvailable else { return }
        ContextualLM.shared.predictNextWord(context: context) { [weak self] word in
            guard let self, let word else { return }
            self.stateQueue.async {
                // Only set if the user hasn't started typing a new word yet.
                guard self.buffer.isEmpty else { return }
                self.predictionRemainder = word
            }
        }
    }

    private func appendContext(_ s: String) {
        recentContext.append(s)
        if recentContext.count > recentContextCap {
            recentContext.removeFirst(recentContext.count - recentContextCap)
        }
    }
}
