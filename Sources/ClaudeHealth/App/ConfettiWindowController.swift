import AppKit
import SwiftUI

/// Borderless transparent window covering the entire screen. Hosts ConfettiView
/// when a usage-limit crossing happens. Click-through (ignoresMouseEvents),
/// auto-dismisses after `duration` seconds, never blocks input.
///
/// Uses a regular NSWindow (not NSPanel) at CGShieldingWindowLevel for the
/// most reliable z-order, and rebuilds the SwiftUI host view on every
/// `celebrate()` call so the particle animation restarts cleanly.
final class ConfettiWindowController: NSWindowController {
    private let duration: TimeInterval
    private var dismissWork: DispatchWorkItem?

    init(duration: TimeInterval = 5.0) {
        self.duration = duration

        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Sits above normal app windows (incl. our floating dashboard at .floating)
        // but BELOW screen-saver / login-screen levels, so genuine system dialogs
        // and Apple's secure entry overlays always rise above us. Was .screenSaver
        // (= CGShieldingWindowLevel) — that's reserved for system UI; using it
        // for confetti was over-privileged.
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle, .transient]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.isMovable = false
        window.acceptsMouseMovedEvents = false
        // Excluded from screen capture / sharing — confetti can't accidentally appear
        // in a screen recording or screen-share session of an unrelated app.
        window.sharingType = .none

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func celebrate() {
        Log.confetti.info("celebrate()")
        guard let window else { return }

        // Snap to the current main screen (may have changed since init).
        if let frame = NSScreen.main?.frame {
            window.setFrame(frame, display: false)
        }

        // Rebuild the SwiftUI host so ConfettiView's @State `startTime` resets to now.
        let host = NSHostingView(rootView: ConfettiView(duration: duration))
        host.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = host
        if let cv = window.contentView {
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
                host.topAnchor.constraint(equalTo: cv.topAnchor),
                host.bottomAnchor.constraint(equalTo: cv.bottomAnchor)
            ])
        }

        window.alphaValue = 1
        window.orderFrontRegardless()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

        // Cancel any prior auto-dismiss (e.g. rapid double-trigger).
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.window?.orderOut(nil)
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
