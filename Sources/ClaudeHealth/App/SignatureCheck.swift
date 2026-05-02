import Foundation
import Security
import AppKit

/// Self-verifies our own bundle on launch. If the binary or any sealed resource
/// (Info.plist, AppIcon-*.icns, entitlements blob) was tampered with after install,
/// the strict validity check fails and we raise a high-visibility alert + log a
/// `Log.security` fault. App keeps running but should refuse to write the cache
/// or register Login Items in that state.
///
/// What this catches:
/// - Someone replaced `Contents/MacOS/ClaudeHealth` with a re-signed trojan
/// - Someone modified `Contents/Info.plist` (e.g. added LSEnvironment to inject dylib)
/// - Someone swapped a bundled .icns
///
/// What this does NOT catch (handled elsewhere):
/// - Runtime code injection via DYLD_INSERT_LIBRARIES → blocked by hardened runtime entitlement
/// - Library hijack → blocked by library-validation entitlement (no Frameworks/ in bundle anyway)
enum SignatureCheck {

    enum Verdict {
        case ok
        case tampered(String)        // human-readable reason
        case checkFailed(String)     // couldn't determine — treat as suspicious
    }

    /// Call from `applicationDidFinishLaunching`. Synchronous, ~10ms.
    static func verifyOwnSignatureStrict() -> Verdict {
        var staticCode: SecStaticCode?
        let bundleURL = Bundle.main.bundleURL as CFURL
        let createStatus = SecStaticCodeCreateWithPath(bundleURL, [], &staticCode)
        guard createStatus == errSecSuccess, let code = staticCode else {
            return .checkFailed("SecStaticCodeCreateWithPath status=\(createStatus)")
        }
        // Strict + nested-code check across all architectures.
        // (kSecCSEnforceRevocationChecks isn't surfaced in the current Swift binding;
        // the strict + nested-code combination is the meaningful tamper detection.)
        let flags = SecCSFlags(rawValue:
              kSecCSStrictValidate
            | kSecCSCheckAllArchitectures
            | kSecCSCheckNestedCode)
        var errorRef: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, nil, &errorRef)
        if status == errSecSuccess { return .ok }

        let reason: String
        if let err = errorRef?.takeRetainedValue() {
            reason = (CFErrorCopyDescription(err) as String?) ?? "OSStatus=\(status)"
        } else {
            reason = "OSStatus=\(status)"
        }
        return .tampered(reason)
    }

    /// User-facing alert on tamper. Non-blocking — app continues but degraded.
    @MainActor
    static func presentTamperAlert(reason: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "ClaudeHealth: signature check failed"
        alert.informativeText = """
            The app bundle on disk doesn't match what was originally signed. This usually \
            means files in /Applications/ClaudeHealth.app were modified after install — \
            either by an upgrade in progress, or by something tampering with the bundle.

            ClaudeHealth will keep running but will not write to its cache file or register \
            new Login Items until you reinstall from a trusted source.

            Detail: \(reason)
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
