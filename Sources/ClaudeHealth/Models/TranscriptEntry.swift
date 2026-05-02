import Foundation

struct TranscriptEntry: Decodable {
    let type: String?
    let timestamp: Date?
    let sessionId: String?
    let cwd: String?
    let isSidechain: Bool?
    let message: MessageBody?

    struct MessageBody: Decodable {
        let model: String?
        let role: String?
        let usage: Usage?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            return iso.date(from: raw) ?? isoNoFrac.date(from: raw) ?? Date.distantPast
        }
        return d
    }
}
