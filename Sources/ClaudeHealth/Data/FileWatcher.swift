import Foundation

/// Polls a directory tree for changes by walking and tracking (path → mtime).
/// Polling-based so we don't need recursive FSEvents wiring; the parser already
/// uses (size,mtime) caching so re-parses are sub-100ms when nothing changed.
final class FileWatcher {
    private var timer: Timer?
    private let interval: TimeInterval
    private let root: URL
    private var lastSnapshot: [String: Date] = [:]
    private var onChange: (() -> Void)?

    init(root: URL, interval: TimeInterval = 5.0) {
        self.root = root
        self.interval = interval
    }

    func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        stop()
        // Take initial snapshot so we don't fire spuriously on first tick.
        lastSnapshot = snapshot()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let current = snapshot()
        if current != lastSnapshot {
            lastSnapshot = current
            onChange?()
        }
    }

    private func snapshot() -> [String: Date] {
        let fm = FileManager.default
        var out: [String: Date] = [:]
        guard let projectDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return out
        }
        for projectDir in projectDirs {
            let isDir = (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let files = (try? fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for f in files where f.pathExtension == "jsonl" {
                let mtime = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                out[f.path] = mtime
            }
        }
        return out
    }

    deinit { stop() }
}
