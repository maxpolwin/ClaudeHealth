import SwiftUI

@main
struct ClaudeHealthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Earliest hook — runs before AppDelegate.applicationDidFinishLaunching.
        // No-op in Debug so Xcode debugging still works.
        AntiDebug.applyIfRelease()
    }

    var body: some Scene {
        // No SwiftUI Scenes — windows are managed manually by AppDelegate so we get
        // full NSPanel control (level, collection behavior, materials). The required
        // Settings scene is left empty; the in-app Settings is opened from the
        // status item / bubble context menu.
        Settings { EmptyView() }
    }
}
