import Foundation

/// Stub — Foundation Models removed. All methods return nil immediately.
final class ContextualLM {
    static let shared = ContextualLM()
    var isAvailable: Bool { false }
    func predictNextWord(context: String, completion: @escaping (String?) -> Void) { completion(nil) }
    func rerank(candidates: [String], context: String, completion: @escaping (String?) -> Void) { completion(nil) }
}
