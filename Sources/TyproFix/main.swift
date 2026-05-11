import Foundation

// Reconstruct the full command line from argv (skip argv[0])
let args = CommandLine.arguments.dropFirst()
guard !args.isEmpty else {
    print("")
    exit(0)
}

// Tokenize preserving quoted strings as single tokens
func tokenize(_ input: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var inQuote: Character? = nil
    for ch in input {
        if let q = inQuote {
            current.append(ch)
            if ch == q { inQuote = nil; tokens.append(current); current = "" }
        } else if ch == "\"" || ch == "'" {
            if !current.isEmpty { tokens.append(current); current = "" }
            current.append(ch); inQuote = ch
        } else if ch == " " {
            if !current.isEmpty { tokens.append(current); current = "" }
        } else {
            current.append(ch)
        }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}

let input = args.joined(separator: " ")
let tokens = tokenize(input)

var fixed: [String] = []
for (i, token) in tokens.enumerated() {
    // Skip quoted strings and flags that are short (-x)
    if token.hasPrefix("\"") || token.hasPrefix("'") {
        // Fix prose inside quotes
        let inner = String(token.dropFirst().dropLast())
        let words = inner.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let fixedWords = words.map { w -> String in ProseFixer.fix(w) ?? w }
        let q = String(token.first!)
        fixed.append(q + fixedWords.joined(separator: " ") + q)
    } else if i == 0 {
        fixed.append(CommandFixer.fix(token) ?? token)
    } else if i == 1 && !token.hasPrefix("-") && !token.contains("/") {
        fixed.append(SubcommandFixer.fix(token) ?? ProseFixer.fix(token) ?? token)
    } else if token.hasPrefix("--") {
        fixed.append(FlagFixer.fix(token) ?? token)
    } else if token.contains("/") || token.hasPrefix(".") {
        fixed.append(PathFixer.fix(token) ?? token)
    } else if token.hasPrefix("-") {
        fixed.append(token)
    } else {
        fixed.append(ProseFixer.fix(token) ?? token)
    }
}

print(fixed.joined(separator: " "))
