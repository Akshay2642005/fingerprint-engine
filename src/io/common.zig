//! Code shared across the io backends (linux epoll, windows IOCP, darwin
//! kqueue): socket options, listen/bind, and the monotonic clock. Adapted
//! from TigerBeetle's `src/io/common.zig` and trimmed to our flavor — no
//! tracer, no stats, no file IO.
const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const assert = std.debug.assert;

pub const TCPOptions = struct {
    rcvbuf: c_int,
    sndbuf: c_int,
    keepalive: ?struct {
        keepidle: c_int,
        keepintvl: c_int,
        keepcnt: c_int,
    },
    user_timeout_ms: c_int,
    nodelay: bool,
};

pub const ListenOptions = struct {
    backlog: u31,
};

/// Monotonic clock per IO instance. `std.time.Instant` is BOOTTIME on Linux
/// (ticks while suspended), QPC on Windows, and UPTIME_RAW on macOS — no
/// wall-clock jumps, so deadline races cannot be fooled by NTP.
pub const TimeOS = struct {
    base: std.time.Instant,

    pub fn init() TimeOS {
        return .{ .base = std.time.Instant.now() catch unreachable };
    }

    /// Nanoseconds since this TimeOS was created.
    pub fn monotonic(self: *const TimeOS) u64 {
        return (std.time.Instant.now() catch unreachable).since(self.base);
    }
};

/// Binds and listens; returns the resolved address, which may be more
/// specific than the input (e.g. listening on port 0).
pub fn listen(
    fd: posix.socket_t,
    address: std.net.Address,
    options: ListenOptions,
) !std.net.Address {
    try setsockopt(fd, posix.SOL.SOCKET, posix.SO.REUSEADDR, 1);
    try posix.bind(fd, &address.any, address.getOsSockLen());

    // Resolve port 0 to the actual port picked by the OS.
    var address_resolved: std.net.Address = .{ .any = undefined };
    var addrlen: posix.socklen_t = @sizeOf(std.net.Address);
    try posix.getsockname(fd, &address_resolved.any, &addrlen);
    assert(address_resolved.getOsSockLen() == addrlen);

    try posix.listen(fd, options.backlog);
    return address_resolved;
}

/// TCP socket tuning. Buffer sizes and keepalive are best-effort on
/// non-Linux platforms (guarded at comptime so the constants only exist
/// where the OS defines them).
pub fn tcp_options(fd: posix.socket_t, options: TCPOptions) !void {
    if (options.rcvbuf > 0) try setsockopt(fd, posix.SOL.SOCKET, posix.SO.RCVBUF, options.rcvbuf);
    if (options.sndbuf > 0) try setsockopt(fd, posix.SOL.SOCKET, posix.SO.SNDBUF, options.sndbuf);

    if (options.keepalive) |keepalive| {
        try setsockopt(fd, posix.SOL.SOCKET, posix.SO.KEEPALIVE, 1);
        if (builtin.os.tag == .linux) {
            try setsockopt(fd, posix.IPPROTO.TCP, posix.TCP.KEEPIDLE, keepalive.keepidle);
            try setsockopt(fd, posix.IPPROTO.TCP, posix.TCP.KEEPINTVL, keepalive.keepintvl);
            try setsockopt(fd, posix.IPPROTO.TCP, posix.TCP.KEEPCNT, keepalive.keepcnt);
        }
    }

    if (options.user_timeout_ms > 0) {
        if (builtin.os.tag == .linux) {
            try setsockopt(fd, posix.IPPROTO.TCP, posix.TCP.USER_TIMEOUT, options.user_timeout_ms);
        }
    }

    if (options.nodelay) {
        if (builtin.os.tag == .linux) {
            try setsockopt(fd, posix.IPPROTO.TCP, posix.TCP.NODELAY, 1);
        }
    }
}

pub fn setsockopt(fd: posix.socket_t, level: i32, option: u32, value: c_int) !void {
    try posix.setsockopt(fd, level, option, &std.mem.toBytes(value));
}

/// Caps a buffer at the largest length a single IO syscall accepts on this
/// platform (Linux limits reads/writes to 0x7ffff000; Darwin to
/// maxInt(i32)).
pub fn buffer_limit(buffer_len: usize) usize {
    const limit = switch (builtin.target.os.tag) {
        .linux => 0x7ffff000,
        .macos, .ios, .tvos, .watchos, .visionos => std.math.maxInt(i32),
        else => std.math.maxInt(i32),
    };
    return @min(limit, buffer_len);
}
