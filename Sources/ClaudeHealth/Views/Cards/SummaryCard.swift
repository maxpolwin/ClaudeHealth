import SwiftUI

struct SummaryCard: View {
    let title: String
    let symbol: String
    let value: Int
    let previous: Int           // for delta calc; pass 0 to hide
    let tint: Color
    let info: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: title, symbol: symbol, tint: tint, info: info)
            Text(NumberFormat.compact(value))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
            if previous > 0 {
                let delta = (Double(value) - Double(previous)) / Double(previous)
                let color: Color = delta >= 0 ? Palette.brand : Palette.brandDeep
                HStack(spacing: 4) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(NumberFormat.compactPercent(abs(delta)))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("vs prior period")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(color)
            } else {
                Text("\(NumberFormat.grouped(value)) tokens")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .healthCard()
    }
}
