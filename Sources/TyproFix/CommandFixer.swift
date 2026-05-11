import Foundation
import AppKit

// MARK: - Levenshtein

// Damerau-Levenshtein: counts transpositions as 1 (gti→git = 1, not 2)
private func editDistance(_ a: String, _ b: String) -> Int {
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

// MARK: - Command fixer (scans PATH)

enum CommandFixer {
    private static var _cache: [String]?

    private static var allCommands: [String] {
        if let c = _cache { return c }
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        var cmds = Set<String>()
        for dir in pathDirs {
            let url = URL(fileURLWithPath: dir)
            if let items = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                for item in items {
                    let full = url.appendingPathComponent(item).path
                    if FileManager.default.isExecutableFile(atPath: full) { cmds.insert(item) }
                }
            }
        }
        let sorted = Array(cmds).sorted()
        _cache = sorted
        return sorted
    }

    static func fix(_ token: String) -> String? {
        guard !token.isEmpty, let firstChar = token.first else { return nil }
        var best: String?
        var bestDist = 3 // exclusive upper bound
        for cmd in allCommands {
            // first character must match — typos rarely change the leading letter
            guard cmd.first == firstChar else { continue }
            let d = editDistance(token, cmd)
            if d < bestDist { bestDist = d; best = cmd }
        }
        return best
    }
}

// MARK: - Subcommand fixer

enum SubcommandFixer {
    private static let subcommands: [String] = [
        // git
        "commit", "status", "push", "pull", "fetch", "checkout", "branch",
        "merge", "rebase", "reset", "stash", "diff", "log", "clone", "init",
        "add", "remove", "restore", "switch", "tag", "cherry-pick", "bisect",
        // docker
        "build", "run", "exec", "stop", "start", "restart", "rm", "rmi",
        "ps", "images", "pull", "push", "login", "logout", "inspect", "logs",
        "compose", "network", "volume", "container",
        // npm/yarn/pnpm
        "install", "uninstall", "update", "publish", "test", "start", "build",
        "run", "audit", "outdated", "link", "pack",
        // swift
        "build", "test", "run", "package", "clean",
        // kubectl
        "get", "apply", "delete", "describe", "create", "edit", "scale",
        "rollout", "expose", "port-forward", "exec", "logs", "config",
    ]

    static func fix(_ token: String) -> String? {
        guard !token.isEmpty, let firstChar = token.first else { return nil }
        var best: String?
        var bestDist = 3
        for sub in subcommands {
            guard sub.first == firstChar else { continue }
            let d = editDistance(token, sub)
            if d < bestDist { bestDist = d; best = sub }
        }
        return best
    }
}

// MARK: - Flag fixer

enum FlagFixer {
    // Common long flags across popular tools
    private static let knownFlags: [String] = [
        "--recursive", "--verbose", "--force", "--help", "--version",
        "--output", "--input", "--config", "--dry-run", "--all",
        "--global", "--local", "--remote", "--branch", "--message",
        "--author", "--date", "--format", "--pretty", "--oneline",
        "--staged", "--cached", "--patch", "--interactive", "--quiet",
        "--no-verify", "--amend", "--rebase", "--merge", "--squash",
        "--follow", "--name-only", "--stat", "--diff", "--list",
        "--delete", "--set-upstream", "--track", "--tags", "--prune",
        "--depth", "--single-branch", "--no-ff", "--ff-only",
        "--porcelain", "--short", "--long", "--color", "--no-color",
    ]

    static func fix(_ token: String) -> String? {
        guard token.hasPrefix("--"), token.count > 3 else { return nil }
        var best: String?
        var bestDist = 3
        for flag in knownFlags {
            let d = editDistance(token, flag)
            if d < bestDist { bestDist = d; best = flag }
        }
        return best
    }
}

// MARK: - Path fixer

enum PathFixer {
    static func fix(_ token: String) -> String? {
        let url = URL(fileURLWithPath: token)
        if FileManager.default.fileExists(atPath: token) { return nil } // already valid

        let dir = url.deletingLastPathComponent().path
        let name = url.lastPathComponent
        guard !name.isEmpty,
              let items = try? FileManager.default.contentsOfDirectory(atPath: dir.isEmpty ? "." : dir)
        else { return nil }

        var best: String?
        var bestDist = 3
        for item in items {
            let d = editDistance(name.lowercased(), item.lowercased())
            if d < bestDist { bestDist = d; best = item }
        }
        guard let match = best else { return nil }
        let base = dir.isEmpty || dir == "." ? "" : dir + "/"
        return base + match
    }
}

// MARK: - Prose fixer (NSSpellChecker)

enum ProseFixer {
    private static let checker = NSSpellChecker.shared

    static func fix(_ word: String, language: String = "en") -> String? {
        guard word.count >= 3 else { return nil }
        let range = checker.checkSpelling(of: word, startingAt: 0, language: language,
                                          wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        guard range.location != NSNotFound else { return nil }
        guard let guesses = checker.guesses(
            forWordRange: NSRange(location: 0, length: (word as NSString).length),
            in: word, language: language, inSpellDocumentWithTag: 0),
              let top = guesses.first,
              top.caseInsensitiveCompare(word) != .orderedSame
        else { return nil }
        return top
    }
}
