import AppKit
import SwiftUI

// The NSPanel is intentionally larger than the visible bubble so SwiftUI's
// .shadow() can bleed out into transparent space without being clipped at
// the panel edge (which produced a square shadow halo around the round bubble).
private let bubbleVisualSide: CGFloat = 72        // the actual round bubble
private let bubblePadding: CGFloat = 14           // transparent room for shadow + hover scale-up
private let bubbleSide: CGFloat = bubbleVisualSide + 2 * bubblePadding   // = 100
private let bubblePosKey = "ClaudeHealth.bubbleOrigin"

final class BubbleWindowController: NSWindowController {

    private let store: DataStore
    private let onPrimaryAction: (NSRect?) -> Void
    private let onShowSettings: () -> Void

    private var moveObserver: NSObjectProtocol?
    private var mouseUpMonitor: Any?
    private var isMaybeDragging = false
    private var lastFrameDuringDrag: NSRect = .zero

    init(store: DataStore,
         onPrimaryAction: @escaping (NSRect?) -> Void,
         onShowSettings: @escaping () -> Void) {
        self.store = store
        self.onPrimaryAction = onPrimaryAction
        self.onShowSettings = onShowSettings

        let origin = Self.loadOrigin()
        let panel = BubblePanel(contentRect: NSRect(origin: origin, size: NSSize(width: bubbleSide, height: bubbleSide)))
        super.init(window: panel)

        let host = NSHostingView(rootView: BubbleView(
            store: store,
            onPrimaryAction: { [weak self, weak panel] in
                guard let self, let frame = panel?.frame else { return }
                self.onPrimaryAction(frame)
            },
            onShowSettings: { [weak self] in
                self?.onShowSettings()
            }
        ).tint(Palette.brand))
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = host
        if let cv = panel.contentView {
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
                host.topAnchor.constraint(equalTo: cv.topAnchor),
                host.bottomAnchor.constraint(equalTo: cv.bottomAnchor)
            ])
        }

        // Movement-driven drag detection.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self, let panel = self.window else { return }
            self.isMaybeDragging = true
            self.lastFrameDuringDrag = panel.frame
            // Persist mid-drag in case the user quits before mouseUp fires.
            Self.saveOrigin(panel.frame.origin)
        }

        // Global left-mouse-up monitor → snap to nearest edge if a drag was in progress.
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self, self.isMaybeDragging else { return }
            self.isMaybeDragging = false
            self.snapToNearestEdge()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let m = moveObserver { NotificationCenter.default.removeObserver(m) }
        if let m = mouseUpMonitor { NSEvent.removeMonitor(m) }
    }

    func show() {
        window?.orderFrontRegardless()
    }

    // MARK: - Edge snap

    private func snapToNearestEdge() {
        guard let panel = window else { return }
        let screen = panel.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let frame = panel.frame
        let inset: CGFloat = 8

        // The user perceives the BUBBLE position, not the (larger) panel.
        // The bubble visual sits inset by `bubblePadding` inside the panel.
        // Compute distances from the visible bubble edges, not the panel edges.
        let bubbleMinX = frame.minX + bubblePadding
        let bubbleMaxX = frame.maxX - bubblePadding
        let bubbleMinY = frame.minY + bubblePadding
        let bubbleMaxY = frame.maxY - bubblePadding

        let dLeft   = bubbleMinX - visible.minX
        let dRight  = visible.maxX - bubbleMaxX
        let dTop    = visible.maxY - bubbleMaxY
        let dBottom = bubbleMinY - visible.minY
        let minD = min(dLeft, dRight, dTop, dBottom)

        var newOrigin = frame.origin
        // Snap so that the BUBBLE (not the panel) sits `inset` pts from the screen edge.
        if minD == dLeft {
            newOrigin.x = visible.minX + inset - bubblePadding
        } else if minD == dRight {
            newOrigin.x = visible.maxX - frame.width - inset + bubblePadding
        } else if minD == dTop {
            newOrigin.y = visible.maxY - frame.height - inset + bubblePadding
        } else {
            newOrigin.y = visible.minY + inset - bubblePadding
        }

        // Orthogonal-axis clamp — keep the bubble (with its padding) within the visible frame.
        newOrigin.x = max(visible.minX + inset - bubblePadding,
                         min(visible.maxX - frame.width - inset + bubblePadding, newOrigin.x))
        newOrigin.y = max(visible.minY + inset - bubblePadding,
                         min(visible.maxY - frame.height - inset + bubblePadding, newOrigin.y))

        // Animate snap with a spring-like timing function.
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.34, 0.64, 1.0)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(NSRect(origin: newOrigin, size: frame.size), display: true)
        })
        Self.saveOrigin(newOrigin)
        // Native trackpad haptic — no-op on devices without Force Touch.
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: - Persistent position

    private static func defaultOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let visible = screen.visibleFrame
        // Place so the BUBBLE (visible round part) sits ~24pt from top-right corner.
        return NSPoint(x: visible.maxX - bubbleSide - 24 + bubblePadding,
                       y: visible.maxY - bubbleSide - 24 + bubblePadding)
    }

    private static func loadOrigin() -> NSPoint {
        let d = UserDefaults.standard
        guard d.object(forKey: bubblePosKey) != nil else { return defaultOrigin() }
        let saved = NSPoint(x: d.double(forKey: bubblePosKey + ".x"),
                            y: d.double(forKey: bubblePosKey + ".y"))
        // Clamp to a screen the user can actually see — otherwise unplugging an
        // external display between sessions strands the bubble at coordinates
        // off the current screen tree.
        let visible: NSRect
        if let onScreen = NSScreen.screens.first(where: { $0.frame.contains(saved) }) {
            visible = onScreen.visibleFrame
        } else if let main = NSScreen.main {
            visible = main.visibleFrame
        } else {
            return defaultOrigin()
        }
        let inset: CGFloat = 8
        let x = max(visible.minX + inset - bubblePadding,
                    min(visible.maxX - bubbleSide - inset + bubblePadding, saved.x))
        let y = max(visible.minY + inset - bubblePadding,
                    min(visible.maxY - bubbleSide - inset + bubblePadding, saved.y))
        return NSPoint(x: x, y: y)
    }

    private static func saveOrigin(_ p: NSPoint) {
        let d = UserDefaults.standard
        d.set(true, forKey: bubblePosKey)
        d.set(p.x, forKey: bubblePosKey + ".x")
        d.set(p.y, forKey: bubblePosKey + ".y")
    }
}

final class BubblePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.animationBehavior = .none
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
