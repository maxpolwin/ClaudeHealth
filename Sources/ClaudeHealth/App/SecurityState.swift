import Foundation

/// Process-wide security verdict, set once at launch by `runSecurityChecks()`.
///
/// When the on-launch self-signature check or the DYLD env-var audit reports a
/// problem, the user-facing tamper alert promises that we "won't write to the
/// cache file or register new Login Items until you reinstall." This type is
/// what makes that promise enforceable: callers consult `allowsCacheWrite` /
/// `allowsLoginItemRegistration` before performing those actions.
///
/// Defaults to "everything allowed" so that pre-init code paths and unit tests
/// behave normally; flipped to degraded mode only when AppDelegate observes a
/// tamper or DYLD-injection signal.
final class SecurityState: @unchecked Sendable {
    static let shared = SecurityState()

    private let lock = NSLock()
    private var _isCompromised = false

    /// Mark the process as degraded. Idempotent. Call from `runSecurityChecks()`.
    func markCompromised(reason: String) {
        lock.lock()
        defer { lock.unlock() }
        if _isCompromised { return }
        _isCompromised = true
        Log.security.fault("entering degraded mode: \(reason.logSafe, privacy: .public)")
    }

    var isCompromised: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isCompromised
    }

    /// Refuse to overwrite the on-disk cache when we don't trust the binary —
    /// otherwise a tampered binary could poison the cache for the next launch.
    var allowsCacheWrite: Bool { !isCompromised }

    /// Refuse to register new Login Items when degraded so a tampered binary
    /// can't establish persistence behind the alert the user just dismissed.
    var allowsLoginItemRegistration: Bool { !isCompromised }
}
