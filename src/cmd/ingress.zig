//! HTTP ingress app (F-1/M5, S4), part of the shared CLI folder `src/cmd/`
//! (ADR-011). The ingress is the only component allowed to speak HTTP: it
//! terminates the browser SDK's POST, validates integrity, wraps the body in
//! an FPKG frame, forwards it to a pooled worker over the `--transport=tcp`
//! path, and translates the FPKG reply back to HTTP.
//!
//! It contains **no engine code**: `engine` is not registered in this
//! module's import map (build.zig), so the rule is structurally enforced
//! (design §7, D16). It imports only `io` + `adapter` framing helpers.
//!
//! CLI (invoked standalone or via the combined `fingerprint` binary — the
//! argv contract is identical, see `parse`):
//!   ingress start --listen=host:port --worker=host:port [--worker=...]
//!                 [--max-body=bytes] [--log-level=level]
//!                 [--log-format=text|json]
//!   ingress version
//!   ingress help
//!
//! S4 status: CLI surface + parse are implemented and unit-tested; the
//! `start` server (HTTP termination, boundary checks, worker pool, status
//! mapping, graceful shutdown) is the S4 backlog slice —
//! specs/architecture/ingress.md.
//!
//! story: s4-ingress-shared-cli

const std = @import("std");
const version_info = @import("version");

/// Product version, injected from build.zig.zon as the `version`
/// build-options module (ADR-011/BUG-002).
pub const version = version_info.version;

/// Default cap on accepted POST bodies. Far below the 16 MiB FPKG cap and
/// comfortably above a real package (canvas/audio bytes are tens of KB).
pub const default_max_body: u64 = 1024 * 1024;

// ── CLI ──────────────────────────────────────────────────────────────

pub const StartOptions = struct {
    /// host:port to bind for HTTP; port 0 binds an ephemeral port.
    listen: ?[]const u8 = null,
    /// Worker pool seeds, each host:port (repeatable). The runtime also
    /// accepts FPKG_WORKERS (comma-separated) for containerized deploys.
    workers: [max_workers][]const u8 = undefined,
    worker_count: usize = 0,
    /// Content-Length cap for POST bodies (413 above it).
    max_body: u64 = default_max_body,
    log_level: []const u8 = "info",
    log_format: []const u8 = "text",
};

/// Cap on CLI worker seeds. Parse is pure (no allocator); the S4 runtime
/// pool can grow beyond this from FPKG_WORKERS.
pub const max_workers: usize = 16;

pub const Command = union(enum) {
    start: StartOptions,
    version,
    help,
};

pub const CliError = error{ UnknownSubcommand, UnknownOption, InvalidOption, MissingListen, TooManyWorkers };

pub const usage =
    \\Usage:
    \\
    \\  ingress start --listen=host:port --worker=host:port [--worker=...]
    \\                [--max-body=bytes] [--log-level=level]
    \\                [--log-format=text|json]
    \\
    \\  ingress version
    \\  ingress help
    \\
    \\Options:
    \\  --listen      host:port to bind for HTTP; port 0 picks an ephemeral
    \\                port, announced on stderr
    \\  --worker      worker pool seed (repeatable); workers are also read
    \\                from FPKG_WORKERS (comma-separated) when not given
    \\  --max-body    accepted POST body cap in bytes (default 1048576)
    \\  --log-level   log verbosity: debug|info|warn|error (default info)
    \\  --log-format  log encoding: text|json (default text)
    \\
;

/// Parses argv (including argv[0]) into a Command.
/// Pure: errors are returned to the caller, which owns the diagnostics.
pub fn parse(args: []const []const u8) CliError!Command {
    const subcommand = if (args.len > 1) args[1] else "help";
    if (std.mem.eql(u8, subcommand, "help") or
        std.mem.eql(u8, subcommand, "-h") or
        std.mem.eql(u8, subcommand, "--help"))
    {
        return .help;
    }
    if (std.mem.eql(u8, subcommand, "version")) return .version;
    if (!std.mem.eql(u8, subcommand, "start")) return error.UnknownSubcommand;

    var options = StartOptions{};
    for (args[2..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--listen=")) {
            options.listen = arg["--listen=".len..];
        } else if (std.mem.startsWith(u8, arg, "--worker=")) {
            if (options.worker_count >= max_workers) return error.TooManyWorkers;
            options.workers[options.worker_count] = arg["--worker=".len..];
            options.worker_count += 1;
        } else if (std.mem.startsWith(u8, arg, "--max-body=")) {
            options.max_body = std.fmt.parseInt(u64, arg["--max-body=".len..], 10) catch
                return error.InvalidOption;
        } else if (std.mem.startsWith(u8, arg, "--log-level=")) {
            options.log_level = arg["--log-level=".len..];
        } else if (std.mem.startsWith(u8, arg, "--log-format=")) {
            options.log_format = arg["--log-format=".len..];
        } else return error.UnknownOption;
    }
    if (options.listen == null) return error.MissingListen;
    return .{ .start = options };
}

// ── Entry points ─────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    try run(alloc, args);
}

/// Runs the ingress CLI against an argv slice that includes argv[0] (the
/// subcommand name, e.g. `"ingress"`). Shared by the standalone `ingress`
/// binary (`main`) and the combined `fingerprint` binary
/// (`src/cmd/main.zig` passes `args[1..]`). The caller owns the args
/// allocation.
pub fn run(alloc: std.mem.Allocator, args: []const []const u8) !void {
    const command = parse(args) catch |err| {
        const message: []const u8 = switch (err) {
            error.UnknownSubcommand => "unknown subcommand",
            error.UnknownOption => "unknown option",
            error.InvalidOption => "invalid option",
            error.MissingListen => "start requires --listen=host:port",
            error.TooManyWorkers => "too many --worker seeds",
        };
        std.io.getStdErr().writer().print("ingress: {s}\n\n{s}", .{ message, usage }) catch {};
        std.process.exit(1);
    };
    switch (command) {
        .help => try std.io.getStdOut().writer().writeAll(usage),
        .version => try std.io.getStdOut().writer().print("ingress version {s}\n", .{version}),
        .start => |options| try start(options, alloc),
    }
}

// ── HTTP server (S4) ─────────────────────────────────────────────────

/// S4 scaffold: the HTTP server (termination, integrity checks, FPKG
/// wrapping, worker pool, status mapping, graceful shutdown) is the next
/// backlog slice — specs/architecture/ingress.md. The CLI surface is real
/// so `zig build ingress` / `zig build fingerprint` ship a working
/// `version`/`help` and the parse contract is testable today.
fn start(options: StartOptions, alloc: std.mem.Allocator) !void {
    _ = options;
    _ = alloc;
    std.io.getStdErr().writer().print(
        "ingress: HTTP server not implemented yet (S4 — specs/architecture/ingress.md)\n",
        .{},
    ) catch {};
    std.process.exit(1);
}
