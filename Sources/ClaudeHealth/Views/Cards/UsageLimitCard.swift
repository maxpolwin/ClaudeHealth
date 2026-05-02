import SwiftUI

struct UsageLimitCard: View {
    let tokensLast5h: Int
    let budget: Int
    let progress: Double          // 0…∞ (≥1 = over)
    let recentEventCount: Int     // last 30 days

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ringColor: Color { Palette.limitColor(progress: progress) }

    /// True when ≥10× over budget — switches the % text to a multiplier badge.
    private var isMassivelyOver: Bool { progress >= 10.0 }

    /// True when over budget at all.
    private var isOver: Bool { progress >= 1.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "5-hour usage limit",
                       symbol: "gauge.with.dots.needle.bottom.50percent",
                       tint: ringColor,
                       info: "Tokens used in the rolling 5-hour window vs the budget you set in Settings. The bubble's color shifts orange → amber → red as you approach (and exceed) the limit. When you cross it, ClaudeHealth logs the event and fires confetti.")
            if budget == 0 {
                emptyState
            } else {
                content
            }
        }
        .healthCard()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No budget set")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Open Settings and enter the number of tokens you'd consider your 5-hour cap. The dashboard will track and notify when you cross it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.10), style: StrokeStyle(lineWidth: 10))
                Circle()
                    .trim(from: 0, to: CGFloat(min(1.0, progress)))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.85), value: progress)
                VStack(spacing: 1) {
                    Text(NumberFormat.compactPercent(progress))
                        .font(.system(size: isMassivelyOver ? 20 : 17, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if isOver {
                        Text("OVER")
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(ringColor)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 4) {
                row("Used",   value: NumberFormat.compact(tokensLast5h))
                row("Budget", value: NumberFormat.compact(budget))
                if isOver {
                    row("Over by",
                        value: NumberFormat.compact(tokensLast5h - budget),
                        valueColor: ringColor)
                } else {
                    row("Remaining",
                        value: NumberFormat.compact(max(0, budget - tokensLast5h)))
                }
                if recentEventCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.brand)
                        Text("Crossed \(recentEventCount)× in last 30 days")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func row(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
    }
}
