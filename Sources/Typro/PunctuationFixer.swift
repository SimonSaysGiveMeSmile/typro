import Foundation

// Returns (corrected, deleteCount) where deleteCount is chars to erase before typing corrected+boundary.
// deleteCount includes the boundary char itself.
enum PunctuationFixer {

    // Patterns where semicolons/colons substitute for apostrophe: I;ll → I'll, I';;. → I'll
    private static let apostrophePattern = try! NSRegularExpression(pattern: "[;:]+")

    static func fix(word: String, boundary: String) -> String? {
        var result = word

        // Semicolon/colon used instead of apostrophe: I;ll → I'll, don;t → don't
        if result.contains(";") || result.contains(":") {
            let fixed = apostrophePattern.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "'"
            )
            if fixed != result { result = fixed }
        }

        return result == word ? nil : result
    }

    // Detects "space before punctuation" in the boundary stream.
    // Called when boundary is "," or "." and the last char of the preceding context was a space.
    // Returns the fix: delete the space + boundary, retype boundary only.
    static func isSpaceBeforePunct(_ boundary: String) -> Bool {
        return boundary == "," || boundary == "." || boundary == "!" || boundary == "?"
    }
}
