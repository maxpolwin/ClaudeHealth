import SwiftUI

struct HourDayHeatmapCard: View {
    let hourDay: [[Double]]   // 7 rows (Sun..Sat) × 24 cols (0..23)

    private static let cellW: CGFloat = 16
    private static let cellH: CGFloat = 14
    private static let gap: CGFloat = 2

    @State private var hovered: (dow: Int, hour: Int)? = nil

    private var ceiling: Double {
        let flat = hourDay.flatMap { $0 }
        return flat.max() ?? 0
    }

    private var peak: (dow: Int, hour: Int, value: Double)? {
        var best: (Int, Int, Double)? = nil
        for d in 0..<7 {
            for h in 0..<24 {
                if hourDay[d][h] > (best?.2 ?? 0) {
                    best = (d, h, hourDay[d][h])
                }
            }
        }
        if let b = best, b.2 > 0 { return (b.0, b.1, b.2) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "When you code with Claude",
                       symbol: "clock",
                       info: "Average tokens by day-of-week (rows) and hour (columns). Brighter cells = more tokens at that time. Highlights when in the week you reach for Claude most.")
            grid
            HStack {
                if let h = hovered {
                    Text("\(weekdayName(h.dow)) at \(formatHour(h.hour)) — avg \(NumberFormat.grouped(Int(hourDay[h.dow][h.hour]))) tokens")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if let p = peak {
                    Text("Peak: \(weekdayName(p.dow)) at \(formatHour(p.hour))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .healthCard()
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            HStack(spacing: Self.gap) {
                Text("").frame(width: 24, alignment: .leading)
                ForEach(0..<24) { h in
                    Text(h % 3 == 0 ? "\(h)" : "")
                        .font(.system(size: 8))
                        .frame(width: Self.cellW, alignment: .center)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(0..<7) { dow in
                HStack(spacing: Self.gap) {
                    Text(weekdayShort(dow))
                        .font(.system(size: 9))
                        .frame(width: 24, alignment: .leading)
                        .foregroundStyle(.secondary)
                    ForEach(0..<24) { hour in
                        cell(dow: dow, hour: hour)
                    }
                }
            }
        }
    }

    private func cell(dow: Int, hour: Int) -> some View {
        let value = hourDay[dow][hour]
        let color = Palette.heatColor(for: value, ceiling: ceiling)
        let isHover = hovered?.dow == dow && hovered?.hour == hour
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            .frame(width: Self.cellW, height: Self.cellH)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(isHover ? Color.primary.opacity(0.4) : Color.clear, lineWidth: 0.8)
            )
            .onHover { hovering in
                if hovering { hovered = (dow, hour) }
                else if hovered?.dow == dow && hovered?.hour == hour { hovered = nil }
            }
            .help("\(weekdayName(dow)) at \(formatHour(hour)): avg \(NumberFormat.grouped(Int(value))) tokens")
    }

    private func weekdayShort(_ i: Int) -> String { ["S","M","T","W","T","F","S"][i] }
    private func weekdayName(_ i: Int) -> String { ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"][i] }
    private func formatHour(_ h: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "h a"
        var c = DateComponents()
        c.hour = h
        c.minute = 0
        if let d = Calendar.current.date(from: c) { return f.string(from: d) }
        return "\(h):00"
    }
}
