import Foundation
import Darwin

struct FileIndex: Codable {
    struct Entry: Codable {
        let size: Int
        let mtime: Date
        let records: [Record]
    }
    var entries: [String: Entry]

    static let empty = FileIndex(entries: [:])
}

struct CachePayload: Codable {
    /// Bumped whenever Aggregates / Record / FileIndex layout changes incompatibly.
    /// Loader rejects mismatching versions and rebuilds from JSONL ground truth — also
    /// blocks an attacker from substituting a tampered cache.json to fake activity:
    /// without our bundle id + version, the cache is ignored.
    static let currentSchemaVersion = 2

    var schemaVersion: Int = currentSchemaVersion
    var bundleIdentifier: String = Bundle.main.bundleIdentifier ?? ""
    var fileIndex: FileIndex
    var aggregates: Aggregates
}

enum Cache {
    static var directory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ClaudeHealth", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }

    static var url: URL { directory.appendingPathComponent("cache.json") }

    static func load() -> CachePayload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(CachePayload.self, from: data) else {
            Log.cache.warning("cache decode failed — rebuilding from JSONL")
            return nil
        }
        // Integrity guards: only trust caches that we wrote, at the schema version we expect.
        // An attacker who substitutes a fake cache.json can't pass both checks.
        guard payload.schemaVersion == CachePayload.currentSchemaVersion else {
            Log.cache.warning("cache schema mismatch (\(payload.schemaVersion, privacy: .public) vs \(CachePayload.currentSchemaVersion, privacy: .public)) — rebuilding")
            return nil
        }
        let myBundle = Bundle.main.bundleIdentifier ?? ""
        guard payload.bundleIdentifier == myBundle else {
            Log.cache.warning("cache bundle identifier mismatch — rebuilding")
            return nil
        }
        return payload
    }

    static func save(_ payload: CachePayload) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(payload)
            try writeAtomicPrivate(data, to: url)
        } catch {
            Log.cache.error("save failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Write `data` to `url` such that the file *never* exists at relaxed permissions.
    /// Open with O_CREAT mode 0600, write+fsync, then atomically rename into place.
    /// Closes the TOCTOU window in `data.write(to:) + setAttributes(.posixPermissions:)`.
    private static func writeAtomicPrivate(_ data: Data, to url: URL) throws {
        let tmpURL = url.appendingPathExtension("tmp")
        // Remove any leftover from a previous failed attempt.
        try? FileManager.default.removeItem(at: tmpURL)

        let fd = open(tmpURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        // Defensive: enforce 0600 even if umask permitted broader (open() respects umask).
        _ = fchmod(fd, 0o600)
        defer { close(fd) }

        var written = 0
        try data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            guard let base = buf.baseAddress else { return }
            while written < data.count {
                let n = write(fd, base.advanced(by: written), data.count - written)
                if n <= 0 {
                    let code = errno
                    throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                }
                written += n
            }
        }
        fsync(fd)

        // Atomic rename. Use replaceItemAt for crash-safety semantics.
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
        } catch {
            // Fallback: if replaceItemAt failed because url didn't exist yet, plain move.
            try FileManager.default.moveItem(at: tmpURL, to: url)
        }
        // Final defensive chmod on the destination (replaceItemAt may copy attrs from url).
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
