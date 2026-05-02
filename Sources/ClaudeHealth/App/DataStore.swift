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

    // --- Apple Intelligence insight (on-device, optional) ---
    var insight: String? = nil
    var insightLoading: Bool = false
    var insightUpdatedAt: Date? = nil
    /// Throttle: don't auto-regenerate more often than this.
    private let insightAutoStale: TimeInterval = 30 * 60   // 30 min

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
        // 1.5s poll — live-feel without burning ~1k stat() calls/sec on users with
        // many project dirs. The watcher is debounced; aggregator is off-main now,
        // so a faster poll buys nothing perceptible.
        self.watcher = FileWatcher(root: projectsDir, interval: 1.5)
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
        // Cowork parse + aggregator are pure CPU over the just-parsed records;
        // run them off the main actor so they don't stutter bubble animations
        // when the timer fires every 5s or the watcher detects a change.
        let agg = await Task.detached(priority: .userInitiated) { () -> Aggregates in
            let coworkSessions = CoworkSessionsParser.parseAll()
            return Aggregator.aggregate(
                records: result.records,
                totalFiles: result.fileCount,
                parseDurationMs: result.durationMs,
                coworkSessions: coworkSessions
            )
        }.value
        self.cache = result.index
        self.aggregates = agg
        recomputeProgressAndDetectCrossing()
        if SecurityState.shared.allowsCacheWrite {
            let payload = CachePayload(fileIndex: result.index, aggregates: agg)
            DispatchQueue.global(qos: .utility).async {
                Cache.save(payload)
            }
        }
    }

    /// Manually trigger confetti — wired to the "Test confetti now" Settings button.
    func triggerConfettiNow() {
        Log.confetti.info("manual trigger requested")
        onConfettiTrigger?()
    }

    /// Regenerate the on-device Apple Intelligence summary. User-triggered or
    /// auto-called by `maybeRefreshInsight()` when the cached insight is stale.
    func regenerateInsight() async {
        guard !insightLoading else { return }
        insightLoading = true
        defer { insightLoading = false }
        let result = await InsightGenerator.generate(
            from: aggregates,
            dailyBudget: usageLimitDaily,
            fiveHourBudget: usageLimitBudget
        )
        if let result {
            insight = result
            insightUpdatedAt = Date()
        }
    }

    /// Auto-refresh the insight if it's missing or older than the throttle window.
    /// Called by DashboardWindowController on show. Cheap when nothing to do.
    func maybeRefreshInsight() async {
        if let last = insightUpdatedAt, Date().timeIntervalSince(last) < insightAutoStale {
            return
        }
        await regenerateInsight()
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
