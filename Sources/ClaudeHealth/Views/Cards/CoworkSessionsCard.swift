import SwiftUI
import Charts

/// Surfaces Claude Desktop App agent-mode (Cowork) session activity. Shows session
/// COUNTS only — token counts aren't observable from the host (the agent runs in
/// a sandboxed VM whose data files don't surface).
struct CoworkSessionsCard: View {
    let sessions: [CoworkSessionInfo]
    let perDay: [SessionsBucket]

    private var last30: [SessionsBucket] { Array(perDay.suffix(30)) }
    private var totalLast30: Int { last30.reduce(0) { $0 + $1.count } }

    private var todayCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return perDay.first(where: { $0.date == today })?.count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeader(
                    title: "Desktop agent sessions",
                    symbol: "macwindow.on.rectangle",
                    info: "Claude Desktop App agent-mode (\"Cowork\") sessions. Session counts only — token totals aren't visible to ClaudeHealth (the agent runs in a sandboxed VM). For full token usage including web/desktop chat, see your Anthropic plan dashboard via Settings → Help."
                )
                Spacer(minLength: 0)
                if totalLast30 > 0 {
                    Text("\(totalLast30) in 30d")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if sessions.isEmpty {
                empty
            } else {
                content
            }
        }
        .healthCard()
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No agent sessions found")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("If you use the Claude Desktop App's agent mode (Cowork), sessions will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(todayCount)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(todayCount == 1 ? "session today" : "sessions today")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if !last30.isEmpty {
                Chart(last30) { s in
                    BarMark(
                        x: .value("Date", s.date, unit: .day),
                        y: .value("Sessions", s.count)
                    )
                    .foregroundStyle(Palette.brand.opacity(0.85))
                    .cornerRadius(2)
                }
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
                .frame(height: 80)
            }

            // Recent sessions list (top 5)
            if !sessions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECENT")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.tertiary)
                    ForEach(Array(sessions.prefix(5))) { s in
                        recentRow(s)
                    }
                }
            }
        }
    }

    private func recentRow(_ s: CoworkSessionInfo) -> some View {
        HStack(spacing: 8) {
            Text(s.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(ModelDisplay.name(for: s.model))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(relativeTime(s.lastActivityAt))
                .font(.system(size: 10, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)
        }
    }

    private func relativeTime(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}
