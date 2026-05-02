import SwiftUI

struct YearHeatmapCard: View {
    let daily: [DailyBucket]

    private static let cellSize: CGFloat = 11
    private static let cellGap: CGFloat = 3
    private static let weeks = 53

    @State private var hoveredDate: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Year activity",
                       symbol: "calendar",
                       info: "Each square is one day. Brighter color = more total tokens that day. The most recent week is on the right. Hover any cell for the exact value.")
            HStack(alignment: .top, spacing: 8) {
                weekdayLabels
                grid
            }
            HStack(spacing: 8) {
                if let date = hoveredDate, let bucket = bucket(for: date) {
                    Text(formattedDate(date))
                        .font(.system(size: 11, weight: .medium))
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(NumberFormat.grouped(bucket.totalTokens)) tokens")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Hover a day for details")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                legend
            }
        }
        .healthCard()
    }

    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: Self.cellGap) {
            ForEach(0..<7) { idx in
                Text(weekdayShort(idx))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: Self.cellSize, alignment: .trailing)
                    .opacity(idx % 2 == 1 ? 1 : 0)
            }
        }
    }

    private var grid: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let map: [Date: DailyBucket] = Dictionary(uniqueKeysWithValues: daily.map { ($0.date, $0) })
        let maxTokens = (daily.map(\.totalTokens).max() ?? 1)

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Self.cellGap) {
                    ForEach(0..<Self.weeks, id: \.self) { weekOffset in
                        let weeksFromNow = (Self.weeks - 1) - weekOffset
                        VStack(spacing: Self.cellGap) {
                            ForEach(0..<7) { dow in
                                let date = dateFor(weeksFromNow: weeksFromNow, dow: dow, today: today)
                                let bucket = map[date]
                                let tokens = Double(bucket?.totalTokens ?? 0)
                                cell(for: date, tokens: tokens, ceiling: Double(maxTokens),
                                     isFuture: date > today)
                            }
                        }
                        .id(weekOffset)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear {
                // Snap to the most recent week — without this the ScrollView opens at
                // the leftmost (52-weeks-ago) edge and the user sees only blank cells.
                proxy.scrollTo(Self.weeks - 1, anchor: .trailing)
            }
        }
    }

    private func cell(for date: Date, tokens: Double, ceiling: Double, isFuture: Bool) -> some View {
        let color: Color = isFuture
            ? Color.primary.opacity(0.04)
            : Palette.heatColor(for: tokens, ceiling: ceiling)
        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color)
            .frame(width: Self.cellSize, height: Self.cellSize)
            .overlay(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(hoveredDate == date ? Color.primary.opacity(0.4) : Color.clear,
                                  lineWidth: 0.8)
            )
            .onHover { hovering in
                hoveredDate = hovering ? date : (hoveredDate == date ? nil : hoveredDate)
            }
            .help(isFuture ? "" : "\(formattedDate(date)): \(NumberFormat.grouped(Int(tokens))) tokens")
            .accessibilityLabel("\(formattedDate(date)): \(Int(tokens)) tokens")
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less").font(.system(size: 9)).foregroundStyle(.secondary)
            ForEach(Palette.heatLevels.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Palette.heatLevels[i])
                    .frame(width: 10, height: 10)
            }
            Text("More").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private func bucket(for date: Date) -> DailyBucket? {
        daily.first { $0.date == date }
    }

    private func dateFor(weeksFromNow: Int, dow: Int, today: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1
        let todayDow = (cal.component(.weekday, from: today) - 1)
        let mostRecentSunday = cal.date(byAdding: .day, value: -todayDow, to: today)!
        let weekStart = cal.date(byAdding: .day, value: -7 * weeksFromNow, to: mostRecentSunday)!
        return cal.date(byAdding: .day, value: dow, to: weekStart)!
    }

    private func weekdayShort(_ idx: Int) -> String {
        ["S","M","T","W","T","F","S"][idx]
    }

    private func formattedDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }
}
