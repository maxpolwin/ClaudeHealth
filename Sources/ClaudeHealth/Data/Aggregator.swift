import Foundation

enum Aggregator {

    static func aggregate(
        records: [Record],
        totalFiles: Int,
        parseDurationMs: Int,
        coworkSessions: [CoworkSessionInfo] = []
    ) -> Aggregates {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let fiveHoursAgo  = now.addingTimeInterval(-5 * 60 * 60)
        let fifteenMinAgo = now.addingTimeInterval(-15 * 60)
        let sixtyMinAgo   = now.addingTimeInterval(-60 * 60)

        var dailyMap: [Date: (input: Int, output: Int, cacheW: Int, cacheR: Int)] = [:]
        var sessionsMap: [Date: Set<String>] = [:]
        var hourDayTotals = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
        var hourDayDays  = Array(repeating: Array(repeating: Set<Date>(), count: 24), count: 7)
        var projMap:  [String: Int] = [:]
        var modelMap: [String: Int] = [:]

        var tokensLast5h = 0
        var tokensLast15min = 0
        var minutelyMap: [Date: Int] = [:]    // minute-start → tokens

        for r in records {
            let day = cal.startOfDay(for: r.timestamp)

            var d = dailyMap[day] ?? (0,0,0,0)
            d.input  += r.inputTokens
            d.output += r.outputTokens
            d.cacheW += r.cacheCreationTokens
            d.cacheR += r.cacheReadTokens
            dailyMap[day] = d

            sessionsMap[day, default: []].insert(r.sessionId)

            let comps = cal.dateComponents([.weekday, .hour], from: r.timestamp)
            let dow = ((comps.weekday ?? 1) - 1).clamped(to: 0...6)
            let hour = (comps.hour ?? 0).clamped(to: 0...23)
            hourDayTotals[dow][hour] += Double(r.totalTokens)
            hourDayDays[dow][hour].insert(day)

            projMap[r.projectKey, default: 0] += r.totalTokens
            modelMap[r.model, default: 0] += r.totalTokens

            // Limit math counts ALL token types (input + output + cache_creation + cache_read)
            // for consistency with the rest of the dashboard. Cache_read is a discount mechanism
            // and doesn't push you toward Anthropic's rate limits as hard as input/output, so
            // pick a budget number relative to what you see in the dashboard's "Today" / "30-day"
            // numbers — not Anthropic's per-plan documentation.
            if r.timestamp >= fiveHoursAgo {
                tokensLast5h += r.totalTokens
            }
            if r.timestamp >= fifteenMinAgo {
                tokensLast15min += r.totalTokens
            }
            if r.timestamp >= sixtyMinAgo {
                let minute = startOfMinute(r.timestamp, cal: cal)
                minutelyMap[minute, default: 0] += r.totalTokens
            }
        }

        let daily = dailyMap.keys.sorted().map { date -> DailyBucket in
            let e = dailyMap[date]!
            return DailyBucket(
                date: date,
                inputTokens: e.input, outputTokens: e.output,
                cacheCreationTokens: e.cacheW, cacheReadTokens: e.cacheR
            )
        }

        var hourDay = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
        for d in 0..<7 {
            for h in 0..<24 {
                let n = hourDayDays[d][h].count
                hourDay[d][h] = n > 0 ? hourDayTotals[d][h] / Double(n) : 0
            }
        }

        let byProject = projMap.map { (k, v) in
            ProjectBucket(projectKey: k, displayName: ProjectName.displayName(for: k), totalTokens: v)
        }.sorted { $0.totalTokens > $1.totalTokens }

        let byModel = modelMap.map { (k, v) in
            ModelBucket(model: k, displayName: ModelDisplay.name(for: k), totalTokens: v)
        }.sorted { $0.totalTokens > $1.totalTokens }

        let sessionsPerDay = sessionsMap.keys.sorted().map { day in
            SessionsBucket(date: day, count: sessionsMap[day]!.count)
        }

        let todayTokens = (dailyMap[today].map { $0.input + $0.output + $0.cacheW + $0.cacheR }) ?? 0
        let last7  = totalIn(daily: daily, days: 7,  ending: today, cal: cal)
        let last30 = totalIn(daily: daily, days: 30, ending: today, cal: cal)
        let prev7End  = cal.date(byAdding: .day, value: -7,  to: today)!
        let prev30End = cal.date(byAdding: .day, value: -30, to: today)!
        let prev7  = totalIn(daily: daily, days: 7,  ending: prev7End,  cal: cal)
        let prev30 = totalIn(daily: daily, days: 30, ending: prev30End, cal: cal)
        let avg30 = Double(last30) / 30.0

        let (currentStreak, longestStreak) = streaks(daily: daily, today: today, cal: cal)

        // Build full minute series for last 60 minutes (zero-fill missing minutes)
        let nowMinute = startOfMinute(now, cal: cal)
        var minutely: [MinuteBucket] = []
        minutely.reserveCapacity(60)
        for offset in stride(from: -59, through: 0, by: 1) {
            let m = cal.date(byAdding: .minute, value: offset, to: nowMinute)!
            minutely.append(MinuteBucket(date: m, tokens: minutelyMap[m] ?? 0))
        }

        let velocity = Double(tokensLast15min) / 15.0

        // Cowork (agent-mode) sessions per day, bucketed by lastActivityAt in user TZ.
        var coworkPerDay: [Date: Int] = [:]
        for s in coworkSessions {
            let day = cal.startOfDay(for: s.lastActivityAt)
            coworkPerDay[day, default: 0] += 1
        }
        let coworkSessionsPerDay = coworkPerDay.keys.sorted().map { d in
            SessionsBucket(date: d, count: coworkPerDay[d]!)
        }
        let recentCowork = Array(coworkSessions.prefix(8))
        // Live velocity = avg over the last 3 minute buckets — responsive (decays
        // in ~3 minutes after activity stops) without being one-sample noisy.
        let lastThree = minutely.suffix(3).reduce(0) { $0 + $1.tokens }
        let liveVelocity = Double(lastThree) / 3.0

        return Aggregates(
            generatedAt: Date(),
            totalRecords: records.count,
            totalFiles: totalFiles,
            parseDurationMs: parseDurationMs,
            daily: daily,
            hourDay: hourDay,
            byProject: byProject,
            byModel: byModel,
            sessionsPerDay: sessionsPerDay,
            todayTokens: todayTokens,
            last7Tokens: last7,
            last30Tokens: last30,
            prev7Tokens: prev7,
            prev30Tokens: prev30,
            thirtyDayDailyAverage: avg30,
            currentStreakDays: currentStreak,
            longestStreakDays: longestStreak,
            tokensLast5h: tokensLast5h,
            tokensLast15min: tokensLast15min,
            velocityPerMinute: velocity,
            liveVelocityPerMinute: liveVelocity,
            minutelyLast60: minutely,
            coworkSessionsPerDay: coworkSessionsPerDay,
            recentCoworkSessions: recentCowork
        )
    }

    // MARK: - Helpers

    private static func totalIn(daily: [DailyBucket], days: Int, ending: Date, cal: Calendar) -> Int {
        let lower = cal.date(byAdding: .day, value: -(days - 1), to: ending)!
        return daily.filter { $0.date >= lower && $0.date <= ending }.reduce(0) { $0 + $1.totalTokens }
    }

    private static func streaks(daily: [DailyBucket], today: Date, cal: Calendar) -> (current: Int, longest: Int) {
        let active = Set(daily.filter { $0.totalTokens > 0 }.map { $0.date })
        var current = 0
        var cursor = today
        if !active.contains(cursor) {
            cursor = cal.date(byAdding: .day, value: -1, to: today)!
        }
        while active.contains(cursor) {
            current += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        var longest = 0, run = 0
        var prev: Date? = nil
        for d in active.sorted() {
            if let p = prev, cal.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            longest = max(longest, run)
            prev = d
        }
        return (current, longest)
    }

    private static func startOfMinute(_ date: Date, cal: Calendar) -> Date {
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return cal.date(from: comps) ?? date
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
