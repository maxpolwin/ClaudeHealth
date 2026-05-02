import AppKit
import SwiftUI

private let dashboardSize = NSSize(width: 760, height: 920)

final class DashboardWindowController: NSWindowController {
    private let store: DataStore
    private let onDismiss: () -> Void
    private var clickOutsideMonitor: Any?
    private var keyMonitor: Any?

    init(store: DataStore, onDismiss: @escaping () -> Void) {
        self.store = store
        self.onDismiss = onDismiss
        let panel = DashboardPanel(contentRect: NSRect(origin: .zero, size: dashboardSize))
        super.init(window: panel)

        let host = NSHostingView(rootView: DashboardView(store: store).tint(Palette.brand))
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = host
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            host.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            host.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(anchoredTo bubbleFrame: NSRect?) {
        guard let panel = window else { return }
        positionPanel(near: bubbleFrame)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        })
        installMonitors()

        // Trigger an Apple Intelligence insight refresh in the background.
        // Throttled in DataStore — won't fire if a fresh one already exists.
        Task { @MainActor [weak store] in
            await store?.maybeRefreshInsight()
        }
    }

    func hide() {
        guard let panel = window, panel.isVisible else { return }
        removeMonitors()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.allowsImplicitAnimation = true
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    // MARK: - Positioning

    private func positionPanel(near bubble: NSRect?) {
        guard let panel = window, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let inset: CGFloat = 16
        var origin: NSPoint
        if let bubble {
            // Prefer placing to the left of the bubble if there's room, else right; align tops.
            let preferLeft = bubble.midX > visible.midX
            let x = preferLeft
                ? max(visible.minX + inset, bubble.minX - dashboardSize.width - 12)
                : min(visible.maxX - dashboardSize.width - inset, bubble.maxX + 12)
            let y = min(max(bubble.maxY - dashboardSize.height, visible.minY + inset),
                        visible.maxY - dashboardSize.height - inset)
            origin = NSPoint(x: x, y: y)
        } else {
            origin = NSPoint(
                x: visible.midX - dashboardSize.width / 2,
                y: visible.midY - dashboardSize.height / 2
            )
        }
        panel.setFrame(NSRect(origin: origin, size: dashboardSize), display: true, animate: false)
    }

    // MARK: - Dismiss-on-outside-click & Escape

    private func installMonitors() {
        removeMonitors()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let frame = self.window?.frame else { return }
            let p = NSEvent.mouseLocation
            if !frame.contains(p) {
                self.onDismiss()
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {            // Escape
                self?.onDismiss()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m); clickOutsideMonitor = nil }
        if let m = keyMonitor          { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    deinit { removeMonitors() }
}

final class DashboardPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.animationBehavior = .utilityWindow
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
