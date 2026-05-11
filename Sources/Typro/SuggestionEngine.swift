import AppKit

struct TypoSuggestion {
    let typed: String
    let suggestion: String
    /// Number of trailing characters in `typed` that differ from `suggestion`.
    /// For "mistika" → "mistake", common prefix is "mista", suffixLength = 2 ("ka").
    let wrongSuffixLength: Int
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

        return TypoSuggestion(typed: word, suggestion: top, wrongSuffixLength: suffixLen)
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
