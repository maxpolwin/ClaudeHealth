import SwiftUI
import Charts

struct CacheRatioCard: View {
    let daily: [DailyBucket]
    @State private var selectedDate: Date?

    private var last30: [DailyBucket] { Array(daily.suffix(30)) }

    private var avgRatio: Double {
        let withData = last30.filter { ($0.cacheReadTokens + $0.inputTokens) > 0 }
        guard !withData.isEmpty else { return 0 }
        return withData.map(\.cacheHitRatio).reduce(0, +) / Double(withData.count)
    }

    private func bucket(for date: Date) -> DailyBucket? {
        let cal = Calendar.current
        return last30.first { cal.isDate($0.date, inSameDayAs: date) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeader(title: "Cache hit ratio — 30d",
                           symbol: "bolt.fill",
                           tint: .green,
                           info: "Tokens served from prompt cache ÷ total input tokens. Higher = more of your context is being reused, which is cheaper and faster. Hover any point for the daily ratio.")
                Spacer(minLength: 0)
                Text(NumberFormat.percent(avgRatio))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            Chart {
                ForEach(last30) { d in
                    AreaMark(
                        x: .value("Date", d.date, unit: .day),
                        y: .value("Ratio", d.cacheHitRatio)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [Color.green.opacity(0.35), Color.green.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Date", d.date, unit: .day),
                        y: .value("Ratio", d.cacheHitRatio)
                    )
                    .foregroundStyle(Color.green)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                if let selectedDate, let b = bucket(for: selectedDate) {
                    RuleMark(x: .value("Selected", b.date, unit: .day))
                        .foregroundStyle(Color.primary.opacity(0.25))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.date, format: .dateTime.month(.abbreviated).day())
                                    .font(.system(size: 10, weight: .semibold))
                                Text(NumberFormat.percent(b.cacheHitRatio))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.green)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                        }
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYScale(domain: 0...1)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 0.25, 0.5, 0.75, 1.0]) { v in
                    AxisValueLabel {
                        if let r = v.as(Double.self) {
                            Text(NumberFormat.percent(r))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                }
            }
            .frame(height: 130)
        }
        .healthCard()
    }
}
