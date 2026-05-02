import SwiftUI
import Charts

struct DailyStackedBarCard: View {
    let daily: [DailyBucket]

    @State private var selectedDate: Date?

    private struct StackEntry: Identifiable {
        let id: String
        let date: Date
        let category: String
        let tokens: Int
    }

    private var last30: [DailyBucket] { Array(daily.suffix(30)) }

    private var data: [StackEntry] {
        var out: [StackEntry] = []
        out.reserveCapacity(last30.count * 4)
        for d in last30 {
            let key = ISO8601DateFormatter().string(from: d.date)
            out.append(StackEntry(id: key + "-output",     date: d.date, category: "Output",      tokens: d.outputTokens))
            out.append(StackEntry(id: key + "-input",      date: d.date, category: "Input",       tokens: d.inputTokens))
            out.append(StackEntry(id: key + "-cacheWrite", date: d.date, category: "Cache write", tokens: d.cacheCreationTokens))
            out.append(StackEntry(id: key + "-cacheRead",  date: d.date, category: "Cache read",  tokens: d.cacheReadTokens))
        }
        return out
    }

    private func bucket(for selected: Date) -> DailyBucket? {
        let cal = Calendar.current
        return last30.first { cal.isDate($0.date, inSameDayAs: selected) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Daily tokens — last 30 days",
                       symbol: "chart.bar.fill",
                       info: "Tokens per day broken into Input, Output, Cache write, and Cache read. Cache read = tokens served from Claude's prompt cache (cheaper, faster — repeated context being reused). Hover a bar for the exact daily breakdown.")
            Chart {
                ForEach(data) { entry in
                    BarMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Tokens", entry.tokens)
                    )
                    .foregroundStyle(by: .value("Type", entry.category))
                    .cornerRadius(2)
                }
                if let selectedDate, let b = bucket(for: selectedDate) {
                    RuleMark(x: .value("Selected", b.date, unit: .day))
                        .foregroundStyle(Color.primary.opacity(0.25))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            tooltip(for: b)
                        }
                }
            }
            .chartForegroundStyleScale([
                "Output":      Palette.output,
                "Input":       Palette.input,
                "Cache write": Palette.cacheWrite,
                "Cache read":  Palette.cacheRead
            ])
            .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(),
                                   centered: false)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel {
                        if let n = v.as(Int.self) {
                            Text(NumberFormat.compact(n))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 220)
        }
        .healthCard()
    }

    private func tooltip(for b: DailyBucket) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(b.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
            Divider().padding(.vertical, 1)
            row("Output",      value: b.outputTokens,         color: Palette.output)
            row("Input",       value: b.inputTokens,          color: Palette.input)
            row("Cache write", value: b.cacheCreationTokens,  color: Palette.cacheWrite)
            row("Cache read",  value: b.cacheReadTokens,      color: Palette.cacheRead)
            Divider().padding(.vertical, 1)
            HStack {
                Text("Total")
                    .font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 8)
                Text(NumberFormat.grouped(b.totalTokens))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(width: 180, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func row(_ name: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(NumberFormat.compact(value))
                .font(.system(size: 10, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}
