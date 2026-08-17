//! Graceful shutdown (H-2), shared by the worker and the ingress.
//!
//! The ingress cannot import `worker` (no engine code in the ingress, D16),
//! yet the combined `fingerprint` binary must install exactly one
//! SIGTERM/SIGINT handler that drains both apps — so the flag and the
//! handlers live here, and `worker`/`ingress` both observe `requested`.
//! Installing twice is harmless: the last install replaces an identical
//! handler that sets the same flag.
//!
//! story: s4-ingress-http

const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;

const native_os = builtin.os.tag;

/// Set by the signal handlers; the accept/serve loops poll it so the worker
/// and ingress can drain in-flight requests and exit 0 on SIGTERM/SIGINT.
pub var requested = std.atomic.Value(bool).init(false);

/// Async-signal-safe POSIX handler: only an atomic store.
fn onShutdownSignal(sig: c_int) callconv(.c) void {
    _ = sig;
    requested.store(true, .release);
}

/// Windows console control handler: claims Ctrl+C / Ctrl+Break and lets the
/// drain path shut the process down.
fn onConsoleEvent(dw_ctrl_type: windows.DWORD) callconv(.C) windows.BOOL {
    _ = dw_ctrl_type;
    requested.store(true, .release);
    return windows.TRUE;
}

/// POSIX sigaction install for SIGTERM/SIGINT (the `restorer` field is
/// Linux-glibc-only, so the literal omits it — it defaults where present).
fn installPosix() void {
    var act = std.posix.Sigaction{
        .handler = .{ .handler = onShutdownSignal },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &act, null);
    std.posix.sigaction(std.posix.SIG.TERM, &act, null);
}

/// Installs the shutdown handlers. POSIX platforms (Linux covers CI and the
/// container deployment target — tini forwards SIGTERM; Darwin covers macOS
/// runners) install the SIGTERM/SIGINT handlers; Windows covers local dev
/// Ctrl+C. Other platforms are a no-op for now (worker-resilience.md).
pub fn install() void {
    switch (native_os) {
        .windows => windows.SetConsoleCtrlHandler(onConsoleEvent, true) catch {},
        .linux, .macos, .ios, .tvos, .watchos, .visionos, .freebsd,
        .netbsd, .openbsd, .dragonfly, .haiku, .solaris, .aix, .serenity => {
            installPosix();
        },
        else => {},
    }
}
