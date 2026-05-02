import Foundation
import AppKit
import ServiceManagement

/// Clean teardown — invoked from Settings → Advanced → "Uninstall ClaudeHealth…".
///
/// Wardle's KnockKnock would flag any "orphan" Login Item that points at a since-deleted
/// bundle. This makes sure we leave no such trails: unregister the SMAppService,
/// delete our Application Support dir + UserDefaults plist, then quit. The user is
/// then told to drag the .app to Trash.
@MainActor
enum Uninstall {

    /// Runs the destructive part of uninstall. Returns a human-readable summary for the
    /// caller to show in a follow-up alert.
    static func purge() -> String {
        var lines: [String] = []
        let fm = FileManager.default

        // 1. Unregister the Login Item if it was ever toggled on.
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                lines.append("• Login Item unregistered")
            } else {
                lines.append("• Login Item was not registered")
            }
        } catch {
            Log.security.error("Uninstall: SMAppService.unregister failed: \(String(describing: error).logSafe, privacy: .public)")
            lines.append("• Login Item unregister failed (non-fatal): \(error.localizedDescription)")
        }

        // 2. Remove our Application Support directory (cache.json + any future state).
        let appSupport = Cache.directory   // Application Support/ClaudeHealth
        if fm.fileExists(atPath: appSupport.path) {
            do {
                try fm.removeItem(at: appSupport)
                lines.append("• Removed \(appSupport.path)")
            } catch {
                lines.append("• Could not remove \(appSupport.path): \(error.localizedDescription)")
            }
        }

        // 3. Remove our UserDefaults plist (preferences: bubble origin, icon style,
        //    menu bar style, bubble metric, usage limit budget, limit events).
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
            UserDefaults.standard.synchronize()
            let prefsURL = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(bundleId).plist")
            if fm.fileExists(atPath: prefsURL.path) {
                try? fm.removeItem(at: prefsURL)
                lines.append("• Removed \(prefsURL.path)")
            } else {
                lines.append("• Removed UserDefaults domain \(bundleId)")
            }
        }

        // 4. Sealed-resources cache (cfprefsd may write a cached copy under ~/Library/Caches).
        let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "")
        if let cacheDir, fm.fileExists(atPath: cacheDir.path) {
            try? fm.removeItem(at: cacheDir)
            lines.append("• Removed \(cacheDir.path)")
        }

        Log.security.notice("uninstall completed")
        return lines.joined(separator: "\n")
    }

    /// Confirm via NSAlert, run purge(), show summary, then quit shortly after.
    static func showFlow() {
        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = "Uninstall ClaudeHealth?"
        confirm.informativeText = """
            This will:
              • Unregister the "Open at Login" item if enabled
              • Delete the cached aggregates at ~/Library/Application Support/ClaudeHealth/
              • Delete preferences at ~/Library/Preferences/com.max.ClaudeHealth.plist
              • Quit ClaudeHealth

            After that, drag ClaudeHealth.app from /Applications to the Trash to remove the bundle itself.

            This does NOT touch ~/.claude/projects/ — your Claude Code transcripts are untouched.
            """
        confirm.addButton(withTitle: "Uninstall")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let summary = purge()

        let done = NSAlert()
        done.alertStyle = .informational
        done.messageText = "ClaudeHealth — uninstall complete"
        done.informativeText = summary + "\n\nNow drag /Applications/ClaudeHealth.app to the Trash. The app will quit in a moment."
        done.addButton(withTitle: "Quit")
        _ = done.runModal()

        // Defer terminate slightly so Log.security.notice flushes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }
}
