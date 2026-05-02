import SwiftUI

struct HeroRingCard: View {
    let aggregates: Aggregates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        let avg = max(1.0, aggregates.thirtyDayDailyAverage)
        return min(1.5, Double(aggregates.todayTokens) / avg)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.10), style: StrokeStyle(lineWidth: 14))
                Circle()
                    .trim(from: 0, to: CGFloat(min(1.0, progress)))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [Palette.brandWarm, Palette.brand]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.85), value: progress)
                VStack(spacing: 2) {
                    Text(NumberFormat.compact(aggregates.todayTokens))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("today")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 132, height: 132)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("Activity")
                        .font(.system(.title3, design: .default).weight(.semibold))
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .help("Today's tokens shown as a ring filling toward your 30-day daily average. A full ring = matched your typical day.")
                }
                deltaRow(label: "vs daily avg",
                         value: aggregates.thirtyDayDailyAverage == 0 ? 0
                                : (Double(aggregates.todayTokens) - aggregates.thirtyDayDailyAverage) / aggregates.thirtyDayDailyAverage)
                miniStat(label: "30-day average",
                         value: NumberFormat.compact(Int(aggregates.thirtyDayDailyAverage)) + " / day")
                miniStat(label: "Velocity (last 15 min)",
                         value: NumberFormat.compact(Int(aggregates.velocityPerMinute.rounded())) + " / min")
            }
            Spacer(minLength: 0)
        }
        .healthCard()
    }

    private func deltaRow(label: String, value: Double) -> some View {
        let color: Color = value >= 0 ? Palette.brand : Palette.brandDeep
        return HStack(spacing: 6) {
            Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(NumberFormat.compactPercent(abs(value)))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func miniStat(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}
