import SwiftUI
import Charts

struct SessionsPerDayCard: View {
    let sessions: [SessionsBucket]
    @State private var selectedDate: Date?

    private var last30: [SessionsBucket] { Array(sessions.suffix(30)) }
    private var totalSessions: Int { last30.reduce(0) { $0 + $1.count } }

    private func bucket(for date: Date) -> SessionsBucket? {
        let cal = Calendar.current
        return last30.first { cal.isDate($0.date, inSameDayAs: date) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeader(title: "Sessions — 30d",
                           symbol: "rectangle.stack",
                           info: "Number of distinct Claude Code sessions started per day. A session is one conversation; opening Claude Code in a new directory typically starts a new session.")
                Spacer(minLength: 0)
                Text("\(totalSessions)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            Chart {
                ForEach(last30) { s in
                    BarMark(
                        x: .value("Date", s.date, unit: .day),
                        y: .value("Sessions", s.count)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                    .cornerRadius(2)
                }
                if let selectedDate, let b = bucket(for: selectedDate) {
                    RuleMark(x: .value("Selected", b.date, unit: .day))
                        .foregroundStyle(Color.primary.opacity(0.25))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.date, format: .dateTime.month(.abbreviated).day())
                                    .font(.system(size: 10, weight: .semibold))
                                Text("\(b.count) session\(b.count == 1 ? "" : "s")")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                        }
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(.secondary)
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                }
            }
            .frame(height: 130)
        }
        .healthCard()
    }
}
