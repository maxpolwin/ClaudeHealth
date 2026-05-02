import AppKit
import Foundation

/// User-pickable app icon. Each variant ships a separate .icns in the bundle.
enum IconStyle: String, CaseIterable, Identifiable {
    case pulse, rings, bars
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pulse: return "Pulse"
        case .rings: return "Rings"
        case .bars:  return "Bars"
        }
    }

    var resourceName: String { "AppIcon-\(rawValue)" }

    /// Loads the multi-resolution .icns from the app bundle.
    var image: NSImage? {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "icns") else {
            Log.appearance.error("missing \(self.resourceName, privacy: .public).icns in bundle")
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

/// What the floating bubble shows in its center label.
enum BubbleMetric: String, CaseIterable, Identifiable {
    case today, week, month, velocity
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today:    return "Today"
        case .week:     return "Last 7 days"
        case .month:    return "Last 30 days"
        case .velocity: return "Velocity (live)"
        }
    }

    /// Pull the right number out of the aggregates for this metric. Velocity
    /// auto-switches to per-second display when the rate is ≥ 1 token/sec,
    /// otherwise falls back to per-minute. When `realWorkOnly` is true, all
    /// numbers come from the input+output-only series (excludes cache reads),
    /// matching what Anthropic's chat UI displays.
    func value(from agg: Aggregates, realWorkOnly: Bool = false) -> Int {
        switch self {
        case .today:
            return realWorkOnly ? agg.realWorkToday : agg.todayTokens
        case .week:
            return realWorkOnly ? agg.realWorkLast7 : agg.last7Tokens
        case .month:
            return realWorkOnly ? agg.realWorkLast30 : agg.last30Tokens
        case .velocity:
            let vpm = realWorkOnly ? agg.realWorkLiveVelocityPerMinute
                                   : agg.liveVelocityPerMinute
            let perSec = vpm / 60.0
            return perSec >= 1.0 ? Int(perSec.rounded()) : Int(vpm.rounded())
        }
    }

    /// Short label rendered under the value inside the bubble. For velocity,
    /// this is unit-aware ("/ sec" vs "/ min") so it tracks the current value.
    func shortLabel(from agg: Aggregates, realWorkOnly: Bool = false) -> String {
        switch self {
        case .today: return "today"
        case .week:  return "7-day"
        case .month: return "30-day"
        case .velocity:
            let vpm = realWorkOnly ? agg.realWorkLiveVelocityPerMinute
                                   : agg.liveVelocityPerMinute
            return (vpm / 60.0) >= 1.0 ? "/ sec" : "/ min"
        }
    }

    /// "Typical" value used as ring-fill baseline so the bubble always reads as
    /// 0…1 for the chosen metric. For 30-day, baseline equals the value.
    /// For velocity, baseline matches the current display unit so the ring
    /// scales smoothly across the auto-switch boundary.
    func baseline(from agg: Aggregates, realWorkOnly: Bool = false) -> Double {
        // The "typical" baseline still uses the all-tokens avg in fallback modes;
        // when realWork is on, divide it by ~50 to approximate the input+output
        // share (since real-work is ~2 % of the all-tokens total in practice).
        // This keeps the ring scale meaningful in both modes.
        let avgPerDay = max(1.0, agg.thirtyDayDailyAverage * (realWorkOnly ? 0.02 : 1.0))
        switch self {
        case .today: return avgPerDay
        case .week:  return avgPerDay * 7
        case .month:
            let monthVal = realWorkOnly ? agg.realWorkLast30 : agg.last30Tokens
            return max(1.0, Double(monthVal))
        case .velocity:
            let vpm = realWorkOnly ? agg.realWorkLiveVelocityPerMinute
                                   : agg.liveVelocityPerMinute
            let perSec = vpm / 60.0
            return perSec >= 1.0
                ? max(1.0, avgPerDay / (24.0 * 60.0 * 60.0))
                : max(1.0, avgPerDay / (24.0 * 60.0))
        }
    }
}

/// User-pickable menu bar SF Symbol. Always rendered as a template image so
/// macOS tints it to match the menu-bar appearance.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case waveform, gauge, chartBar
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .waveform: return "Waveform"
        case .gauge:    return "Gauge"
        case .chartBar: return "Bars"
        }
    }

    var symbolName: String {
        switch self {
        case .waveform: return "waveform.path.ecg"
        case .gauge:    return "gauge.with.dots.needle.bottom.50percent"
        case .chartBar: return "chart.bar.fill"
        }
    }
}

/// Persistence + change-broadcast for appearance choices.
@MainActor
enum Appearance {
    static let iconKey               = "ClaudeHealth.iconStyle"
    static let menuBarKey            = "ClaudeHealth.menuBarStyle"
    static let bubbleMetricKey       = "ClaudeHealth.bubbleMetric"
    static let bubbleRealWorkOnlyKey = "ClaudeHealth.bubbleRealWorkOnly"

    /// Posted whenever any appearance preference changes.
    static let didChange = Notification.Name("ClaudeHealth.appearanceDidChange")

    static var iconStyle: IconStyle {
        get {
            IconStyle(rawValue: UserDefaults.standard.string(forKey: iconKey) ?? "") ?? .pulse
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: iconKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static var menuBarStyle: MenuBarStyle {
        get {
            MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: menuBarKey) ?? "") ?? .waveform
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: menuBarKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static var bubbleMetric: BubbleMetric {
        get {
            BubbleMetric(rawValue: UserDefaults.standard.string(forKey: bubbleMetricKey) ?? "") ?? .today
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: bubbleMetricKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// When true, the floating bubble (and its velocity reading) shows only
    /// "real work" tokens — input + output, excluding cache reads/creates —
    /// matching the numbers Anthropic's chat UI surfaces. Default OFF: bubble
    /// shows the full all-tokens count (billing reality).
    static var bubbleRealWorkOnly: Bool {
        get { UserDefaults.standard.bool(forKey: bubbleRealWorkOnlyKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: bubbleRealWorkOnlyKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}
