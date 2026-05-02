import Foundation

/// One billable assistant turn extracted from a JSONL transcript.
struct Record: Codable, Hashable {
    let timestamp: Date
    let projectKey: String      // raw directory name e.g. "-Users-max-Development-TL-DR"
    let model: String
    let sessionId: String
    let isSidechain: Bool
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }
}
