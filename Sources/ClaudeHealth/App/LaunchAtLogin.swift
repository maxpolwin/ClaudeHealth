import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` for "Open at Login" toggling.
/// Requires the .app to be in /Applications (or another approved location)
/// with a stable bundle identifier — both of which we have.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            Log.launch.error("\(String(describing: error), privacy: .public)")
        }
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .notRegistered:    return "Off"
        case .enabled:          return "On"
        case .requiresApproval: return "Needs approval in System Settings"
        case .notFound:         return "Service not found"
        @unknown default:       return "Unknown"
        }
    }
}
