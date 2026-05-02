import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let store = DataStore()
    private var bubbleController: BubbleWindowController?
    private var dashboardController: DashboardWindowController?
    private var settingsController: SettingsWindowController?
    private var confettiController: ConfettiWindowController?
    private var statusItem: NSStatusItem?
    private var appearanceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Wardle-style runtime tamper checks. Fast (≈10ms total).
        runSecurityChecks()

        // Apply persisted appearance on launch.
        applyIconStyle()

        bubbleController = BubbleWindowController(
            store: store,
            onPrimaryAction: { [weak self] anchor in self?.toggleDashboard(anchoredTo: anchor) },
            onShowSettings:  { [weak self] in self?.showSettings() }
        )
        bubbleController?.show()

        installStatusItem()
        applyMenuBarStyle()

        confettiController = ConfettiWindowController(duration: 5.0)

        store.onConfettiTrigger = { [weak self] in
            self?.confettiController?.celebrate()
        }

        // React to user changing icon / menu-bar style in Settings.
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: Appearance.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyIconStyle()
                self?.applyMenuBarStyle()
            }
        }
    }

    deinit {
        if let o = appearanceObserver { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Security checks (called once on launch)

    private func runSecurityChecks() {
        // 1. dyld injection env-var audit. Hardened runtime should strip these on launch
        //    of a hardened binary; if they survived, something is very wrong (or we're
        //    running an unhardened debug build).
        let env = ProcessInfo.processInfo.environment
        let suspicious = ["DYLD_INSERT_LIBRARIES",
                          "DYLD_LIBRARY_PATH",
                          "DYLD_FRAMEWORK_PATH",
                          "DYLD_FALLBACK_LIBRARY_PATH",
                          "DYLD_FALLBACK_FRAMEWORK_PATH"]
        for key in suspicious {
            if let value = env[key], !value.isEmpty {
                Log.security.fault("\(key, privacy: .public) is set at launch (\(value.logSafe, privacy: .public)) — hardened runtime should have stripped this")
                #if !DEBUG
                SecurityState.shared.markCompromised(reason: "\(key) survived hardened runtime")
                #endif
            }
        }

        // 2. Bundle-signature self-check. Catches post-install tampering of the binary,
        //    Info.plist, or bundled resources.
        switch SignatureCheck.verifyOwnSignatureStrict() {
        case .ok:
            Log.security.info("self-signature check passed")
        case .tampered(let reason):
            Log.security.fault("self-signature check FAILED — bundle likely tampered: \(reason.logSafe, privacy: .public)")
            SecurityState.shared.markCompromised(reason: "self-signature tamper: \(reason)")
            SignatureCheck.presentTamperAlert(reason: reason)
        case .checkFailed(let reason):
            // Could not determine — only escalate in Release builds (Debug runs unsigned).
            Log.security.error("self-signature check could not run: \(reason.logSafe, privacy: .public)")
            #if !DEBUG
            SecurityState.shared.markCompromised(reason: "self-signature check failed: \(reason)")
            #endif
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Appearance

    private func applyIconStyle() {
        if let img = Appearance.iconStyle.image {
            NSApp.applicationIconImage = img
        }
    }

    private func applyMenuBarStyle() {
        guard let button = statusItem?.button else { return }
        let symbol = NSImage(systemSymbolName: Appearance.menuBarStyle.symbolName,
                             accessibilityDescription: "ClaudeHealth")
        symbol?.isTemplate = true
        button.image = symbol
    }

    // MARK: - Dashboard

    func toggleDashboard(anchoredTo anchor: NSRect?) {
        if let dc = dashboardController, dc.window?.isVisible == true {
            dc.hide()
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            return
        }
        if dashboardController == nil {
            dashboardController = DashboardWindowController(
                store: store,
                onDismiss: { [weak self] in self?.dashboardController?.hide() }
            )
        }
        dashboardController?.show(anchoredTo: anchor ?? bubbleController?.window?.frame)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    // MARK: - Settings

    func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(store: store)
        }
        settingsController?.show()
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            toggleDashboard(anchoredTo: nil)
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(menuItem("Show Dashboard", #selector(menuShowDashboard), symbol: "chart.bar.xaxis"))
        menu.addItem(menuItem("Refresh Now",    #selector(menuRefresh),       symbol: "arrow.clockwise"))
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…",      #selector(menuSettings),      symbol: "gearshape"))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit ClaudeHealth", #selector(menuQuit), symbol: "power"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector, symbol: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            image.isTemplate = true
            item.image = image
        }
        return item
    }

    @objc private func menuShowDashboard() { toggleDashboard(anchoredTo: nil) }
    @objc private func menuRefresh()       { Task { await store.refresh() } }
    @objc private func menuSettings()      { showSettings() }
    @objc private func menuQuit()          { NSApp.terminate(nil) }
}
