import Foundation

actor TranscriptParser {
    // Hardening caps — stop a malformed/oversized JSONL from OOMing the app.
    private let maxLineBytes = 1 * 1024 * 1024            // 1 MiB
    private let maxFileBytes = 100 * 1024 * 1024          // 100 MiB
    private let maxTotalBytes = 500 * 1024 * 1024         // 500 MiB across one parse

    private let projectsDir: URL
    private let projectsDirCanonical: String              // resolved + standardized; used to reject symlink escapes
    private let decoder = TranscriptEntry.decoder()

    init(projectsDir: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = projectsDir ?? home.appendingPathComponent(".claude/projects", isDirectory: true)
        self.projectsDir = dir
        self.projectsDirCanonical = dir.resolvingSymlinksInPath().standardizedFileURL.path
    }

    struct ParseResult {
        let records: [Record]
        let index: FileIndex
        let fileCount: Int
        let durationMs: Int
    }

    /// Walk all .jsonl files. Reuses cached records when (size, mtime) is unchanged.
    /// Rejects anything that resolves outside `projectsDir` (e.g., a symlink to ~/.ssh).
    /// Skips files larger than `maxFileBytes` and lines larger than `maxLineBytes`.
    func parseAll(reusing cache: FileIndex) -> ParseResult {
        let start = Date()
        let fm = FileManager.default
        var newIndex: [String: FileIndex.Entry] = [:]
        var allRecords: [Record] = []
        var fileCount = 0
        var totalBytes = 0

        guard let projectDirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return ParseResult(records: [], index: FileIndex(entries: [:]), fileCount: 0, durationMs: 0)
        }

        for projectDir in projectDirs {
            // Reject project dirs that resolve outside ~/.claude/projects (e.g., a symlinked dir).
            let projectResolved = projectDir.resolvingSymlinksInPath().standardizedFileURL
            let projectCanonical = projectResolved.path
            guard projectCanonical.hasPrefix(projectsDirCanonical + "/") || projectCanonical == projectsDirCanonical else {
                Log.parser.warning("rejected project dir outside projects root: \(projectDir.lastPathComponent.logSafe, privacy: .public)")
                continue
            }
            let isDir = (try? projectResolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let projectKey = projectDir.lastPathComponent

            let files = (try? fm.contentsOfDirectory(at: projectResolved,
                          includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                          options: [.skipsHiddenFiles])) ?? []

            for fileURL in files where fileURL.pathExtension == "jsonl" {
                // Resolve once, then operate on the canonical URL throughout —
                // closes the symlink-swap TOCTOU between bounds-check and open.
                let fileResolved = fileURL.resolvingSymlinksInPath().standardizedFileURL
                let fileCanonical = fileResolved.path
                guard fileCanonical.hasPrefix(projectsDirCanonical + "/") else {
                    Log.parser.warning("rejected file escaping projects dir: \(fileURL.lastPathComponent.logSafe, privacy: .public)")
                    continue
                }

                fileCount += 1
                let attrs = try? fileResolved.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = attrs?.fileSize ?? 0
                let mtime = attrs?.contentModificationDate ?? .distantPast
                let cacheKey = fileCanonical

                if size > maxFileBytes {
                    Log.parser.warning("skipping oversize file (>100 MiB): \(fileURL.lastPathComponent.logSafe, privacy: .public) (\(size, privacy: .public) bytes)")
                    continue
                }

                if totalBytes >= maxTotalBytes {
                    Log.parser.warning("hit \(self.maxTotalBytes, privacy: .public)-byte total cap — skipping remaining files")
                    break
                }

                if let cached = cache.entries[cacheKey], cached.size == size, abs(cached.mtime.timeIntervalSince(mtime)) < 0.001 {
                    allRecords.append(contentsOf: cached.records)
                    newIndex[cacheKey] = cached
                    totalBytes += size
                    continue
                }
                let records = parse(fileURL: fileResolved, projectKey: projectKey)
                allRecords.append(contentsOf: records)
                newIndex[cacheKey] = FileIndex.Entry(size: size, mtime: mtime, records: records)
                totalBytes += size
            }
        }

        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        return ParseResult(records: allRecords, index: FileIndex(entries: newIndex),
                           fileCount: fileCount, durationMs: durationMs)
    }

    /// Streaming line-by-line parse with a per-line size cap. We never materialize
    /// the whole file as a single String, so a 100-MiB file with one giant line
    /// won't allocate 100 MiB just to split — the giant line is dropped.
    private func parse(fileURL: URL, projectKey: String) -> [Record] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }

        var records: [Record] = []
        records.reserveCapacity(256)

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        let chunkSize = 64 * 1024
        var droppedOversizeLines = 0

        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: chunkSize) ?? Data()
            } catch {
                Log.parser.warning("read error in \(fileURL.lastPathComponent.logSafe, privacy: .public)")
                break
            }
            if chunk.isEmpty { break }
            buffer.append(chunk)

            // Pull complete lines out of the buffer.
            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineStart = buffer.startIndex
                let lineRange = lineStart..<nl
                let lineData = buffer.subdata(in: lineRange)
                buffer.removeSubrange(lineStart...nl)

                if lineData.count > maxLineBytes {
                    droppedOversizeLines += 1
                    continue
                }
                if lineData.isEmpty { continue }
                if let r = parseLine(lineData, projectKey: projectKey) {
                    records.append(r)
                }
            }

            // Defensive: if the buffer (incomplete trailing line) grows past the
            // line cap with no newline yet, there's a malformed giant line — drop.
            if buffer.count > maxLineBytes {
                droppedOversizeLines += 1
                buffer.removeAll(keepingCapacity: true)
            }
        }

        // Trailing partial line (no newline at EOF).
        if !buffer.isEmpty, buffer.count <= maxLineBytes {
            if let r = parseLine(buffer, projectKey: projectKey) {
                records.append(r)
            }
        }

        if droppedOversizeLines > 0 {
            Log.parser.warning("\(droppedOversizeLines, privacy: .public) oversize line(s) dropped in \(fileURL.lastPathComponent.logSafe, privacy: .public)")
        }
        return records
    }

    private func parseLine(_ lineData: Data, projectKey: String) -> Record? {
        guard let entry = try? decoder.decode(TranscriptEntry.self, from: lineData) else { return nil }
        guard entry.type == "assistant",
              let timestamp = entry.timestamp, timestamp > Date.distantPast,
              let session = entry.sessionId,
              let message = entry.message,
              let model = message.model,
              let usage = message.usage else { return nil }
        let inT  = usage.inputTokens ?? 0
        let outT = usage.outputTokens ?? 0
        let cw   = usage.cacheCreationInputTokens ?? 0
        let cr   = usage.cacheReadInputTokens ?? 0
        if inT + outT + cw + cr == 0 { return nil }
        return Record(
            timestamp: timestamp,
            projectKey: projectKey,
            model: model,
            sessionId: session,
            isSidechain: entry.isSidechain ?? false,
            inputTokens: inT,
            outputTokens: outT,
            cacheCreationTokens: cw,
            cacheReadTokens: cr
        )
    }
}
