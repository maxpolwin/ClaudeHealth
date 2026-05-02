import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class DataStore {
    var aggregates: Aggregates
    var isRefreshing: Bool = false
    var lastError: String? = nil

    /// User-configured rolling-5h budget. 0 = disabled.
    var usageLimitBudget: Int {
        didSet {
            UsageLimitDefaults.budget = usageLimitBudget
            recomputeProgressAndDetectCrossing()
        }
    }
    /// User-configured daily token budget for the bubble's activity ring.
    /// 0 = disabled, ring then falls back to today-vs-30-day-average.
    var usageLimitDaily: Int {
        didSet { UsageLimitDefaults.dailyBudget = usageLimitDaily }
    }
    /// 0…∞ — usually 0…1, can exceed when over budget.
    var usageLimitProgress: Double = 0
    var limitEvents: [LimitEvent]

    /// Kept for backward compat with any view still binding to it (currently none after refactor).
    var pendingConfetti: Bool = false

    /// Set by AppDelegate; called whenever a confetti trigger should fire.
    /// Direct callback rather than KVO/polling so no timing race.
    var onConfettiTrigger: (() -> Void)?

    private let parser: TranscriptParser
    private var cache: FileIndex
    private let watcher: FileWatcher
    private var idleRefreshTimer: Timer?
    private var lastProgressBelow1: Bool = true

    init() {
        self.parser = TranscriptParser()
        if let payload = Cache.load() {
            self.aggregates = payload.aggregates
            self.cache = payload.fileIndex
        } else {
            self.aggregates = .empty
            self.cache = .empty
        }
        self.usageLimitBudget = UsageLimitDefaults.budget
        self.usageLimitDaily = UsageLimitDefaults.dailyBudget
        self.limitEvents = UsageLimitDefaults.events
        let projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        // 0.5s poll — live-feel updates while you're actively coding. Cost is
        // ~30 file stats per tick, negligible CPU.
        self.watcher = FileWatcher(root: projectsDir, interval: 0.5)
        recomputeProgressAndDetectCrossing()
        Task { await self.refresh() }
        watcher.start { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }

        // Idle re-aggregate every 5s so rolling-window metrics (velocity, last-15-min,
        // last-5h) decay to zero during quiet periods. Files-on-disk parser is skipped
        // (mtime cache) so this is ~5 ms of work per tick — just re-runs Aggregator
        // against the current wall clock to slide the windows forward.
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleRefreshTimer = timer
    }


    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let snapshotCache = self.cache
        let result = await parser.parseAll(reusing: snapshotCache)
        // Cheap synchronous side-channel: read Claude Desktop's agent-mode session metadata
        // (~5 ms; just JSON files <100 KiB each, no tokens inside).
        let coworkSessions = CoworkSessionsParser.parseAll()
        let agg = Aggregator.aggregate(
            records: result.records,
            totalFiles: result.fileCount,
            parseDurationMs: result.durationMs,
            coworkSessions: coworkSessions
        )
        self.cache = result.index
        self.aggregates = agg
        recomputeProgressAndDetectCrossing()
        let payload = CachePayload(fileIndex: result.index, aggregates: agg)
        DispatchQueue.global(qos: .utility).async {
            Cache.save(payload)
        }
    }

    /// Manually trigger confetti — wired to the "Test confetti now" Settings button.
    func triggerConfettiNow() {
        Log.confetti.info("manual trigger requested")
        onConfettiTrigger?()
    }

    func clearLimitEvents() {
        limitEvents.removeAll()
        UsageLimitDefaults.events = limitEvents
    }

    private func recomputeProgressAndDetectCrossing() {
        guard usageLimitBudget > 0 else {
            usageLimitProgress = 0
            lastProgressBelow1 = true
            return
        }
        let p = Double(aggregates.tokensLast5h) / Double(usageLimitBudget)
        usageLimitProgress = p
        if p >= 1.0 && lastProgressBelow1 {
            let event = LimitEvent(
                timestamp: Date(),
                tokensInWindow: aggregates.tokensLast5h,
                budget: usageLimitBudget
            )
            limitEvents.append(event)
            UsageLimitDefaults.events = limitEvents
            Log.limit.notice("usage limit crossed — \(self.aggregates.tokensLast5h, privacy: .private) / \(self.usageLimitBudget, privacy: .private) — firing confetti")
            onConfettiTrigger?()
        }
        lastProgressBelow1 = (p < 1.0)
    }
}
