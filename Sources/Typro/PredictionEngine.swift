import AppKit

/// On-device word completion using NSSpellChecker.completions.
/// Purely offline; no network, no model download.
final class PredictionEngine {
    private let checker = NSSpellChecker.shared

    // Small in-process cache keyed by (prefix, language) so repeated same-prefix
    // keystrokes don't re-query the spell checker.
    private var cache: [String: String?] = [:]
    private let cacheLimit = 64

    /// Returns the remainder of the best single-word completion for `prefix`,
    /// or nil if we can't confidently complete. Result excludes the prefix itself.
    /// Example: prefix "predic", language "en" → "tion" (full word "prediction").
    func remainder(forPrefix prefix: String, language: String) -> String? {
        guard prefix.count >= 3 else { return nil }

        // Only alphabetic prefixes — skip numbers, symbols, mixed garbage.
        for scalar in prefix.unicodeScalars {
            if !CharacterSet.letters.contains(scalar) { return nil }
        }

        let cacheKey = "\(language)::\(prefix.lowercased())"
        if let cached = cache[cacheKey] { return cached }

        let range = NSRange(location: 0, length: (prefix as NSString).length)
        guard let completions = checker.completions(forPartialWordRange: range,
                                                     in: prefix,
                                                     language: language,
                                                     inSpellDocumentWithTag: 0),
              !completions.isEmpty else {
            store(cacheKey, nil)
            return nil
        }

        let prefixLower = prefix.lowercased()
        // Pick the shortest valid completion — avoids "predictably" beating "prediction".
        guard let best = completions
            .filter({ $0.lowercased().hasPrefix(prefixLower) && $0.count > prefix.count })
            .min(by: { $0.count < $1.count }) else {
            store(cacheKey, nil)
            return nil
        }

        let remainder = String(best.dropFirst(prefix.count))
        store(cacheKey, remainder)
        return remainder
    }

    func clearCache() { cache.removeAll() }

    private func store(_ key: String, _ value: String?) {
        if cache.count >= cacheLimit { cache.removeAll() }
        cache[key] = value
    }
}
