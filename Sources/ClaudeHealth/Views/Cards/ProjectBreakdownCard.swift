import SwiftUI

struct ProjectBreakdownCard: View {
    let projects: [ProjectBucket]

    private var top: [ProjectBucket] {
        let topN = 7
        let sorted = projects.sorted { $0.totalTokens > $1.totalTokens }
        if sorted.count <= topN { return sorted }
        let head = Array(sorted.prefix(topN))
        let tailTokens = sorted.dropFirst(topN).reduce(0) { $0 + $1.totalTokens }
        return head + [ProjectBucket(projectKey: "__other__", displayName: "Other",
                                     totalTokens: tailTokens)]
    }

    private var maxTokens: Int { top.map(\.totalTokens).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "By project",
                       symbol: "folder",
                       info: "Tokens consumed per project, summed across all sessions in that working directory. Worktrees are listed separately from their main project.")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(top) { p in
                    row(p)
                }
            }
        }
        .healthCard()
    }

    private func row(_ p: ProjectBucket) -> some View {
        let ratio = CGFloat(p.totalTokens) / CGFloat(max(1, maxTokens))
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(p.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(NumberFormat.compact(p.totalTokens))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06)).frame(height: 6)
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.brandWarm, Palette.brand],
                                              startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(2, geo.size.width * ratio), height: 6)
                }
            }
            .frame(height: 6)
            .help("\(p.displayName): \(NumberFormat.grouped(p.totalTokens)) tokens")
        }
    }
}
