import Foundation
import AppKit

final class TypoEngine {
    private let monitor = KeyMonitor()
    private let suggester = SuggestionEngine()
    private let predictor = PredictionEngine()

    private let stateQueue = DispatchQueue(label: "typro.state")
    private let spellQueue = DispatchQueue(label: "typro.spell", qos: .userInitiated)
    private var buffer: String = ""
    private var pending: (typed: String, correction: String, boundary: String)?
    private var lastChar: Character?

    private var spaceGuardUntil: Date?
    private let spaceGuardWindow: TimeInterval = 0.35

    private var backspaceHistory: [Date] = []
    private let rapidBackspaceThreshold = 2
    private let rapidBackspaceWindow: TimeInterval = 0.45

    private var escHistory: [Date] = []
    private let tripleEscWindow: TimeInterval = 0.6

    private var lastPunctBoundary: String?
    private var pendingSentenceCap: Bool = false

    private var suppressedWords: [String: Date] = [:]
    private var recentlyFixed: [String: Date] = [:]
    // Incremented on every word boundary and reset; async fixes abort if stale.
    private var fixGeneration: Int = 0

    private static let shortWordCompletions: [String: String] = [
        "i": "is", "s": "so", "a": "as", "o": "of",
        "b": "be", "w": "we", "h": "he", "t": "to",
        "n": "no", "d": "do",
    ]

    private let autoFixConfidenceThreshold: Double = 0.65

    func start() {
        monitor.shouldSwallow = { [weak self] event in
            guard let self else { return false }
            return self.stateQueue.sync { self.handleSync(event) }
        }
        guard monitor.start() else {
            NSLog("[Typro] Failed to create event tap.")
            return
        }
        NSLog("[Typro] Key monitor started.")
    }

    func stop() {
        monitor.stop()
        stateQueue.sync { resetState() }
    }

    func settingsChanged() {
        if TyproSettings.shared.enabled { _ = monitor.start() } else { stop() }
    }

    private func resetState() {
        buffer.removeAll(); pending = nil
        spaceGuardUntil = nil; backspaceHistory.removeAll(); escHistory.removeAll()
        lastPunctBoundary = nil; lastChar = nil; pendingSentenceCap = false
        suppressedWords.removeAll(); recentlyFixed.removeAll(); fixGeneration += 1
        predictor.clearCache()
    }

    private func handleSync(_ event: KeyEvent) -> Bool {
        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard TyproSettings.shared.shouldActivate(forBundleID: frontBundleID) else {
            resetState(); return false
        }

        if case .escape = event.kind {
            let now = Date()
            escHistory = escHistory.filter { now.timeIntervalSince($0) < tripleEscWindow }
            escHistory.append(now)
            if escHistory.count >= 3 {
                escHistory.removeAll()
                buffer.removeAll(); pending = nil
                lastChar = nil; lastPunctBoundary = nil; pendingSentenceCap = false
                NSLog("[Typro] triple-Esc → clear field")
                CorrectionLog.shared.record(.clearField, typed: "", correction: "", app: frontBundleID)
                DispatchQueue.global(qos: .userInitiated).async { KeyPoster.selectAllAndDelete() }
                return true
            }
            buffer.removeAll(); pending = nil
            lastChar = nil; lastPunctBoundary = nil; pendingSentenceCap = false
            return false
        }

        if case .backspace = event.kind {
            return handleBackspace(app: frontBundleID)
        }

        if case .tab = event.kind {
            guard TyproSettings.shared.predictionsEnabled, !buffer.isEmpty else {
                buffer.removeAll(); lastChar = nil; lastPunctBoundary = nil
                return false
            }
            let prefix = buffer
            let language = TyproSettings.shared.language
            let gen = fixGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let remainder = self.predictor.remainder(forPrefix: prefix, language: language),
                      !remainder.isEmpty else { return }
                self.stateQueue.async {
                    guard self.fixGeneration == gen, self.buffer == prefix else { return }
                    self.buffer.append(remainder)
                    self.lastChar = remainder.last
                }
                NSLog("[Typro] Tab complete: '\(prefix)' → '\(prefix + remainder)'")
                CorrectionLog.shared.record(.prediction, typed: prefix, correction: prefix + remainder, app: frontBundleID)
                KeyPoster.type(remainder)
            }
            return true
        }

        backspaceHistory.removeAll()
        pending = nil
        spaceGuardUntil = nil

        switch event.kind {
        case .character(let s):
            if s.count == 1, s.first?.isLetter == true {
                if let prev = lastPunctBoundary, prev != "" {
                    NSLog("[Typro] missing-space after '\(prev)'")
                    CorrectionLog.shared.record(.missingSpaceAfterPunct, typed: prev + s, correction: prev + " " + s, app: frontBundleID)
                    let letter = s
                    DispatchQueue.global(qos: .userInitiated).async { KeyPoster.type(" " + letter) }
                    buffer = letter; lastPunctBoundary = nil; lastChar = letter.last
                    pendingSentenceCap = false
                    return true
                }

                if pendingSentenceCap, TyproSettings.shared.sentenceCapEnabled,
                   let ch = s.first, ch.isLowercase {
                    let upper = String(ch).uppercased()
                    NSLog("[Typro] sentence cap: '\(s)' → '\(upper)'")
                    CorrectionLog.shared.record(.sentenceCap, typed: s, correction: upper, app: frontBundleID)
                    DispatchQueue.global(qos: .userInitiated).async { KeyPoster.type(upper) }
                    buffer.append(upper); lastChar = upper.last; pendingSentenceCap = false
                    return true
                }

                buffer.append(s); lastChar = s.last; pendingSentenceCap = false
            } else {
                buffer.removeAll(); lastChar = s.last; pendingSentenceCap = false
            }
            lastPunctBoundary = nil

        case .caretMove, .modifierCombo, .escape:
            buffer.removeAll(); lastPunctBoundary = nil; lastChar = nil

        case .tab:
            break

        case .wordBoundary(let boundary):
            let word = buffer
            buffer.removeAll()
            fixGeneration += 1
            let gen = fixGeneration

            if TyproSettings.shared.capitalizeI, word == "i",
               boundary == " " || boundary == "." || boundary == "," || boundary == "!" || boundary == "?" {
                NSLog("[Typro] capital I fix")
                CorrectionLog.shared.record(.capitalI, typed: "i" + boundary, correction: "I" + boundary, boundary: boundary, app: frontBundleID)
                postFix(typed: "i", correction: "I", boundary: boundary)
                lastChar = boundary.last
                lastPunctBoundary = (boundary == "," || boundary == "!" || boundary == "?") ? boundary : nil
                return false
            }

            lastPunctBoundary = (boundary == "," || boundary == "!" || boundary == "?") ? boundary : nil

            if boundary == " ", let prev = lastChar, prev == "." || prev == "!" || prev == "?" {
                pendingSentenceCap = true
            } else if boundary != "." && boundary != "!" && boundary != "?" {
                pendingSentenceCap = false
            }

            lastChar = boundary.last

            if word.isEmpty && PunctuationFixer.isSpaceBeforePunct(boundary) {
                pending = (" ", boundary, ""); return false
            }

            if let fixed = PunctuationFixer.fix(word: word, boundary: boundary) {
                CorrectionLog.shared.record(.punctuation, typed: word, correction: fixed, boundary: boundary, app: frontBundleID)
                postFix(typed: word, correction: fixed, boundary: boundary)
                return false
            }

            guard word.count >= TyproSettings.shared.minWordLength else { return false }
            scheduleSpellSuggest(word: word, boundary: boundary, gen: gen, app: frontBundleID)

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
            pending = nil; backspaceHistory.removeAll()
            if p.typed == " " && p.boundary.isEmpty {
                CorrectionLog.shared.record(.spaceBeforePunct, typed: " " + p.correction, correction: p.correction, app: app)
            } else {
                CorrectionLog.shared.record(.applyFromBackspace, typed: p.typed, correction: p.correction, boundary: p.boundary, app: app)
            }
            postFix(typed: p.typed, correction: p.correction, boundary: p.boundary)
            return true
        }

        let word = buffer
        if word.count == 1, let completion = TypoEngine.shortWordCompletions[word.lowercased()] {
            buffer.removeAll(); backspaceHistory.removeAll()
            CorrectionLog.shared.record(.applyFromBackspace, typed: word, correction: completion, app: app)
            postFix(typed: word, correction: completion, boundary: "")
            return true
        }

        if word.count >= TyproSettings.shared.minWordLength {
            buffer.removeAll(); backspaceHistory.removeAll()
            if let s = suggester.suggest(for: word, language: TyproSettings.shared.language) {
                CorrectionLog.shared.record(.applyFromBackspace, typed: word, correction: s.suggestion, confidence: s.confidence, app: app)
                postFix(typed: word, correction: s.suggestion, boundary: "")
            } else {
                CorrectionLog.shared.record(.deleteWholeWord, typed: word, correction: "", app: app)
                NSLog("[Typro] no suggestion, deleting '\(word)'")
                DispatchQueue.global(qos: .userInitiated).async { KeyPoster.backspace(word.count) }
            }
            return true
        }

        let now = Date()
        backspaceHistory = backspaceHistory.filter { now.timeIntervalSince($0) < rapidBackspaceWindow }
        backspaceHistory.append(now)

        if backspaceHistory.count >= rapidBackspaceThreshold {
            backspaceHistory.removeAll(); buffer.removeAll()
            NSLog("[Typro] rapid BS → delete previous word")
            CorrectionLog.shared.record(.rapidWordDelete, typed: "", correction: "", app: app)
            DispatchQueue.global(qos: .userInitiated).async { KeyPoster.optionBackspace(1) }
            return true
        }

        if !buffer.isEmpty { buffer.removeLast() }
        return false
    }

    // Single entry point for posting a fix — backspace the wrong chars, type the correction.
    private func postFix(typed: String, correction: String, boundary: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            if typed == " " && boundary.isEmpty {
                KeyPoster.backspace(2); KeyPoster.type(correction); return
            }
            KeyPoster.backspace(typed.count + (boundary.isEmpty ? 0 : 1))
            KeyPoster.type(correction + boundary)
            if boundary == " " {
                self.stateQueue.async { self.spaceGuardUntil = Date().addingTimeInterval(self.spaceGuardWindow) }
            }
        }
    }

    private func isSuppressed(_ word: String) -> Bool {
        guard let until = suppressedWords[word] else { return false }
        if Date() < until { return true }
        suppressedWords.removeValue(forKey: word); return false
    }

    private func recordFix(_ word: String) {
        let now = Date()
        if let last = recentlyFixed[word], now.timeIntervalSince(last) < 5.0 {
            suppressedWords[word] = now.addingTimeInterval(2.0)
            NSLog("[Typro] suppressing '\(word)' for 2s")
        }
        recentlyFixed[word] = now
    }

    private func scheduleSpellSuggest(word: String, boundary: String, gen: Int, app: String?) {
        guard !isSuppressed(word) else { return }
        let language = TyproSettings.shared.language
        // NSSpellChecker must run on main thread.
        spellQueue.async { [weak self] in
            guard let self else { return }
            guard let s = self.suggester.suggest(for: word, language: language) else { return }
            self.stateQueue.async {
                // Abort if the user has already typed another word since this fix was scheduled.
                guard self.fixGeneration == gen else { return }
                if s.confidence >= self.autoFixConfidenceThreshold {
                    NSLog("[Typro] auto-apply (conf \(String(format: "%.2f", s.confidence))): '\(s.typed)' → '\(s.suggestion)'")
                    CorrectionLog.shared.record(.autoApply, typed: s.typed, correction: s.suggestion, boundary: boundary, confidence: s.confidence, app: app)
                    self.recordFix(word)
                    self.postFix(typed: s.typed, correction: s.suggestion, boundary: boundary)
                } else {
                    NSLog("[Typro] pending (conf \(String(format: "%.2f", s.confidence))): '\(s.typed)' → '\(s.suggestion)'")
                    CorrectionLog.shared.record(.pending, typed: s.typed, correction: s.suggestion, boundary: boundary, confidence: s.confidence, app: app)
                    self.pending = (s.typed, s.suggestion, boundary)
                }
            }
        }
    }
}
