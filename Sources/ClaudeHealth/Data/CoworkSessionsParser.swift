import Foundation

/// Parses Claude Desktop App's agent-mode (Cowork) session metadata files at
/// `~/Library/Application Support/Claude/local-agent-mode-sessions/<account>/<workspace>/local_<uuid>.json`.
///
/// What this gives us:
/// - Per-day count of agent-mode sessions started
/// - List of the most recent N sessions (title, model, when)
///
/// What this does NOT give us:
/// - Token counts. Those live inside the Cowork VM and never surface to the host.
/// - Anything about claude.ai web chat or normal Claude Desktop chat (no local files at all).
///
/// Same security posture as `TranscriptParser`: bounded sizes, symlink-escape rejection,
/// log-string sanitization for filesystem-derived names.
struct CoworkSessionsParser {

    private static let maxFileBytes = 1 * 1024 * 1024     // 1 MiB per session JSON (they're typically <100 KiB)
    private static let maxFiles = 5_000                   // sane upper bound

    static var rootDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions",
                                    isDirectory: true)
    }

    static func parseAll() -> [CoworkSessionInfo] {
        let fm = FileManager.default
        let root = rootDir
        guard fm.fileExists(atPath: root.path) else { return [] }
        let rootCanonical = root.resolvingSymlinksInPath().standardizedFileURL.path

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [CoworkSessionInfo] = []
        var fileCount = 0

        let decoder = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        // Cowork JSONs use **Unix epoch milliseconds** (e.g., 1769281204922), not ISO strings.
        // Accept either form so we don't break if Anthropic ever changes.
        decoder.dateDecodingStrategy = .custom { d in
            let c = try d.singleValueContainer()
            if let ms = try? c.decode(Double.self) {
                // Heuristic: > 1e12 → milliseconds (post-2001); else seconds.
                let secs = ms > 1e12 ? ms / 1000.0 : ms
                return Date(timeIntervalSince1970: secs)
            }
            if let s = try? c.decode(String.self) {
                return iso.date(from: s) ?? isoNoFrac.date(from: s) ?? .distantPast
            }
            return .distantPast
        }

        for case let url as URL in enumerator {
            // Cap on volume.
            fileCount += 1
            if fileCount > maxFiles {
                Log.parser.warning("cowork parser hit file cap (\(self.maxFiles, privacy: .public)), stopping")
                break
            }

            // Only top-level local_*.json files (not the various subdirs / .lock / .backup files).
            let name = url.lastPathComponent
            guard url.pathExtension == "json",
                  name.hasPrefix("local_"),
                  !name.contains(".backup") else { continue }

            // Symlink-escape rejection.
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(rootCanonical + "/") else {
                Log.parser.warning("cowork: rejected file escaping root: \(name.logSafe, privacy: .public)")
                continue
            }

            // Per-file size cap.
            let attrs = try? resolved.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard attrs?.isRegularFile == true else { continue }
            let size = attrs?.fileSize ?? 0
            guard size <= maxFileBytes else {
                Log.parser.warning("cowork: skipping oversize \(name.logSafe, privacy: .public) (\(size, privacy: .public) bytes)")
                continue
            }

            // Decode minimal subset — ignore unknown keys.
            guard let data = try? Data(contentsOf: resolved),
                  let raw = try? decoder.decode(RawSession.self, from: data) else {
                continue
            }
            // Skip archived / corrupt entries.
            if raw.isArchived == true { continue }
            guard let created = raw.createdAt, created > .distantPast else { continue }
            let last = raw.lastActivityAt ?? created

            results.append(CoworkSessionInfo(
                sessionId: raw.sessionId ?? UUID().uuidString,
                title: (raw.title ?? "(untitled)").logSafe,
                model: raw.model ?? "—",
                createdAt: created,
                lastActivityAt: last
            ))
        }

        // Most recent first.
        results.sort { $0.lastActivityAt > $1.lastActivityAt }
        return results
    }

    private struct RawSession: Decodable {
        let sessionId: String?
        let title: String?
        let model: String?
        let createdAt: Date?
        let lastActivityAt: Date?
        let isArchived: Bool?
    }
}
