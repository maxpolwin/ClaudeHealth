import Foundation

/// All the pre-computed buckets the dashboard renders. Computed by `Aggregator`,
/// cached to disk by `Cache`, observed by SwiftUI via `DataStore`.
struct Aggregates: Codable, Equatable {
    var generatedAt: Date
    var totalRecords: Int
    var totalFiles: Int
    var parseDurationMs: Int

    var daily: [DailyBucket]                  // sorted ascending by date
    var hourDay: [[Double]]                   // 7 rows (Sun..Sat) × 24 cols (0..23) avg tokens/cell
    var byProject: [ProjectBucket]            // sorted desc by tokens
    var byModel: [ModelBucket]                // sorted desc by tokens
    var sessionsPerDay: [SessionsBucket]      // sorted ascending by date

    // Headline numbers (precomputed for hot-path rendering)
    var todayTokens: Int
    var last7Tokens: Int
    var last30Tokens: Int
    var prev7Tokens: Int
    var prev30Tokens: Int
    var thirtyDayDailyAverage: Double
    var currentStreakDays: Int
    var longestStreakDays: Int

    // Live metrics
    var tokensLast5h: Int                     // rolling 5-hour window
    var tokensLast15min: Int                  // rolling 15-min window
    var velocityPerMinute: Double             // tokensLast15min / 15  (smooth)
    var liveVelocityPerMinute: Double         // sum of last 3 minute buckets / 3  (responsive, decays in ~3 min)
    var minutelyLast60: [MinuteBucket]        // tokens per minute over the last 60 minutes (60 entries)

    // "Real work" tokens: input + output only. Excludes cache_read (which
    // dominates the all-tokens count by ~97 %) AND cache_creation. This is the
    // "human-meaningful" view — what you typed and what Claude generated —
    // and roughly matches the numbers Anthropic's chat UI surfaces.
    var realWorkToday: Int
    var realWorkLast7: Int
    var realWorkLast30: Int
    var realWorkLast5h: Int
    var realWorkLast15min: Int
    var realWorkVelocityPerMinute: Double      // smooth 15-min
    var realWorkLiveVelocityPerMinute: Double  // responsive 3-min
    var realWorkMinutelyLast60: [MinuteBucket] // for the velocity sparkline when in real-work mode

    // Cowork (Claude Desktop App, agent-mode) sessions — metadata only, no tokens
    // (those live inside the Cowork VM, unreachable from host). Lets us at least
    // surface "Hey, you ran N agent sessions today" alongside the Code-only data.
    var coworkSessionsPerDay: [SessionsBucket]
    var recentCoworkSessions: [CoworkSessionInfo]

    static let empty = Aggregates(
        generatedAt: .distantPast,
        totalRecords: 0, totalFiles: 0, parseDurationMs: 0,
        daily: [],
        hourDay: Array(repeating: Array(repeating: 0.0, count: 24), count: 7),
        byProject: [], byModel: [], sessionsPerDay: [],
        todayTokens: 0, last7Tokens: 0, last30Tokens: 0,
        prev7Tokens: 0, prev30Tokens: 0,
        thirtyDayDailyAverage: 0,
        currentStreakDays: 0, longestStreakDays: 0,
        tokensLast5h: 0, tokensLast15min: 0,
        velocityPerMinute: 0, liveVelocityPerMinute: 0, minutelyLast60: [],
        realWorkToday: 0, realWorkLast7: 0, realWorkLast30: 0,
        realWorkLast5h: 0, realWorkLast15min: 0,
        realWorkVelocityPerMinute: 0, realWorkLiveVelocityPerMinute: 0,
        realWorkMinutelyLast60: [],
        coworkSessionsPerDay: [], recentCoworkSessions: []
    )
}

extension DailyBucket {
    /// Input + output only — Claude's "real work" output excluding cache plumbing.
    var realWorkTokens: Int { inputTokens + outputTokens }
}

/// One Claude Desktop App "Cowork" / agent-mode session. We see metadata only
/// (tokens consumed inside the VM aren't observable from the host).
struct CoworkSessionInfo: Codable, Equatable, Identifiable {
    var id: String { sessionId }
    let sessionId: String
    let title: String
    let model: String
    let createdAt: Date
    let lastActivityAt: Date
}

struct DailyBucket: Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }
    var cacheHitRatio: Double {
        let denom = inputTokens + cacheReadTokens
        return denom == 0 ? 0 : Double(cacheReadTokens) / Double(denom)
    }
}

struct ProjectBucket: Codable, Equatable, Identifiable {
    var id: String { projectKey }
    let projectKey: String
    let displayName: String
    let totalTokens: Int
}

struct ModelBucket: Codable, Equatable, Identifiable {
    var id: String { model }
    let model: String
    let displayName: String
    let totalTokens: Int
}

struct SessionsBucket: Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let count: Int
}

/// One minute of token activity, used for the velocity sparkline.
struct MinuteBucket: Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date           // minute start
    let tokens: Int
}
