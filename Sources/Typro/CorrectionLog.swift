import Foundation

/// JSONL correction log at ~/Library/Logs/Typro/corrections.log.
/// Append-only; one line per correction. Safe to call from any thread.
final class CorrectionLog {
    static let shared = CorrectionLog()

    enum Kind: String {
        case autoApply = "auto_apply"          // high-confidence fix applied at word boundary
        case pending = "pending"               // low-confidence suggestion staged
        case applyFromBackspace = "bs_apply"   // pending fix triggered by backspace
        case deleteWholeWord = "delete_word"   // no suggestion, whole word erased
        case rapidWordDelete = "rapid_word"    // 2 backspaces → option+delete
        case punctuation = "punct"             // PunctuationFixer edit
        case spaceBeforePunct = "space_punct"  // " ," → ","
        case missingSpaceAfterPunct = "missing_space"
        case activeApostrophe = "apostrophe"   // ; or : converted to '
        case doubleSpace = "double_space"      // "a  b" → "a b"
        case capitalI = "capital_i"            // lone "i " → "I "
        case prediction = "prediction"         // Tab-completed a word
        case sentenceCap = "sentence_cap"      // ". a" → ". A"
        case contextRerank = "ctx_rerank"      // Foundation Models picked a candidate
        case clearField = "clear_field"        // triple-Esc → select-all + delete
    }

    private let queue = DispatchQueue(label: "typro.correctionlog", qos: .utility)
    private let fileURL: URL
    private let iso = ISO8601DateFormatter()

    private init() {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Typro", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.fileURL = logsDir.appendingPathComponent("corrections.log")
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    var fileURLForDisplay: URL { fileURL }

    func record(_ kind: Kind, typed: String, correction: String,
                boundary: String = "", confidence: Double? = nil, app: String? = nil) {
        let entry: [String: Any?] = [
            "t": iso.string(from: Date()),
            "kind": kind.rawValue,
            "typed": typed,
            "correction": correction,
            "boundary": boundary.isEmpty ? nil : boundary,
            "confidence": confidence,
            "app": app
        ]
        let cleaned = entry.compactMapValues { $0 }
        queue.async { [fileURL] in
            guard let data = try? JSONSerialization.data(withJSONObject: cleaned,
                                                        options: [.withoutEscapingSlashes])
            else { return }
            var line = data
            line.append(0x0A) // newline
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? line.write(to: fileURL, options: [.atomic])
            }
        }
    }
}
