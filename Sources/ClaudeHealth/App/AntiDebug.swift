import Foundation
import Darwin

// `ptrace` is a libc symbol but not surfaced in Darwin's Swift-visible interface;
// declare it directly. (`@_silgen_name` is the standard idiom for this — Wardle
// uses the same pattern in his anti-debug write-ups.)
@_silgen_name("ptrace")
private func ptrace(_ request: Int32,
                    _ pid: pid_t,
                    _ addr: UnsafeMutablePointer<Int8>?,
                    _ data: Int32) -> Int32

private let PT_DENY_ATTACH: Int32 = 31

/// Anti-debug hook. In **Release** builds, asks the kernel to refuse any future
/// `ptrace` attach to this process, so casual `lldb -p $(pgrep ClaudeHealth)` is
/// blocked. Determined adversaries can still inspect us (kernel patches, DTrace,
/// memory dump from another process with task_for_pid right) — this is defense
/// in depth, not a wall.
///
/// In **Debug** builds the call is omitted so the Xcode debugger keeps working.
enum AntiDebug {
    static func applyIfRelease() {
        #if !DEBUG
        _ = ptrace(PT_DENY_ATTACH, 0, nil, 0)
        #endif
    }
}
