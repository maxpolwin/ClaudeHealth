import SwiftUI
import AppKit

struct DashboardView: View {
    @Bindable var store: DataStore

    var body: some View {
        let agg = store.aggregates
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                HeroRingCard(aggregates: agg)

                InsightCard(store: store)

                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        SummaryCard(title: "Today", symbol: "sun.max.fill",
                                    value: agg.todayTokens, previous: 0,
                                    tint: .accentColor,
                                    info: "Total tokens (input + output + cache) used today.")
                        SummaryCard(title: "7-day", symbol: "calendar",
                                    value: agg.last7Tokens, previous: agg.prev7Tokens,
                                    tint: .blue,
                                    info: "Tokens used in the last 7 days. Delta compares against the previous 7 days.")
                        SummaryCard(title: "30-day", symbol: "calendar",
                                    value: agg.last30Tokens, previous: agg.prev30Tokens,
                                    tint: .indigo,
                                    info: "Tokens used in the last 30 days. Delta compares against the previous 30 days.")
                    }
                }

                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        VelocityCard(minutely: agg.minutelyLast60,
                                     velocityPerMinute: agg.velocityPerMinute,
                                     liveVelocityPerMinute: agg.liveVelocityPerMinute,
                                     tokensLast15min: agg.tokensLast15min)
                        UsageLimitCard(tokensLast5h: agg.tokensLast5h,
                                       budget: store.usageLimitBudget,
                                       progress: store.usageLimitProgress,
                                       recentEventCount: recentEventCount)
                    }
                }

                StreakCard(current: agg.currentStreakDays, longest: agg.longestStreakDays)

                HourDayHeatmapCard(hourDay: agg.hourDay)

                DailyStackedBarCard(daily: agg.daily)

                YearHeatmapCard(daily: agg.daily)

                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        ProjectBreakdownCard(projects: agg.byProject)
                        ModelDonutCard(models: agg.byModel)
                    }
                    GridRow {
                        CacheRatioCard(daily: agg.daily)
                        SessionsPerDayCard(sessions: agg.sessionsPerDay)
                    }
                }

                CoworkSessionsCard(
                    sessions: agg.recentCoworkSessions,
                    perDay: agg.coworkSessionsPerDay
                )

                footer
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                // Subtle warm wash matching the Pulse icon's cream surface — auto-blends in dark mode.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.brand.opacity(0.045))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var recentEventCount: Int {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        return store.limitEvents.filter { $0.timestamp >= cutoff }.count
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ClaudeHealth")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text(formattedDate(store.aggregates.generatedAt))
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .help("Refresh now (⌘R)")
                .keyboardShortcut("r", modifiers: .command)

                ShareButton(store: store)
                    .help("Share dashboard as PNG")
            }
        }
        .padding(.bottom, 4)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(store.aggregates.totalRecords) records · \(store.aggregates.totalFiles) files · parsed in \(store.aggregates.parseDurationMs) ms")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            if store.usageLimitBudget > 0 {
                Text("5h: \(NumberFormat.grouped(store.aggregates.tokensLast5h)) / \(NumberFormat.grouped(store.usageLimitBudget))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 8)
    }

    private func formattedDate(_ d: Date) -> String {
        guard d > .distantPast else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return "Updated \(f.string(from: d))"
    }
}

/// Standalone share button to avoid embedding NSViewRepresentable noise in DashboardView.
struct ShareButton: View {
    let store: DataStore

    var body: some View {
        ShareAnchor { view in
            let snapshot = DashboardView(store: store)
                .frame(width: 760, height: 1200)   // fixed for predictable export
            Sharing.share(view: snapshot, anchor: view)
        }
    }
}

/// Embeds a real NSView into SwiftUI so NSSharingServicePicker can anchor to it.
struct ShareAnchor: NSViewRepresentable {
    final class HostView: NSView {
        var onShare: ((NSView) -> Void)?
        override func mouseDown(with event: NSEvent) {
            onShare?(self)
        }
    }

    let onShare: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let host = HostView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        host.onShare = onShare
        // SwiftUI image inside an NSHostingView, layered into the HostView so the click target is the NSView.
        let icon = NSHostingView(rootView:
            Image(systemName: "square.and.arrow.up")
                .imageScale(.medium)
                .foregroundStyle(.secondary)
        )
        icon.frame = host.bounds
        icon.autoresizingMask = [.width, .height]
        host.addSubview(icon)
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
