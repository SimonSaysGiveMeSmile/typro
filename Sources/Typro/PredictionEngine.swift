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
              let first = completions.first else {
            store(cacheKey, nil)
            return nil
        }

        let firstLower = first.lowercased()
        let prefixLower = prefix.lowercased()
        guard firstLower.hasPrefix(prefixLower), first.count > prefix.count else {
            store(cacheKey, nil)
            return nil
        }

        // Skip if there are many competing completions — ambiguous.
        if completions.count > 6 {
            store(cacheKey, nil)
            return nil
        }

        // Drop the prefix the user already typed — match their case exactly.
        let remainder = String(first.dropFirst(prefix.count))
        store(cacheKey, remainder)
        return remainder
    }

    func clearCache() { cache.removeAll() }

    private func store(_ key: String, _ value: String?) {
        if cache.count >= cacheLimit { cache.removeAll() }
        cache[key] = value
    }
}
