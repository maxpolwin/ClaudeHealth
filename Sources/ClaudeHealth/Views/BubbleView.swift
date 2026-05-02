import SwiftUI
import AppKit

struct BubbleView: View {
    @Bindable var store: DataStore
    let onPrimaryAction: () -> Void
    let onShowSettings: () -> Void

    @State private var isHovering = false
    @State private var bubbleMetric: BubbleMetric = Appearance.bubbleMetric
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Raw activity progress (0…∞). When the user has set a daily token budget,
    /// this is `today / dailyLimit` and is allowed to exceed 1 (overflow visualised
    /// as a second inner ring, Apple-Activity style — but capped at 1 stacked overflow).
    /// When no daily budget is set, falls back to "today vs 30-day average" and is
    /// hard-capped at 1.0 (no overflow rendering — that would mean "you did more than
    /// average," which isn't a thing to alarm-stack about).
    private var activityProgress: Double {
        let agg = store.aggregates
        if store.usageLimitDaily > 0 {
            return Double(agg.todayTokens) / Double(store.usageLimitDaily)
        }
        let value = Double(bubbleMetric.value(from: agg))
        let baseline = bubbleMetric.baseline(from: agg)
        // Cap at 1.0 in fallback mode — no overflow stacking.
        return min(1.0, value / max(1, baseline))
    }

    /// Whether to render the second-arc overflow ring (only meaningful when a
    /// daily limit is set AND the user has crossed 100% of it).
    private var hasOverflow: Bool { store.usageLimitDaily > 0 && activityProgress > 1.0 }

    /// 0..1 fill of the OUTER ring — at most fully filled.
    private var outerArcFill: Double { min(1.0, activityProgress) }

    /// 0..1 fill of the INNER overflow ring. Apple-Activity style: shows how
    /// far into the SECOND lap you are; saturates at 1.0 if you've crossed 200%.
    private var overflowArcFill: Double { min(1.0, activityProgress - 1.0) }

    /// Usage-limit progress: 0…1+. Drives ring color (orange → amber → red).
    private var limitProgress: Double { store.usageLimitProgress }

    /// Color shifts within the warm Claude family as the limit approaches:
    /// brand orange → warm amber → systemRed. Keeps the bubble visually consistent
    /// with the rest of the UI while still signalling "stop" at saturation.
    private var ringColor: Color { Palette.limitColor(progress: limitProgress) }

    private var isOverLimit: Bool { limitProgress >= 1.0 && store.usageLimitBudget > 0 }

    private var metricBinding: Binding<BubbleMetric> {
        Binding(
            get: { bubbleMetric },
            set: { newValue in
                bubbleMetric = newValue
                Appearance.bubbleMetric = newValue
            }
        )
    }

    var body: some View {
        let agg = store.aggregates
        let displayedValue = bubbleMetric.value(from: agg)

        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )

            // Faint full-circle track (always visible).
            Circle()
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 4))
                .padding(5)

            // Outer arc: 0 → min(1, progress). The "first lap."
            Circle()
                .trim(from: 0, to: CGFloat(outerArcFill))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [ringColor.opacity(0.55), ringColor]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(5)
                .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.78), value: outerArcFill)
                .animation(reduceMotion ? .none : .easeInOut(duration: 0.4), value: ringColor)

            // Apple-Activity-style overflow: a SINGLE inner ring stacked when you
            // cross your daily goal. Saturates at 100% of the inner ring (= 200% of
            // your day) — beyond that we only pulse, never stack more rings (would
            // collapse visually inside a 72-pt bubble).
            if hasOverflow {
                Circle()
                    .stroke(Color(NSColor.systemRed).opacity(0.10),
                            style: StrokeStyle(lineWidth: 3))
                    .padding(11)
                Circle()
                    .trim(from: 0, to: CGFloat(overflowArcFill))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [ringColor.opacity(0.7),
                                                        Color(NSColor.systemRed)]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(11)
                    .animation(reduceMotion ? .none : .spring(response: 0.30, dampingFraction: 0.78),
                               value: overflowArcFill)
            }

            // Over-limit pulse — saturated red end of the warm gradient.
            if isOverLimit {
                Circle()
                    .stroke(Color(NSColor.systemRed), lineWidth: 2)
                    .padding(5)
                    .opacity(0.7)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isOverLimit)
            }

            VStack(spacing: 0) {
                Text(NumberFormat.compact(displayedValue))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    // Snappier transition so live updates feel as responsive as velocity does.
                    .contentTransition(.numericText(value: Double(displayedValue)))
                    .animation(reduceMotion ? .none : .spring(response: 0.20, dampingFraction: 0.85), value: displayedValue)
                Text(bubbleMetric.shortLabel(from: agg))
                    .font(.system(size: 8, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 6)

            if store.isRefreshing {
                Circle()
                    .stroke(ringColor.opacity(0.35), lineWidth: 1)
                    .padding(2)
                    .opacity(0.6)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: store.isRefreshing)
            }
        }
        .frame(width: 72, height: 72)
        .scaleEffect(isHovering ? 1.06 : 1.0)
        .shadow(color: .black.opacity(isHovering ? 0.22 : 0.16),
                radius: isHovering ? 14 : 10, x: 0, y: 4)
        .animation(reduceMotion ? .none : .spring(response: 0.30, dampingFraction: 0.72), value: isHovering)
        // Outer transparent frame matches the (larger) NSPanel bounds — gives
        // the .shadow() above room to render without being clipped square at
        // the panel edges. The NSPanel is `bubbleVisualSide + 2*bubblePadding`
        // wide, so this view fills it entirely.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Circle())
        .onHover { isHovering = $0 }
        .onTapGesture { onPrimaryAction() }
        .onReceive(NotificationCenter.default.publisher(for: Appearance.didChange)) { _ in
            // Settings or another menu changed the metric — sync our local @State.
            let latest = Appearance.bubbleMetric
            if latest != bubbleMetric { bubbleMetric = latest }
        }
        .help(tooltipText(for: agg))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bubbleMetric.displayName): \(displayedValue) tokens")
        .accessibilityHint("Click to open dashboard. Right-click for menu.")
        .contextMenu {
            Button {
                onPrimaryAction()
            } label: {
                Label("Show Dashboard", systemImage: "chart.bar.xaxis")
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Label("Refresh Now", systemImage: "arrow.clockwise")
            }
            Divider()

            Picker(selection: metricBinding) {
                ForEach(BubbleMetric.allCases) { m in
                    Text(m.displayName).tag(m)
                }
            } label: {
                Label("Bubble shows", systemImage: "rectangle.stack")
            }

            Divider()
            Button {
                onShowSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            Divider()
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Quit ClaudeHealth", systemImage: "power")
            }
        }
    }

    private func tooltipText(for agg: Aggregates) -> String {
        let today = NumberFormat.grouped(agg.todayTokens)
        let week  = NumberFormat.grouped(agg.last7Tokens)
        let month = NumberFormat.grouped(agg.last30Tokens)
        let vmin  = NumberFormat.grouped(Int(agg.velocityPerMinute.rounded()))
        var lines = [
            "Showing: \(bubbleMetric.displayName)",
            "Today: \(today)  •  7-day: \(week)  •  30-day: \(month)",
            "Velocity: \(vmin) / min"
        ]
        if store.usageLimitDaily > 0 {
            let dailyPct = Double(agg.todayTokens) / Double(store.usageLimitDaily)
            lines.append("Daily ring: \(today) / \(NumberFormat.grouped(store.usageLimitDaily)) — \(NumberFormat.compactPercent(dailyPct))")
        }
        if store.usageLimitBudget > 0 {
            lines.append("5h: \(NumberFormat.grouped(agg.tokensLast5h)) / \(NumberFormat.grouped(store.usageLimitBudget)) — \(NumberFormat.compactPercent(limitProgress))")
        }
        return lines.joined(separator: "\n")
    }
}
