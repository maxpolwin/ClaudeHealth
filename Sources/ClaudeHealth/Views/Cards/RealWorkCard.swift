import SwiftUI

/// "Real work" tokens — input + output only, excludes the dominant cache_read
/// volume that makes ClaudeHealth's headline numbers look 50–100× bigger than
/// what Anthropic's chat UI shows. This is the human-meaningful view.
struct RealWorkCard: View {
    let agg: Aggregates

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(
                title: "Real work tokens",
                symbol: "hammer.fill",
                tint: Palette.brandWarm,
                info: """
                Just input + output tokens — what you typed and what Claude generated. Excludes the cache_read tokens that dominate the headline "Today" / "30-day" numbers (those re-read your conversation context every turn — ~10× cheaper, mostly transparent to you).

                This is the "human work" view, roughly aligned with what claude.ai's chat UI shows. The all-tokens view above is closer to what Anthropic actually meters.
                """
            )

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                stat("Today",   value: agg.realWorkToday,    flex: true)
                divider
                stat("7-day",   value: agg.realWorkLast7,    flex: true)
                divider
                stat("30-day",  value: agg.realWorkLast30,   flex: true)
            }

            // Comparison footnote — gives the user a sense of the cache_read
            // multiplier they're "saving" thanks to caching.
            if agg.todayTokens > 0 {
                let ratio = Double(agg.todayTokens) / max(1.0, Double(agg.realWorkToday))
                Text("All-tokens view shows \(String(format: "%.0f", ratio))× larger numbers (cache reads dominate).")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .healthCard()
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 0.5, height: 36)
            .padding(.horizontal, 4)
    }

    private func stat(_ label: String, value: Int, flex: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NumberFormat.compact(value))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: flex ? .infinity : nil, alignment: .leading)
    }
}
