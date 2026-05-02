import Foundation
import OSLog

/// Centralized OSLog `Logger`s. Use `.private` interpolation for token counts,
/// budget values, and any other numeric we don't want exposed in `Console.app`
/// to admins or other users on shared systems.
///
/// Pattern:
///     Log.limit.info("crossed — \(tokens, privacy: .private) / \(budget, privacy: .private)")
///     Log.parser.warning("skipped \(fileName, privacy: .public)")
enum Log {
    static let subsystem = "com.max.ClaudeHealth"

    static let lifecycle  = Logger(subsystem: subsystem, category: "lifecycle")
    static let data       = Logger(subsystem: subsystem, category: "data")
    static let parser     = Logger(subsystem: subsystem, category: "parser")
    static let cache      = Logger(subsystem: subsystem, category: "cache")
    static let limit      = Logger(subsystem: subsystem, category: "limit")
    static let confetti   = Logger(subsystem: subsystem, category: "confetti")
    static let appearance = Logger(subsystem: subsystem, category: "appearance")
    static let sharing    = Logger(subsystem: subsystem, category: "sharing")
    static let launch     = Logger(subsystem: subsystem, category: "launch-at-login")
    static let security   = Logger(subsystem: subsystem, category: "security")
}

extension String {
    /// Render any filesystem-derived (or otherwise untrusted) string safely for
    /// inclusion in a log line. Replaces the user's home-directory prefix with
    /// a literal `~` (so Console.app readers don't see the username), drops
    /// control bytes and non-printable ASCII, and truncates to 120 chars so an
    /// attacker who can plant a directory named
    /// `foo\n2026-05-01 [SECURITY] ALL OK\nbar` can't inject fake log lines.
    var logSafe: String {
        let scrubbed = Self.scrubHomePrefix(self)
        let cleaned = scrubbed.unicodeScalars.compactMap { s -> Character? in
            guard s.isASCII else { return nil }
            // Allow tab; drop other C0 controls and DEL.
            if s.value < 32 && s != "\t" { return nil }
            if s.value == 0x7f { return nil }
            return Character(s)
        }
        let out = String(cleaned)
        return out.count > 120 ? String(out.prefix(120)) + "…" : out
    }

    private static let homePathPrefix: String = {
        FileManager.default.homeDirectoryForCurrentUser.path
    }()

    private static func scrubHomePrefix(_ s: String) -> String {
        guard !homePathPrefix.isEmpty, s.contains(homePathPrefix) else { return s }
        return s.replacingOccurrences(of: homePathPrefix, with: "~")
    }
}

