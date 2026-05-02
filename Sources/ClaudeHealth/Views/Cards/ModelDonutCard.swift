import SwiftUI
import Charts

struct ModelDonutCard: View {
    let models: [ModelBucket]
    @State private var selectedTokens: Int?

    private var total: Int {
        models.reduce(0) { $0 + $1.totalTokens }
    }

    private var palette: [String: Color] {
        var p: [String: Color] = [:]
        for m in models {
            let name = m.displayName.lowercased()
            if name.hasPrefix("opus")        { p[m.model] = .purple }
            else if name.hasPrefix("sonnet") { p[m.model] = .blue }
            else if name.hasPrefix("haiku")  { p[m.model] = .green }
            else                              { p[m.model] = .gray }
        }
        return p
    }

    /// The model whose cumulative band contains `selectedTokens`.
    private var selectedModel: ModelBucket? {
        guard let selectedTokens else { return nil }
        var running = 0
        for m in models {
            running += m.totalTokens
            if selectedTokens <= running { return m }
        }
        return models.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "By model",
                       symbol: "cpu",
                       info: "Token share between model families (Opus / Sonnet / Haiku). Hover a slice or legend item for the exact token count.")
            HStack(spacing: 16) {
                ZStack {
                    Chart(models) { m in
                        SectorMark(
                            angle: .value("Tokens", m.totalTokens),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .foregroundStyle(palette[m.model] ?? .gray)
                        .opacity(selectedModel == nil || selectedModel?.id == m.id ? 1.0 : 0.45)
                        .cornerRadius(2)
                    }
                    .chartAngleSelection(value: $selectedTokens)
                    .frame(width: 120, height: 120)
                    if let m = selectedModel {
                        VStack(spacing: 2) {
                            Text(m.displayName)
                                .font(.system(size: 10, weight: .semibold))
                            Text(NumberFormat.compact(m.totalTokens))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            if total > 0 {
                                Text(NumberFormat.percent(Double(m.totalTokens) / Double(total)))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(models) { m in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(palette[m.model] ?? .gray)
                                .frame(width: 8, height: 8)
                            Text(m.displayName)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(NumberFormat.compact(m.totalTokens))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .help("\(m.displayName): \(NumberFormat.grouped(m.totalTokens)) tokens")
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .healthCard()
    }
}
