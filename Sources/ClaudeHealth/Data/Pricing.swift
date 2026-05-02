import Foundation

struct ModelPricing: Codable, Equatable {
    /// USD per million tokens
    let inputPerMTok: Double
    let outputPerMTok: Double
    let cacheWritePerMTok: Double
    let cacheReadPerMTok: Double

    func cost(input: Int, output: Int, cacheWrite: Int, cacheRead: Int) -> Double {
        let m = 1_000_000.0
        return Double(input)      / m * inputPerMTok
             + Double(output)     / m * outputPerMTok
             + Double(cacheWrite) / m * cacheWritePerMTok
             + Double(cacheRead)  / m * cacheReadPerMTok
    }
}

enum Pricing {
    /// Date the table below was last verified. Surface in the UI so stale numbers are flagged.
    static let asOf = "2026-05-01"

    /// Public Anthropic pricing per million tokens. If a model is not listed,
    /// `priceFor(model:)` falls back to the closest family rate, then Sonnet rate.
    private static let table: [String: ModelPricing] = [
        // Opus family
        "claude-opus-4-7":          ModelPricing(inputPerMTok: 15.00, outputPerMTok: 75.00, cacheWritePerMTok: 18.75, cacheReadPerMTok: 1.50),
        "claude-opus-4-6":          ModelPricing(inputPerMTok: 15.00, outputPerMTok: 75.00, cacheWritePerMTok: 18.75, cacheReadPerMTok: 1.50),
        "claude-opus-4-5":          ModelPricing(inputPerMTok: 15.00, outputPerMTok: 75.00, cacheWritePerMTok: 18.75, cacheReadPerMTok: 1.50),
        // Sonnet family
        "claude-sonnet-4-6":        ModelPricing(inputPerMTok:  3.00, outputPerMTok: 15.00, cacheWritePerMTok:  3.75, cacheReadPerMTok: 0.30),
        "claude-sonnet-4-5":        ModelPricing(inputPerMTok:  3.00, outputPerMTok: 15.00, cacheWritePerMTok:  3.75, cacheReadPerMTok: 0.30),
        // Haiku family
        "claude-haiku-4-5":         ModelPricing(inputPerMTok:  0.80, outputPerMTok:  4.00, cacheWritePerMTok:  1.00, cacheReadPerMTok: 0.08),
        "claude-haiku-4-5-20251001":ModelPricing(inputPerMTok:  0.80, outputPerMTok:  4.00, cacheWritePerMTok:  1.00, cacheReadPerMTok: 0.08),
    ]

    /// Sonnet rate as ultimate fallback so unknown models don't silently zero out totals.
    static let sonnetFallback = ModelPricing(
        inputPerMTok: 3.00, outputPerMTok: 15.00,
        cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.30
    )

    static func priceFor(model: String) -> ModelPricing {
        if let p = table[model] { return p }
        // Prefix match (handles "claude-opus-4-7-1m" etc.)
        for (key, val) in table where model.hasPrefix(key) { return val }
        // Family match
        let lc = model.lowercased()
        if lc.contains("opus")   { return table["claude-opus-4-7"]   ?? sonnetFallback }
        if lc.contains("haiku")  { return table["claude-haiku-4-5"]  ?? sonnetFallback }
        if lc.contains("sonnet") { return table["claude-sonnet-4-6"] ?? sonnetFallback }
        return sonnetFallback
    }
}

/// Display name helpers for models. Kept here next to pricing because they share the keying convention.
enum ModelDisplay {
    static func name(for model: String) -> String {
        let parts = model.lowercased().split(separator: "-")
        guard parts.count >= 4, parts[0] == "claude" else { return model }
        let family = String(parts[1]).capitalized
        let maj = parts[2]
        let min = parts[3]
        var suffix = ""
        if parts.count > 4, parts[4] == "1m" { suffix = " (1M)" }
        return "\(family) \(maj).\(min)\(suffix)"
    }
}
