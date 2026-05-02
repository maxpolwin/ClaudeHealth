import SwiftUI

enum Palette {
    // --- Claude brand palette (matches the app icon) ---------------------
    /// Canonical Claude orange — primary accent used by ring, bubble, hero, summaries.
    static let brand     = Color(red: 0.85, green: 0.47, blue: 0.34)   // ~#D97757
    /// Warmer companion for gradients ("amber" end stop).
    static let brandWarm = Color(red: 0.95, green: 0.65, blue: 0.32)   // ~#F2A652
    /// Deeper companion for gradients ("burnt" end stop).
    static let brandDeep = Color(red: 0.65, green: 0.32, blue: 0.20)   // ~#A65133

    // --- Token-type colors -----------------------------------------------
    // Distinct enough to differentiate the four bands in the daily stacked bar.
    // Cache write deliberately uses `brand` so the dashboard's most-frequent
    // color reads as Claude orange.
    static let input      = Color.blue
    static let output     = Color.purple
    static let cacheWrite = brand
    static let cacheRead  = Color.green

    /// Five-level intensity gradient used by the year contribution heatmap.
    /// Now keyed off the Claude brand orange so it visually matches the app icon.
    static let heatLevels: [Color] = [
        Color(nsColor: .quaternaryLabelColor).opacity(0.18),
        brand.opacity(0.28),
        brand.opacity(0.50),
        brand.opacity(0.75),
        brand
    ]

    static func heatColor(for value: Double, ceiling: Double) -> Color {
        guard ceiling > 0, value > 0 else { return heatLevels[0] }
        let ratio = min(1.0, value / ceiling)
        let lastIdx = heatLevels.count - 1
        let scaled = ratio == 0 ? 0 : max(1, Int(ceil(ratio * Double(lastIdx))))
        return heatLevels[min(lastIdx, scaled)]
    }

    /// Color for usage-limit progress (bubble ring + limit card). Stays in the warm
    /// Claude-orange family throughout: brand orange (calm) → warm amber (heating up)
    /// → systemRed (over budget). Avoids the cool-green clash with the rest of the UI.
    static func limitColor(progress t: Double) -> Color {
        let clamped = max(0, min(1, t))
        let stops: [(CGFloat, NSColor)] = [
            (0.0, NSColor(brand)),         // Claude orange — at rest
            (0.5, NSColor(brandWarm)),     // amber — heating up
            (1.0, .systemRed)              // red — at/over the limit
        ]
        // Find the segment, lerp between the two endpoints.
        for i in 0..<(stops.count - 1) {
            let (t0, c0) = stops[i]
            let (t1, c1) = stops[i + 1]
            if clamped <= t1 {
                let local = (clamped - t0) / (t1 - t0)
                let blended = c0.blended(withFraction: CGFloat(local), of: c1) ?? c0
                return Color(blended)
            }
        }
        return Color(stops.last!.1)
    }
}

/// Compact number formatter (1.2K, 3.4M) used in space-constrained labels.
enum NumberFormat {
    static func compact(_ n: Int) -> String {
        let v = Double(n)
        if v < 1_000        { return "\(n)" }
        if v < 10_000       { return String(format: "%.1fK", v / 1_000) }
        if v < 1_000_000    { return "\(Int(v / 1_000))K" }
        if v < 10_000_000   { return String(format: "%.1fM", v / 1_000_000) }
        if v < 1_000_000_000 { return "\(Int(v / 1_000_000))M" }
        return String(format: "%.1fB", v / 1_000_000_000)
    }

    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func usd(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = v < 1 ? 3 : 2
        f.maximumFractionDigits = v < 1 ? 3 : 2
        return f.string(from: NSNumber(value: v)) ?? "$0"
    }

    static func percent(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: v)) ?? "0%"
    }

    /// Compact percent display that gracefully handles wild overflow:
    ///   0.635 → "64 %"
    ///   1.27  → "127 %"
    ///   3.27  → "327 %"
    ///   33.0  → "33×"
    ///   100+  → "99×+"
    /// Designed to always fit in a small badge or ring without overflowing layout.
    static func compactPercent(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .percent
        if v < 1.0 {
            f.maximumFractionDigits = 0
            return f.string(from: NSNumber(value: v)) ?? "0%"
        }
        if v < 10.0 {
            // 100–999%: integer percent, no decimal
            f.maximumFractionDigits = 0
            return f.string(from: NSNumber(value: v)) ?? "\(Int(v * 100))%"
        }
        if v < 100.0 {
            // 10×–99×: multiplier
            return "\(Int(v))×"
        }
        return "99×+"
    }
}
