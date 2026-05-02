import SwiftUI
import Charts

struct VelocityCard: View {
    let minutely: [MinuteBucket]
    let velocityPerMinute: Double         // smooth 15-min average
    let liveVelocityPerMinute: Double     // responsive 3-min average (drives the headline)
    let tokensLast15min: Int

    @State private var selectedMinute: Date?

    /// Unit-aware live readout: shows /sec when ≥ 1 token/sec, else /min.
    private var headline: (value: Int, unit: String) {
        let perSec = liveVelocityPerMinute / 60.0
        if perSec >= 1.0 {
            return (Int(perSec.rounded()), "/ sec")
        } else {
            return (Int(liveVelocityPerMinute.rounded()), "/ min")
        }
    }

    private var selectedBucket: MinuteBucket? {
        guard let selectedMinute else { return nil }
        return minutely.min(by: { abs($0.date.timeIntervalSince(selectedMinute)) < abs($1.date.timeIntervalSince(selectedMinute)) })
    }

    private var ceiling: Int {
        max(1, minutely.map(\.tokens).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeader(title: "Live velocity",
                           symbol: "bolt.fill",
                           tint: Palette.brand,
                           info: "Live token rate, smoothed over the last 3 minutes. Auto-switches between /sec and /min so the value is always readable: tokens-per-second when you're actively bursting, tokens-per-minute when activity is light. The 15-min average and last-15-min total below give the smoother context.")
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(NumberFormat.compact(headline.value))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text(headline.unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(NumberFormat.compact(tokensLast15min))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("tokens · last 15 min")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("(\(NumberFormat.compact(Int(velocityPerMinute.rounded()))) / min avg)")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            Chart {
                ForEach(minutely) { m in
                    AreaMark(
                        x: .value("Minute", m.date),
                        y: .value("Tokens", m.tokens)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [Color.yellow.opacity(0.45), Color.yellow.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                    LineMark(
                        x: .value("Minute", m.date),
                        y: .value("Tokens", m.tokens)
                    )
                    .foregroundStyle(Color.orange)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                if let sel = selectedBucket {
                    RuleMark(x: .value("Selected", sel.date))
                        .foregroundStyle(Color.primary.opacity(0.25))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            tooltip(for: sel)
                        }
                }
            }
            .chartXSelection(value: $selectedMinute)
            .chartXAxis {
                AxisMarks(values: .stride(by: .minute, count: 15)) { _ in
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisValueLabel {
                        if let n = v.as(Int.self) {
                            Text(NumberFormat.compact(n))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                }
            }
            .frame(height: 110)
        }
        .healthCard()
    }

    private func tooltip(for m: MinuteBucket) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(m.date, format: .dateTime.hour().minute())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
            Text("\(NumberFormat.grouped(m.tokens)) tokens")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}
