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
    /// otherwise falls back to per-minute (so it never reads "0 / sec" while
    /// there's actually something happening).
    func value(from agg: Aggregates) -> Int {
        switch self {
        case .today:    return agg.todayTokens
        case .week:     return agg.last7Tokens
        case .month:    return agg.last30Tokens
        case .velocity:
            let perSec = agg.liveVelocityPerMinute / 60.0
            return perSec >= 1.0
                ? Int(perSec.rounded())
                : Int(agg.liveVelocityPerMinute.rounded())
        }
    }

    /// Short label rendered under the value inside the bubble. For velocity,
    /// this is unit-aware ("/ sec" vs "/ min") so it tracks the current value.
    func shortLabel(from agg: Aggregates) -> String {
        switch self {
        case .today: return "today"
        case .week:  return "7-day"
        case .month: return "30-day"
        case .velocity:
            return (agg.liveVelocityPerMinute / 60.0) >= 1.0 ? "/ sec" : "/ min"
        }
    }

    /// "Typical" value used as ring-fill baseline so the bubble always reads as
    /// 0…1 for the chosen metric. For 30-day, baseline equals the value.
    /// For velocity, baseline matches the current display unit so the ring
    /// scales smoothly across the auto-switch boundary.
    func baseline(from agg: Aggregates) -> Double {
        let avgPerDay = max(1.0, agg.thirtyDayDailyAverage)
        switch self {
        case .today: return avgPerDay
        case .week:  return avgPerDay * 7
        case .month: return max(1.0, Double(agg.last30Tokens))
        case .velocity:
            let perSec = agg.liveVelocityPerMinute / 60.0
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
    static let iconKey         = "ClaudeHealth.iconStyle"
    static let menuBarKey      = "ClaudeHealth.menuBarStyle"
    static let bubbleMetricKey = "ClaudeHealth.bubbleMetric"

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
}
