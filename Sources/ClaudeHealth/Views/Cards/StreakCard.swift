import SwiftUI

struct StreakCard: View {
    let current: Int
    let longest: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Streak",
                       symbol: "flame.fill",
                       tint: .orange,
                       info: "Consecutive days with at least one Claude turn. The streak holds today if you've used Claude today, otherwise it counts back from yesterday.")
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, .red],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .symbolEffect(.pulse, options: .repeating, isActive: current > 0)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(current) day\(current == 1 ? "" : "s")")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("Current streak")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(longest)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text("Longest")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .healthCard()
    }
}
