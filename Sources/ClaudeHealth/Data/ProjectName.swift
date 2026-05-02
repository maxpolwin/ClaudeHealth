import Foundation

enum ProjectName {
    /// Convert raw project directory keys like "-Users-max-Development-TL-DR" into
    /// human-readable labels like "TL-DR".
    /// Worktrees: "...-Foo--claude-worktrees-bar" → "Foo (worktree: bar)".
    static func displayName(for key: String) -> String {
        var s = key
        // Strip the per-user prefix. Be permissive: any number of leading "-Users-…-Development-" forms.
        if let range = s.range(of: "-Development-") {
            s = String(s[range.upperBound...])
        } else if s.hasPrefix("-Users-") {
            // "-Users-max-foo" → "foo"
            let parts = s.split(separator: "-", omittingEmptySubsequences: false)
            if parts.count >= 4 {
                s = parts[3...].joined(separator: "-")
            }
        }
        // Worktree split
        if let r = s.range(of: "--claude-worktrees-") {
            let main = String(s[..<r.lowerBound])
            let worktree = String(s[r.upperBound...])
            return "\(main) (worktree: \(worktree))"
        }
        return s
    }
}
