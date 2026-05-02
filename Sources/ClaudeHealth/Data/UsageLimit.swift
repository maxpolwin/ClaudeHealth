import Foundation

/// One time the rolling 5-hour token usage crossed the user-configured budget.
struct LimitEvent: Codable, Identifiable, Equatable {
    var id: UUID
    let timestamp: Date
    let tokensInWindow: Int
    let budget: Int

    init(id: UUID = UUID(), timestamp: Date, tokensInWindow: Int, budget: Int) {
        self.id = id
        self.timestamp = timestamp
        self.tokensInWindow = tokensInWindow
        self.budget = budget
    }
}

enum UsageLimitDefaults {
    static let budgetKey      = "ClaudeHealth.usageLimitTokens5h"
    static let dailyBudgetKey = "ClaudeHealth.usageLimitDaily"
    static let eventsKey      = "ClaudeHealth.limitEvents"

    static var budget: Int {
        get { UserDefaults.standard.integer(forKey: budgetKey) }
        set { UserDefaults.standard.set(newValue, forKey: budgetKey) }
    }

    /// Optional daily token budget. Drives the bubble's activity-ring fill, like
    /// an Apple Health Activity ring. 0 = disabled, falls back to today-vs-avg.
    static var dailyBudget: Int {
        get { UserDefaults.standard.integer(forKey: dailyBudgetKey) }
        set { UserDefaults.standard.set(newValue, forKey: dailyBudgetKey) }
    }

    static var events: [LimitEvent] {
        get {
            guard let data = UserDefaults.standard.data(forKey: eventsKey) else { return [] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return (try? decoder.decode([LimitEvent].self, from: data)) ?? []
        }
        set {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(newValue) {
                UserDefaults.standard.set(data, forKey: eventsKey)
            }
        }
    }
}
