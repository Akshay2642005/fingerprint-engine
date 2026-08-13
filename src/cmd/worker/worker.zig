//! Deterministic fingerprint worker app (D9, D16), part of the shared CLI
//! folder `src/cmd/` (ADR-011).
//!
//! Tiny by design: parse CLI args, select the inbound transport at comptime,
//! then loop `read frame → map to engine request → engine.process() → reply`.
//! No business logic — the engine performs every computation, and every
//! transport concern lives in the adapter layer.
//!
//! CLI (invoked standalone or via the combined `fingerprint` binary — the
//! argv contract is identical, see `parse`):
//!   worker start --transport=loopback|tcp [--listen=host:port]
//!                [--publish=amqp|none]
//!   worker version
//!   worker help
//!
//! The worker replies with an FPKG frame whose payload starts with the
//! engine `Status` code byte followed by the operation's result (see
//! `decodeReply`). Frame integrity is validated on ingest; corrupt frames
//! are dropped and acked as poison (no DLQ in v1).

const std = @import("std");
const builtin = @import("builtin");
const engine = @import("engine");
const adapter = @import("adapter");
const io = @import("io");
const version_info = @import("version");
const shutdown = @import("shutdown");

/// Product version, injected from build.zig.zon as the `version`
/// build-options module (ADR-011/BUG-002).
pub const version = version_info.version;

/// Upper bound on an operation's result payload. The engine folds oversized
/// results into `status.buffer_overflow`, so this is a cap, not a contract.
pub const max_result: usize = 64 * 1024;

// ── Graceful shutdown (H-2) ──────────────────────────────────────────

/// Set by the signal handlers; the accept/serve loops poll it so the worker
/// can drain in-flight requests and exit 0 on SIGTERM/SIGINT (H-2). Shared
/// with the ingress via src/cmd/shutdown.zig — the combined `fingerprint`
/// binary installs one handler that drains both apps.
pub const shutdown_requested = &shutdown.requested;

/// How long the tcp accept loop waits for a client before re-checking the
/// shutdown flag while idle.
const accept_poll_ms: u32 = 250;

/// Installs the shutdown handlers (src/cmd/shutdown.zig). Linux covers CI
/// and the container deployment target (tini forwards SIGTERM); Windows
/// covers local dev Ctrl+C. Public so the combined `fingerprint` binary
/// (src/cmd/main.zig) can install them once before dispatching.
pub fn installShutdownHandlers() void {
    shutdown.install();
}

// ── CLI ──────────────────────────────────────────────────────────────

pub const TransportKind = enum { loopback, tcp };

pub const PublishKind = enum { none, amqp };

pub const StartOptions = struct {
    transport: TransportKind = .loopback,
    /// host:port for --transport=tcp; port 0 binds an ephemeral port.
    listen: ?[]const u8 = null,
    publish: PublishKind = .none,
    /// Idle receive deadline for tcp clients, in ms; 0 disables (H-1).
    idle_timeout_ms: u64 = 30_000,
    /// Broker host:port for --publish=amqp.
    amqp_address: []const u8 = "127.0.0.1:5672",
    amqp_user: []const u8 = "guest",
    amqp_password: []const u8 = "guest",
    amqp_vhost: []const u8 = "/",
};

pub const Command = union(enum) {
    start: StartOptions,
    version,
    help,
};

pub const CliError = error{ UnknownSubcommand, UnknownOption, InvalidOption, MissingListen };

pub const usage =
    \\Usage:
    \\
    \\  worker start --transport=loopback|tcp [--listen=host:port]
    \\               [--publish=amqp|none]
    \\               [--idle-timeout-ms=ms]
    \\               [--amqp-address=host:port] [--amqp-user=user]
    \\               [--amqp-password=pass] [--amqp-vhost=vhost]
    \\
    \\  worker version
    \\  worker help
    \\
    \\Options:
    \\  --transport   inbound transport: loopback (stdin/stdout frames) or
    \\                tcp (FPKG-framed request/response server; requires
    \\                --listen)
    \\  --listen      host:port to bind for --transport=tcp; port 0 picks an
    \\                ephemeral port, announced on stderr
    \\  --idle-timeout-ms  tcp client idle deadline in ms; 0 disables
    \\                (default 30000). A client that sends nothing for this
    \\                long is disconnected so a stalled connection cannot
    \\                wedge the accept loop (H-1).
    \\  --publish     outbound event sink: none or amqp. With amqp, every
    \\                reply frame is published to the broker's `fingerprint`
    \\                exchange (direct, durable) under routing key
    \\                result.<message-type>, with publisher confirms. Publish
    \\                failures are logged and the frame dropped; the broker's
    \\                persistence and the supervisor's restart policy cover
    \\                the rest in v1.
    \\  --amqp-address  broker host:port (default 127.0.0.1:5672)
    \\  --amqp-user     broker user name (default guest)
    \\  --amqp-password  broker password (default guest)
    \\  --amqp-vhost     broker virtual host (default /)
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
        if (std.mem.startsWith(u8, arg, "--transport=")) {
            const value = arg["--transport=".len..];
            options.transport = parseTransport(value) orelse return error.InvalidOption;
        } else if (std.mem.startsWith(u8, arg, "--listen=")) {
            options.listen = arg["--listen=".len..];
        } else if (std.mem.startsWith(u8, arg, "--publish=")) {
            const value = arg["--publish=".len..];
            options.publish = parsePublish(value) orelse return error.InvalidOption;
        } else if (std.mem.startsWith(u8, arg, "--idle-timeout-ms=")) {
            options.idle_timeout_ms = std.fmt.parseInt(u64, arg["--idle-timeout-ms=".len..], 10) catch
                return error.InvalidOption;
        } else if (std.mem.startsWith(u8, arg, "--amqp-address=")) {
            options.amqp_address = arg["--amqp-address=".len..];
        } else if (std.mem.startsWith(u8, arg, "--amqp-user=")) {
            options.amqp_user = arg["--amqp-user=".len..];
        } else if (std.mem.startsWith(u8, arg, "--amqp-password=")) {
            options.amqp_password = arg["--amqp-password=".len..];
        } else if (std.mem.startsWith(u8, arg, "--amqp-vhost=")) {
            options.amqp_vhost = arg["--amqp-vhost=".len..];
        } else return error.UnknownOption;
    }
    if (options.transport == .tcp and options.listen == null) return error.MissingListen;
    return .{ .start = options };
}

fn parseTransport(value: []const u8) ?TransportKind {
    if (std.mem.eql(u8, value, "loopback")) return .loopback;
    if (std.mem.eql(u8, value, "tcp")) return .tcp;
    return null;
}

fn parsePublish(value: []const u8) ?PublishKind {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "amqp")) return .amqp;
    return null;
}

// ── Frame ↔ engine mapping (design §8) ───────────────────────────────

/// Inbound FPKG message type → engine operation. Outbound event types
/// (diagnostics, fingerprint_computed) are not engine operations and return
/// null so the worker replies `invalid_request`.
pub fn operationFor(message_type: io.frame.MessageType) ?engine.Operation {
    return switch (message_type) {
        .signal_package => .hash, // canonical digest — the worker's core path
        .validation_result => .validate,
        .normalization_result => .normalize,
        .fingerprint_result => .hash,
        .risk_result => .risk,
        .similarity_result => .similarity,
        .diagnostics, .fingerprint_computed, .entropy_result => null,
    };
}

/// Engine operation → reply frame message type.
pub fn resultType(operation: engine.Operation) io.frame.MessageType {
    return switch (operation) {
        .validate => .validation_result,
        .normalize => .normalization_result,
        .hash => .fingerprint_result,
        .entropy => .entropy_result,
        .risk => .risk_result,
        .similarity => .similarity_result,
        .serialize, .deserialize, .package => .signal_package,
        // Unknown wire tags never reach the worker (operationFor rejects
        // them), but the non-exhaustive enum demands a default prong.
        _ => .diagnostics,
    };
}

fn codecOf(frame_codec: io.frame.Codec) engine.CodecID {
    // Frame and engine codec tags are the same wire values (1 = binary,
    // 2 = json), so the conversion cannot fail.
    return std.meta.intToEnum(engine.CodecID, @intFromEnum(frame_codec)) catch unreachable;
}

/// The worker's reply to one inbound frame: an FPKG frame whose payload is
/// `u8 status | engine result`. `buf` must hold at least
/// `header_size + 1 + max_result` bytes; the engine writes its result in
/// place after the status byte.
pub fn processFrame(frame: []const u8, buf: []u8, allocator: std.mem.Allocator) ![]const u8 {
    const decoded = try adapter.decodeFrame(frame);
    const operation = operationFor(decoded.header.message_type) orelse {
        return buildReply(.diagnostics, decoded.header.codec, .invalid_request, &.{}, buf);
    };

    var response = engine.Response.init(operation, buf[io.frame.header_size + 1 ..]);
    var request = engine.Request{
        .operation = operation,
        .codec = codecOf(decoded.header.codec),
        .payload = decoded.payload,
    };
    try engine.process(&request, &response, allocator);

    return buildReply(resultType(operation), decoded.header.codec, response.status, response.slice(), buf);
}

pub const Reply = struct {
    message_type: io.frame.MessageType,
    status: engine.Status,
    /// Engine result, after the status byte.
    payload: []const u8,
};

/// Parses a worker reply frame: `status byte | engine result`.
pub fn decodeReply(frame: []const u8) !Reply {
    const decoded = try adapter.decodeFrame(frame);
    if (decoded.payload.len < 1) return error.Truncated;
    const status = std.meta.intToEnum(engine.Status, decoded.payload[0]) catch return error.InvalidStatus;
    return .{
        .message_type = decoded.header.message_type,
        .status = status,
        .payload = decoded.payload[1..],
    };
}

fn buildReply(
    message_type: io.frame.MessageType,
    codec: io.frame.Codec,
    status: engine.Status,
    result: []const u8,
    buf: []u8,
) ![]const u8 {
    const payload_len = 1 + result.len;
    if (buf.len < io.frame.header_size + payload_len) return error.BufferFull;
    const payload = buf[io.frame.header_size .. io.frame.header_size + payload_len];
    payload[0] = status.code();
    // The engine writes its result immediately after the status byte, so the
    // normal path needs no copy; the guard keeps buildReply safe for results
    // that arrive from elsewhere.
    if (@intFromPtr(result.ptr) != @intFromPtr(payload.ptr + 1)) {
        @memcpy(payload[1..], result);
    }
    // Zero-copy: the payload already lives at buf[header_size..], so only the
    // header needs writing. Going through buildFrame would re-copy the payload
    // onto itself (aliased @memcpy).
    const header = io.frame.FrameHeader{
        .message_type = message_type,
        .codec = codec,
        .payload_len = @intCast(payload_len),
        .integrity = io.frame.FrameHeader.integrityOf(payload),
    };
    var w = io.Writer.init(buf);
    try header.encode(&w);
    return buf[0 .. io.frame.header_size + payload_len];
}

// ── Service loop ─────────────────────────────────────────────────────

/// True when the transport reports the peer is done sending. The service
/// loop treats these as a clean shutdown rather than an error. The set is
/// transport-agnostic: stdin EOF (loopback) and TCP disconnect errors
/// (tcp) both exit the loop the same way.
fn peerGone(err: anyerror) bool {
    return switch (err) {
        error.EndOfStream, error.ConnectionClosedByPeer, error.BrokenPipe => true,
        else => false,
    };
}

/// Serves frames until the transport reports end-of-stream, then returns.
/// Inbound frames are processed one at a time; scratch is an arena that
/// resets after every frame (no state carries across requests). When a
/// publisher is configured, every reply frame is also published to the
/// broker; publish failures are logged and the frame dropped (v1 policy,
/// documented in the CLI usage).
fn serve(
    comptime Transport: type,
    t: *Transport,
    alloc: std.mem.Allocator,
    publisher: ?*adapter.amqp_publisher.Publisher,
) !void {
    comptime adapter.transport.check(Transport);
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    // H-2: check the flag at the top of the frame loop so an in-flight
    // request completes (process → reply → publish → ack) before the worker
    // drains and exits. readFrame stays bounded by H-1, so an idle client
    // cannot stall the drain indefinitely.
    while (!shutdown_requested.load(.acquire)) {
        const frame = t.readFrame(a) catch |err| {
            if (peerGone(err)) return;
            return err;
        };

        var buf: [io.frame.header_size + 1 + max_result]u8 = undefined;
        const reply = processFrame(frame, &buf, a) catch |err| {
            // Poison frame (bad magic, integrity violation, ...): drop and
            // ack; v1 has no dead-letter queue.
            std.debug.print("worker: frame dropped: {s}\n", .{@errorName(err)});
            t.ack(frame);
            _ = arena.reset(.retain_capacity);
            continue;
        };

        try t.writeFrame(reply);
        try t.publish(reply); // transport-level outbound hook (no-op in v1)
        if (publisher) |p| {
            p.publish_reply(reply) catch |err| {
                std.debug.print("worker: publish dropped: {s}\n", .{@errorName(err)});
            };
        }
        t.ack(frame);
        _ = arena.reset(.retain_capacity);
    }
}

fn start(options: StartOptions, alloc: std.mem.Allocator) !void {
    var publisher: ?adapter.amqp_publisher.Publisher = null;
    if (options.publish == .amqp) {
        const host, const port = splitHostPort(options.amqp_address) catch {
            std.debug.print("worker: invalid --amqp-address '{s}' (expected host:port)\n", .{options.amqp_address});
            std.process.exit(1);
        };
        const address = std.net.Address.parseIp(host, port) catch {
            std.debug.print("worker: invalid --amqp-address '{s}' (expected host:port)\n", .{options.amqp_address});
            std.process.exit(1);
        };
        const p = adapter.amqp_publisher.Publisher.init(alloc, .{
            .address = address,
            .user_name = options.amqp_user,
            .password = options.amqp_password,
            .virtual_host = options.amqp_vhost,
            // The worker caps every reply at header + status + max_result.
            .message_size_max = @intCast(io.frame.header_size + 1 + max_result),
        }) catch |err| {
            std.debug.print("worker: amqp publisher failed: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        publisher = p;
        std.debug.print(
            "worker: amqp publisher ready at {s}:{d} (exchange '{s}')\n",
            .{ host, port, adapter.amqp_publisher.exchange_name },
        );
    }
    defer if (publisher) |*p| p.deinit(alloc);
    // serve() takes the publisher by pointer so one broker connection is
    // shared across every inbound client in the accept loop.
    const publisher_ptr: ?*adapter.amqp_publisher.Publisher = if (publisher) |*p| p else null;

    switch (options.transport) {
        .loopback => {
            var t = adapter.Loopback.init(alloc, .stdio);
            defer t.deinit();
            try serve(adapter.Loopback, &t, alloc, publisher_ptr);
        },
        .tcp => {
            const listen = options.listen orelse unreachable; // parse enforces
            const host, const port = splitHostPort(listen) catch {
                std.debug.print("worker: invalid --listen '{s}' (expected host:port)\n", .{listen});
                std.process.exit(1);
            };
            var t = try adapter.Tcp.init(
                alloc,
                host,
                port,
                // H-1: per-client receive deadline (0 disables). Clamp the
                // multiply so a huge --idle-timeout-ms cannot overflow.
                std.math.mul(u64, options.idle_timeout_ms, std.time.ns_per_ms) catch std.math.maxInt(u64),
            );
            defer t.deinit();
            // Announce the bound address so supervisors and tests can learn
            // the ephemeral port (--listen=...:0).
            std.debug.print("worker: listening on {s}:{d}\n", .{ host, t.port() });
            // H-2: acceptWait bounds the accept so the loop observes the
            // shutdown flag while idle; accept() applies the per-client idle
            // deadline (H-1). On exit the current client is closed by deinit.
            while (!shutdown_requested.load(.acquire)) {
                if (!try t.acceptWait(accept_poll_ms)) continue;
                serve(adapter.Tcp, &t, alloc, publisher_ptr) catch |err| {
                    if (peerGone(err)) continue; // client done; serve the next
                    // Protocol errors (InvalidMagic, Truncated,
                    // IntegrityViolation, ...) are per-connection: after a
                    // malformed frame the stream is desynchronized, so close
                    // the client and keep serving. A single bad client must
                    // never take down the worker (or its container).
                    t.closeClient();
                    continue;
                };
            }
        },
    }
}

fn splitHostPort(listen: []const u8) !struct { []const u8, u16 } {
    const idx = std.mem.lastIndexOfScalar(u8, listen, ':') orelse return error.InvalidListen;
    const host = listen[0..idx];
    const port = try std.fmt.parseInt(u16, listen[idx + 1 ..], 10);
    return .{ host, port };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // H-2: SIGTERM/SIGINT (POSIX) and Ctrl+C/Ctrl+Break (Windows) set the
    // shutdown flag; the accept/serve loops drain in-flight work and exit 0.
    installShutdownHandlers();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    try run(alloc, args);
}

/// Runs the worker CLI against an argv slice that includes argv[0] (the
/// subcommand name, e.g. `"worker"`). Shared by the standalone `worker`
/// binary (`main`) and the combined `fingerprint` binary
/// (`src/cmd/main.zig` passes `args[1..]`). The caller owns shutdown
/// handler installation and the args allocation.
pub fn run(alloc: std.mem.Allocator, args: []const []const u8) !void {
    const command = parse(args) catch |err| {
        const message: []const u8 = switch (err) {
            error.UnknownSubcommand => "unknown subcommand",
            error.UnknownOption => "unknown option",
            error.InvalidOption => "invalid option",
            error.MissingListen => "--transport=tcp requires --listen=host:port",
        };
        std.io.getStdErr().writer().print("worker: {s}\n\n{s}", .{ message, usage }) catch {};
        std.process.exit(1);
    };
    switch (command) {
        .help => try std.io.getStdOut().writer().writeAll(usage),
        .version => try std.io.getStdOut().writer().print("worker version {s}\n", .{version}),
        .start => |options| try start(options, alloc),
    }
}
