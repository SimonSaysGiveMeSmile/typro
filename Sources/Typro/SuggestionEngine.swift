import AppKit

struct TypoSuggestion {
    let typed: String
    let suggestion: String
    /// Number of trailing characters in `typed` that differ from `suggestion`.
    /// For "mistika" → "mistake", common prefix is "mista", suffixLength = 2 ("ka").
    let wrongSuffixLength: Int
    /// Rough confidence in [0, 1]. 1.0 = near-certain, 0.0 = unsure.
    let confidence: Double
    /// Up to ~5 alternate candidates from the spell checker (including `suggestion`),
    /// ordered by NSSpellChecker's preference. Used by contextual re-rank.
    let candidates: [String]
}

final class SuggestionEngine {
    private let checker = NSSpellChecker.shared

    func suggest(for word: String, language: String) -> TypoSuggestion? {
        guard word.count >= 2 else { return nil }
        if containsDigitOrSymbol(word) { return nil }

        let range = checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        guard range.location != NSNotFound, range.length > 0 else { return nil }

        guard let guesses = checker.guesses(forWordRange: NSRange(location: 0, length: (word as NSString).length),
                                            in: word,
                                            language: language,
                                            inSpellDocumentWithTag: 0),
              let top = guesses.first else { return nil }

        if top.caseInsensitiveCompare(word) == .orderedSame { return nil }

        let prefix = commonPrefixLength(word.lowercased(), top.lowercased())
        let suffixLen = word.count - prefix

        if suffixLen == 0 { return nil }

        let confidence = scoreConfidence(typed: word, suggestion: top, guesses: guesses, prefixLen: prefix)

        let candidates = Array(guesses.prefix(5))
        return TypoSuggestion(typed: word, suggestion: top, wrongSuffixLength: suffixLen, confidence: confidence, candidates: candidates)
    }

    private func scoreConfidence(typed: String, suggestion: String, guesses: [String], prefixLen: Int) -> Double {
        let dist = damerauLevenshtein(typed.lowercased(), suggestion.lowercased())
        let len = max(typed.count, suggestion.count)

        // Base score: closer edit distance = more confident, length-normalized.
        // dist 1 on a 5-char word ≈ 0.8; dist 2 ≈ 0.6.
        var score = 1.0 - (Double(dist) / Double(len))

        // Boost if typed and suggestion share the same first letter.
        if typed.first?.lowercased() == suggestion.first?.lowercased() { score += 0.1 }

        // Boost if there's a clear winner (only one guess, or big quality gap).
        if guesses.count == 1 { score += 0.1 }

        // Penalty if prefix is 0 (could be a wildly different word).
        if prefixLen == 0 { score -= 0.15 }

        // Penalty for very short words — too many plausible neighbors.
        if typed.count < 3 { score -= 0.15 }

        // Penalty for big length mismatches.
        let lenDiff = abs(typed.count - suggestion.count)
        if lenDiff >= 3 { score -= 0.15 }

        return min(max(score, 0.0), 1.0)
    }

    // Damerau-Levenshtein — counts transpositions as 1 (teh→the = 1 not 2).
    private func damerauLevenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let n = a.count, m = b.count
        if n == 0 { return m }; if m == 0 { return n }
        var prev = [Int](repeating: 0, count: m+1)
        var dp   = (0...m).map { $0 }
        for i in 1...n {
            var cur = [Int](repeating: 0, count: m+1)
            cur[0] = i
            for j in 1...m {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                cur[j] = min(cur[j-1]+1, dp[j]+1, dp[j-1]+cost)
                if i > 1 && j > 1 && a[i-1] == b[j-2] && a[i-2] == b[j-1] {
                    cur[j] = min(cur[j], prev[j-2]+cost)
                }
            }
            prev = dp; dp = cur
        }
        return dp[m]
    }

    private func commonPrefixLength(_ a: String, _ b: String) -> Int {
        var count = 0
        var i = a.startIndex, j = b.startIndex
        while i < a.endIndex, j < b.endIndex, a[i] == b[j] {
            count += 1
            i = a.index(after: i)
            j = b.index(after: j)
        }
        return count
    }

    private func containsDigitOrSymbol(_ s: String) -> Bool {
        for scalar in s.unicodeScalars {
            if CharacterSet.decimalDigits.contains(scalar) { return true }
            if CharacterSet.symbols.contains(scalar) { return true }
        }
        return false
    }
}
