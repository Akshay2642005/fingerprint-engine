//! Combined `fingerprint` binary — the single-artifact distribution
//! (ADR-011, TigerBeetle-style subcommands).
//!
//! Dispatches on argv[1]:
//!   fingerprint worker  ...  → worker.run  (same CLI as standalone `worker`)
//!   fingerprint ingress ...  → ingress.run (same CLI as standalone `ingress`)
//!   fingerprint version      → product version
//!   fingerprint help         → this usage
//!
//! argv contract (shared with the standalone binaries): each app's
//! `parse(args)` skips args[0] and reads args[1] as its subcommand, so we
//! pass `args[1..]` down and the two invocations stay byte-compatible.

const std = @import("std");
const version_info = @import("version");
const worker = @import("worker/worker.zig");
const ingress = @import("ingress/ingress.zig");
const log = @import("log");

/// Routes `std.log` (the AMQP client's `std.log.scoped(.amqp)`) through the
/// application logger when running under the combined binary, so
/// `fingerprint worker start --log-level=...` behaves exactly like the
/// standalone worker (specs/architecture/logging.md, F-2/S3).
pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = log.logFn,
};

/// Product version, injected from build.zig.zon as the `version`
/// build-options module (ADR-011/BUG-002).
pub const version = version_info.version;
const usage =
    \\Usage:
    \\
    \\  fingerprint worker start --transport=loopback|tcp [--listen=host:port]
    \\                           [--publish=amqp|none]
    \\                           [--idle-timeout-ms=ms]
    \\                           [--amqp-address=host:port] [--amqp-user=user]
    \\                           [--amqp-password=pass] [--amqp-vhost=vhost]
    \\  fingerprint ingress start --listen=host:port --worker=host:port
    \\                            [--worker=host:port ...] [--max-body=bytes]
    \\  fingerprint worker version
    \\  fingerprint worker help
    \\  fingerprint ingress version
    \\  fingerprint ingress help
    \\  fingerprint version
    \\  fingerprint help
    \\
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // H-2: install the signal handlers once, before dispatching. The worker
    // owns the shared shutdown flag; the ingress adds its own drain when S4
    // lands (specs/architecture/ingress.md).
    worker.installShutdownHandlers();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const subcommand = if (args.len > 1) args[1] else "help";
    if (std.mem.eql(u8, subcommand, "worker")) return worker.run(alloc, args[1..]);
    if (std.mem.eql(u8, subcommand, "ingress")) return ingress.run(alloc, args[1..]);
    if (std.mem.eql(u8, subcommand, "version")) {
        try std.io.getStdOut().writer().print("fingerprint version {s}\n", .{version});
        return;
    }
    if (std.mem.eql(u8, subcommand, "help") or
        std.mem.eql(u8, subcommand, "-h") or
        std.mem.eql(u8, subcommand, "--help"))
    {
        try std.io.getStdOut().writer().writeAll(usage);
        return;
    }
    std.io.getStdErr().writer().print(
        "fingerprint: unknown subcommand '{s}'\n\n{s}",
        .{ subcommand, usage },
    ) catch {};
    std.process.exit(1);
}
