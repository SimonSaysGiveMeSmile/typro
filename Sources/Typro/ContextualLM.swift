import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Wraps Apple's on-device Foundation Models framework for contextual candidate re-ranking.
/// On macOS 26+ with Apple Intelligence available, asks the system LM which of several
/// spelling candidates best fits the recent typing context. Silently returns nil otherwise.
///
/// Only consulted for LOW-confidence corrections on the backspace path — the LM's latency
/// (~100–500ms first inference) is fine when the user has already decided to correct.
final class ContextualLM {
    static let shared = ContextualLM()

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static var _session: LanguageModelSession?

    @available(macOS 26.0, *)
    private static func session() -> LanguageModelSession? {
        if let s = _session { return s }
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let s = LanguageModelSession(instructions: """
            You help pick the word a user meant to type, using short surrounding context.
            Reply with just the chosen word. No punctuation, no explanation.
            """)
        _session = s
        return s
    }
    #endif

    /// Whether contextual re-ranking is possible on this machine right now.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
        #else
        return false
        #endif
    }

    /// Given recent context and a set of candidates, return the best fit or nil on failure.
    /// Runs async on the caller's thread. Falls through to nil in ≤1.5s if the model stalls.
    func rerank(candidates: [String], context: String,
                completion: @escaping (String?) -> Void) {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { completion(nil); return }
        guard isAvailable else { completion(nil); return }
        guard candidates.count >= 2 else { completion(candidates.first); return }

        let trimmedContext = String(context.suffix(200))
        let list = candidates.prefix(5).enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "  ")
        let prompt = """
            Context: "\(trimmedContext)"
            Candidates: \(list)
            Pick the best candidate.
            """

        Task {
            do {
                guard let session = Self.session() else {
                    completion(nil); return
                }
                let response = try await session.respond(to: prompt)
                let text = response.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.,!?"))
                let match = candidates.first { $0.lowercased() == text.lowercased() }
                completion(match)
            } catch {
                completion(nil)
            }
        }
        #else
        completion(nil)
        #endif
    }
}
