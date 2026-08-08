//! Deterministic fingerprint worker executable (D9, D16).
//!
//! Tiny by design: parse CLI args, select the inbound transport at comptime,
//! then loop `read frame → map to engine request → engine.process() → reply`.
//! No business logic — the engine performs every computation, and every
//! transport concern lives in the adapter layer.
//!
//! CLI:
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
const engine = @import("engine");
const adapter = @import("adapter");
const io = @import("io");

/// Matches build.zig.zon; kept here until the CLI lands a shared version
/// source of truth.
pub const version = "0.2.0";

/// Upper bound on an operation's result payload. The engine folds oversized
/// results into `status.buffer_overflow`, so this is a cap, not a contract.
pub const max_result: usize = 64 * 1024;

// ── CLI ──────────────────────────────────────────────────────────────

pub const TransportKind = enum { loopback, tcp };

pub const PublishKind = enum { none, amqp };

pub const StartOptions = struct {
    transport: TransportKind = .loopback,
    /// host:port for --transport=tcp; port 0 binds an ephemeral port.
    listen: ?[]const u8 = null,
    publish: PublishKind = .none,
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
    \\  --publish     outbound event sink: none (v1) or amqp (not built yet)
    \\
;

/// Parses argv (including argv[0]) into a Command. Diagnostics go to stderr.
pub fn parse(args: []const []const u8) CliError!Command {
    const subcommand = if (args.len > 1) args[1] else "help";
    if (std.mem.eql(u8, subcommand, "help") or
        std.mem.eql(u8, subcommand, "-h") or
        std.mem.eql(u8, subcommand, "--help"))
    {
        return .help;
    }
    if (std.mem.eql(u8, subcommand, "version")) return .version;
    if (!std.mem.eql(u8, subcommand, "start")) {
        std.debug.print("worker: unknown subcommand '{s}'\n\n{s}", .{ subcommand, usage });
        return error.UnknownSubcommand;
    }

    var options = StartOptions{};
    for (args[2..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--transport=")) {
            const value = arg["--transport=".len..];
            options.transport = parseTransport(value) orelse {
                std.debug.print("worker: invalid transport '{s}' (expected loopback|tcp)\n", .{value});
                return error.InvalidOption;
            };
        } else if (std.mem.startsWith(u8, arg, "--listen=")) {
            options.listen = arg["--listen=".len..];
        } else if (std.mem.startsWith(u8, arg, "--publish=")) {
            const value = arg["--publish=".len..];
            options.publish = parsePublish(value) orelse {
                std.debug.print("worker: invalid publish '{s}' (expected amqp|none)\n", .{value});
                return error.InvalidOption;
            };
        } else {
            std.debug.print("worker: unknown option '{s}'\n\n{s}", .{ arg, usage });
            return error.UnknownOption;
        }
    }
    if (options.transport == .tcp and options.listen == null) {
        std.debug.print("worker: --transport=tcp requires --listen=host:port\n\n{s}", .{usage});
        return error.MissingListen;
    }
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
/// resets after every frame (no state carries across requests).
fn serve(comptime Transport: type, t: *Transport, alloc: std.mem.Allocator) !void {
    comptime adapter.transport.check(Transport);
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    while (true) {
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
        try t.publish(reply); // v1: no-op on every transport
        t.ack(frame);
        _ = arena.reset(.retain_capacity);
    }
}

fn start(options: StartOptions, alloc: std.mem.Allocator) !void {
    switch (options.publish) {
        .none => {},
        .amqp => {
            std.debug.print("worker: --publish=amqp is not built yet; use --publish=none\n", .{});
            std.process.exit(1);
        },
    }
    switch (options.transport) {
        .loopback => {
            var t = adapter.Loopback.init(alloc, .stdio);
            defer t.deinit();
            try serve(adapter.Loopback, &t, alloc);
        },
        .tcp => {
            const listen = options.listen orelse unreachable; // parse enforces
            const host, const port = splitHostPort(listen) catch {
                std.debug.print("worker: invalid --listen '{s}' (expected host:port)\n", .{listen});
                std.process.exit(1);
            };
            var t = try adapter.Tcp.init(alloc, host, port);
            defer t.deinit();
            // Announce the bound address so supervisors and tests can learn
            // the ephemeral port (--listen=...:0).
            std.debug.print("worker: listening on {s}:{d}\n", .{ host, t.port() });
            while (true) {
                try t.accept();
                serve(adapter.Tcp, &t, alloc) catch |err| {
                    if (peerGone(err)) continue; // client done; serve the next
                    return err;
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

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const command = parse(args) catch std.process.exit(1);
    switch (command) {
        .help => try std.io.getStdOut().writer().writeAll(usage),
        .version => try std.io.getStdOut().writer().print("worker version {s}\n", .{version}),
        .start => |options| try start(options, alloc),
    }
}
