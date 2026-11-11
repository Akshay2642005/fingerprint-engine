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
const obs = @import("obs");
const log = @import("log");

/// Per-collection envelope construction (ADR-013 §1). Publishes an extra
/// outbound frame next to the unchanged digest reply when the publisher is
/// enabled; see `collection_event.zig`.
pub const collection_event = @import("collection_event.zig");

/// Session context codec (ADR-013 §4, ADR-015). Handles both v1 and v2
/// signal_package_context frames.
const session_context = @import("io").session_context;

/// Worker metric registry (ADR-014 §2). Exposed so tests can pin the catalog.
pub const metrics = @import("metrics.zig");

/// Routes `std.log` (the AMQP client's `std.log.scoped(.amqp)`) through the
/// application logger (specs/architecture/logging.md, F-2/S3). The comptime
/// level stays `.debug` — the TigerBeetle pattern — so `--log-level` is the
/// only filter and debug messages are never compiled out.
pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = log.logFn,
};

/// Product version, injected from build.zig.zon as the `version`
/// build-options module (ADR-011/BUG-002).
pub const version = version_info.version;

/// R-6: Upper bound on an operation's result payload (64 KiB). The engine
/// folds oversized results into `status.buffer_overflow`, so this is a cap,
/// not a contract. Callers (e.g. WASM, TCP) must not rely on payloads
/// exceeding this limit — the worker will reject them at the reply stage.
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

/// Default metrics + probe listener (ADR-014 §4). It is a different port from
/// the ingress (9090) so a scrape target can never be ambiguous;
/// `--metrics-listen=off` disables the surface.
pub const default_metrics_listen = ":9091";

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
    // D-5: guest/guest is the standard RabbitMQ development default.
    // Production deployments MUST override via CLI flags or env vars.
    amqp_user: []const u8 = "guest",
    amqp_password: []const u8 = "guest",
    amqp_vhost: []const u8 = "/",
    /// --log-level (err|warn|info|debug); null = FPKG_LOG_LEVEL, then info.
    log_level: ?log.Level = null,
    /// --log-format (text|json); null = FPKG_LOG_FORMAT, then text.
    log_format: ?log.Format = null,
    /// --metrics-listen (host:port) for the scrape + probe surface; defaults
    /// to `:9091`. `off` disables the surface (ADR-014 §4).
    metrics_listen: []const u8 = default_metrics_listen,
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
    \\               [--log-level=level] [--log-format=text|json]
    \\               [--metrics-listen=host:port|off]
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
    \\                result.<message-type>, with publisher confirms. Each
    \\                successful signal package also publishes one
    \\                `collection_event` (result.collection-event) carrying the
    \\                ADR-013 envelope, so a ledger can store one row per
    \\                collection. Publish failures are logged and the frame
    \\                dropped; the broker's persistence and the supervisor's
    \\                restart policy cover the rest in v1.
    \\  --amqp-address  broker host:port (default 127.0.0.1:5672)
    \\  --amqp-user     broker user name (default guest)
    \\  --amqp-password  broker password (default guest)
    \\  --amqp-vhost     broker virtual host (default /)
    \\  --log-level   log verbosity: debug|info|warn|err (default info;
    \\                FPKG_LOG_LEVEL overrides the default, the flag wins)
    \\  --log-format  log encoding: text|json (default text;
    \\                FPKG_LOG_FORMAT overrides the default, the flag wins)
    \\  --metrics-listen  metrics + readiness listener (default :9091); never
    \\                the FPKG port; `off` disables the surface
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
        } else if (std.mem.startsWith(u8, arg, "--log-level=")) {
            options.log_level = log.parseLevel(arg["--log-level=".len..]) orelse
                return error.InvalidOption;
        } else if (std.mem.startsWith(u8, arg, "--log-format=")) {
            options.log_format = log.parseFormat(arg["--log-format=".len..]) orelse
                return error.InvalidOption;
        } else if (std.mem.startsWith(u8, arg, "--metrics-listen=")) {
            const value = arg["--metrics-listen=".len..];
            if (value.len == 0) return error.InvalidOption;
            options.metrics_listen = value;
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
/// (diagnostics, fingerprint_computed, collection_event) are not engine
/// operations and return null so the worker replies `invalid_request`.
pub fn operationFor(message_type: io.frame.MessageType) ?engine.Operation {
    return switch (message_type) {
        .signal_package => .hash, // canonical digest — the worker's core path
        // A signal package wrapped with an ingress session id (ADR-013 §4):
        // same operation, the prefix is stripped before the engine sees it.
        .signal_package_context, .signal_package_context_v2 => .hash,
        .validation_result => .validate,
        .normalization_result => .normalize,
        .fingerprint_result => .hash,
        .risk_result => .risk,
        .similarity_result => .similarity,
        .diagnostics, .fingerprint_computed, .entropy_result, .collection_event => null,
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

/// One inbound frame, resolved to what the engine needs. Splitting transport
/// metadata from the request payload is what keeps `signal_package_context`
/// invisible to the engine (ADR-013 §4).
pub const Inbound = struct {
    /// The frame's message type as received; `signal_package_context` stays
    /// visible here so logging and dispatch can distinguish it.
    message_type: io.frame.MessageType,
    codec: io.frame.Codec,
    /// The engine request payload. For `signal_package_context` this is the
    /// inner package body with the context prefix stripped — byte-identical
    /// to an unwrapped `signal_package` body, so the digest is too.
    body: []const u8,
    /// `x-fpkg-session-id` as forwarded by the ingress; null when the client
    /// sent none. Borrows from the frame.
    session_id: ?[]const u8 = null,
    request_id: ?[]const u8 = null,
    /// Ingress arrival time in epoch milliseconds (0 when the frame did not
    /// traverse the ingress, e.g. a direct TCP/loopback client).
    ingress_received_at: i64 = 0,
};

/// Resolves a decoded frame into an `Inbound`. A `signal_package_context`
/// payload is `[u16 session_len][session][i64 ingress_received_at][body]`;
/// malformed context is a protocol error (the caller drops the frame, as for
/// any poison frame). A `signal_package_context_v2` payload includes a
/// request_id prefix (ADR-015).
pub fn splitInbound(decoded: adapter.DecodedFrame) !Inbound {
    if (decoded.header.message_type != .signal_package_context and
        decoded.header.message_type != .signal_package_context_v2)
    {
        return .{
            .message_type = decoded.header.message_type,
            .codec = decoded.header.codec,
            .body = decoded.payload,
        };
    }
    const view = if (decoded.header.message_type == .signal_package_context_v2)
        try session_context.unwrapV2(decoded.payload)
    else
        try session_context.unwrap(decoded.payload);
    return .{
        .message_type = decoded.header.message_type,
        .codec = decoded.header.codec,
        .body = view.body,
        .session_id = if (view.session_id.len > 0) view.session_id else null,
        .request_id = if (view.request_id.len > 0) view.request_id else null,
        .ingress_received_at = view.ingress_received_at,
    };
}

/// The worker's reply to one inbound frame: an FPKG frame whose payload is
/// `u8 status | engine result`. `buf` must hold at least
/// `header_size + 1 + max_result` bytes; the engine writes its result in
/// place after the status byte.
pub fn processFrame(frame: []const u8, buf: []u8, allocator: std.mem.Allocator) ![]const u8 {
    return processFrameWithMetrics(frame, buf, allocator, null);
}

/// `processFrame` with a metrics registry. Instrumented at this level rather
/// than in `serve` because the operation, the status and the engine call all
/// exist here, so one code path records both the counter and the latency and a
/// new caller cannot instrument only half of it.
pub fn processFrameWithMetrics(
    frame: []const u8,
    buf: []u8,
    allocator: std.mem.Allocator,
    registry: ?*metrics.Metrics,
) ![]const u8 {
    const started_ns = std.time.nanoTimestamp();
    const decoded = try adapter.decodeFrame(frame);
    const inbound = try splitInbound(decoded);
    const operation = operationFor(inbound.message_type) orelse {
        // Decoded but not an engine operation: the reply is a 400, and it
        // still counts as a job so `jobs_total` matches the replies served.
        if (registry) |m| m.observeJob(.unknown, .@"error", elapsedSeconds(started_ns));
        return buildReply(.diagnostics, inbound.codec, .invalid_request, &.{}, buf);
    };

    var response = engine.Response.init(operation, buf[io.frame.header_size + 1 ..]);
    var request = engine.Request{
        .operation = operation,
        .codec = codecOf(inbound.codec),
        .payload = inbound.body,
    };
    engine.process(&request, &response, allocator) catch |err| {
        if (registry) |m| m.observeJob(metrics.opOf(operation), .@"error", elapsedSeconds(started_ns));
        return err;
    };

    if (registry) |m| {
        const result: metrics.JobResult = if (response.status == .ok) .ok else .@"error";
        m.observeJob(metrics.opOf(operation), result, elapsedSeconds(started_ns));
    }
    return buildReply(resultType(operation), inbound.codec, response.status, response.slice(), buf);
}

/// Seconds between `started_ns` and now. A negative delta (clock step) is
/// clamped to zero rather than trusted.
fn elapsedSeconds(started_ns: i128) f64 {
    const delta = std.time.nanoTimestamp() - started_ns;
    return @as(f64, @floatFromInt(@max(delta, 0))) / @as(f64, @floatFromInt(std.time.ns_per_s));
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
/// broker, and every successful collection additionally publishes one
/// `collection_event` envelope (ADR-013); publish failures are logged and the
/// frame dropped (v1 policy, documented in the CLI usage).
fn serve(
    comptime Transport: type,
    t: *Transport,
    alloc: std.mem.Allocator,
    publisher: ?*adapter.amqp_publisher.Publisher,
    registry: *metrics.Metrics,
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
            if (peerGone(err)) {
                // Clean peer close: the client hung up. serve() returns
                // normally here, so the close is attributed inside — the
                // accept loop only sees non-peerGone (protocol) errors.
                log.worker.debug("worker: client closed", .{});
                return;
            }
            return err;
        };
        const request_id = requestIdForFrame(frame, a) catch |err| {
            log.worker.warn("worker: cannot establish request id: {s}", .{@errorName(err)});
            return err;
        };

        // got job: decode the request header for the flow trace. Flow
        // lifecycle lines are info (visible at the default level, S3b);
        // frame-detail fields (codec, payload_len) stay at debug. The decode
        // is gated on the info level so the default build pays the cost
        // exactly once per frame; processFrame re-decodes (with integrity)
        // anyway.
        if (log.shouldLog(.info)) {
            if (adapter.decodeFrame(frame)) |decoded| {
                log.worker.info("worker: got job type={s} request_id={s}", .{ @tagName(decoded.header.message_type), request_id });
                if (log.shouldLog(.debug)) {
                    log.worker.debug(
                        "worker: job detail codec={s} payload_len={d}",
                        .{ @tagName(decoded.header.codec), decoded.header.payload_len },
                    );
                }
            } else |_| {} // decode errors surface in processFrame below
        }

        log.worker.info("worker: processing job request_id={s}", .{request_id});
        var buf: [io.frame.header_size + 1 + max_result]u8 = undefined;
        const reply = processFrameWithMetrics(frame, &buf, a, registry) catch |err| {
            // Poison frame (bad magic, integrity violation, ...): drop and
            // ack; v1 has no dead-letter queue.
            log.worker.warn("worker: frame dropped request_id={s}: {s}", .{ request_id, @errorName(err) });
            registry.frames_dropped_total.inc(.{ .reason = metrics.dropReasonOf(err) });
            t.ack(frame);
            _ = arena.reset(.retain_capacity);
            continue;
        };
        // The reply type/status for the flow trace; decoded once, gated on
        // the info level (the reply is self-built, so decode cannot fail).
        const flow_reply: ?Reply = if (log.shouldLog(.info)) (decodeReply(reply) catch null) else null;

        if (flow_reply) |r| {
            log.worker.info("worker: job done status={s} request_id={s}", .{ @tagName(r.status), request_id });
            if (log.shouldLog(.debug)) {
                log.worker.debug("worker: job detail result_len={d}", .{r.payload.len});
            }
        }

        try t.writeFrame(reply);
        if (flow_reply) |r| {
            log.worker.info("worker: reply sent to client (type={s}) request_id={s}", .{ @tagName(r.message_type), request_id });
        }
        try t.publish(reply); // transport-level outbound hook (no-op in v1)
        if (publisher) |p| {
            if (!p.isConnected()) {
                p.reconnect(alloc) catch |err| {
                    registry.amqp_connected.set(0);
                    registry.publish_total.inc(.{ .result = .failed });
                    log.worker.warn("worker: AMQP reconnect failed: {s}", .{@errorName(err)});
                    t.ack(frame);
                    _ = arena.reset(.retain_capacity);
                    continue;
                };
                registry.amqp_connected.set(1);
                log.worker.info("worker: AMQP connection recovered", .{});
            }
            if (flow_reply) |r| {
                log.worker.info(
                    "worker: publishing reply (type={s}) to exchange '{s}' key '{s}'",
                    .{
                        @tagName(r.message_type),
                        adapter.amqp_publisher.exchange_name,
                        adapter.amqp_publisher.routingKey(r.message_type),
                    },
                );
            }
            const published = blk: {
                p.publish_replyWithRequestId(reply, request_id) catch |err| {
                    // ADR-016: handle unroutable messages by republishing to DLQ
                    if (err == error.Unroutable) {
                        registry.publish_total.inc(.{ .result = .unroutable });
                        p.republishToDlq(reply, request_id) catch |dlq_err| {
                            registry.publish_total.inc(.{ .result = .dlq_failed });
                            log.worker.warn("worker: DLQ republish failed: {s}", .{@errorName(dlq_err)});
                            break :blk false;
                        };
                        registry.publish_total.inc(.{ .result = .dlq });
                        log.worker.warn("worker: message unroutable, republished to DLQ", .{});
                        break :blk true;
                    }
                    p.markDisconnected();
                    registry.amqp_connected.set(0);
                    registry.publish_total.inc(.{ .result = .failed });
                    log.worker.warn("worker: publish dropped: {s}", .{@errorName(err)});
                    break :blk false;
                };
                registry.publish_total.inc(.{ .result = .acked });
                break :blk true;
            };
            if (published) log.worker.info("worker: publish confirmed request_id={s}", .{request_id});

            // ADR-013 §1: one extra out-of-band frame per successful
            // collection, carrying the self-contained ledger document. It is
            // built from the same package the reply was, after the reply is
            // published, so a slow/expensive envelope can never delay or
            // change the browser's reply (which was already written above).
            if (published) publishCollectionEvent(frame, reply, a, p, request_id, registry);
        }
        t.ack(frame);
        _ = arena.reset(.retain_capacity);
    }
}

fn requestIdForFrame(frame: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const decoded = try adapter.decodeFrame(frame);
    const inbound = try splitInbound(decoded);
    if (inbound.request_id) |request_id| return request_id;

    var raw: [16]u8 = undefined;
    std.crypto.random.bytes(&raw);
    const id = try allocator.alloc(u8, 32);
    _ = std.fmt.bufPrint(id, "{s}", .{std.fmt.fmtSliceHexLower(&raw)}) catch unreachable;
    return id;
}

/// Builds and publishes the collection envelope for one request/reply pair.
/// Non-collection frames and failed collections build nothing (returns
/// silently); a build or publish failure is logged and dropped, exactly like
/// the reply publish path — the ledger can fall back to the live fanout, and a
/// partial/truncated envelope would be worse than none (ADR-013 §1).
fn publishCollectionEvent(
    frame: []const u8,
    reply: []const u8,
    alloc: std.mem.Allocator,
    publisher: *adapter.amqp_publisher.Publisher,
    request_id: []const u8,
    registry: *metrics.Metrics,
) void {
    const out = alloc.alloc(u8, io.frame.header_size + collection_event.max_payload) catch {
        log.worker.warn("worker: collection event dropped: out of memory", .{});
        return;
    };
    const event_frame = collection_event.buildWithMetrics(frame, reply, alloc, out, registry) catch |err| {
        log.worker.warn("worker: collection event dropped: {s}", .{@errorName(err)});
        return;
    } orelse return;

    if (log.shouldLog(.info)) {
        log.worker.info(
            "worker: publishing collection event to exchange '{s}' key '{s}'",
            .{
                adapter.amqp_publisher.exchange_name,
                adapter.amqp_publisher.routingKey(.collection_event),
            },
        );
    }
    publisher.publish_replyWithRequestId(event_frame, request_id) catch |err| {
        registry.publish_total.inc(.{ .result = .failed });
        log.worker.warn("worker: collection event publish dropped: {s}", .{@errorName(err)});
        return;
    };
    registry.publish_total.inc(.{ .result = .acked });
    log.worker.info("worker: collection event confirmed", .{});
}

fn start(options: StartOptions, alloc: std.mem.Allocator) !void {
    // Logging config: CLI flags > FPKG_LOG_LEVEL/FPKG_LOG_FORMAT > defaults
    // (specs/architecture/logging.md). Applied before any message is logged.
    log.initFromEnv(alloc, options.log_level, options.log_format);

    // ADR-017: env-only AMQP credentials. FPKG_AMQP_USER/FPKG_AMQP_PASSWORD
    // take precedence over deprecated CLI flags.
    const amqp_user = readEnvCredential("FPKG_AMQP_USER", options.amqp_user);
    const amqp_password = readEnvCredential("FPKG_AMQP_PASSWORD", options.amqp_password);

    // ADR-014 §2: the registry is process-scoped and atomic; the scrape thread
    // reads it while the serve loop writes. Created before the publisher so the
    // scrape surface can report a failed AMQP link as `amqp_connected 0`.
    var registry = metrics.Metrics{};

    var publisher: ?adapter.amqp_publisher.Publisher = null;
    if (options.publish == .amqp) {
        const host, const port = splitHostPort(options.amqp_address) catch {
            log.worker.err("worker: invalid --amqp-address '{s}' (expected host:port)", .{options.amqp_address});
            std.process.exit(1);
        };
        const address = adapter.transport.resolveHost(alloc, host, port) catch {
            log.worker.err("worker: cannot resolve --amqp-address '{s}'", .{options.amqp_address});
            std.process.exit(1);
        };
        const p = adapter.amqp_publisher.Publisher.init(alloc, .{
            .address = address,
            .user_name = amqp_user,
            .password = amqp_password,
            .virtual_host = options.amqp_vhost,
            // The worker caps every reply at header + status + max_result.
            .message_size_max = @intCast(io.frame.header_size + 1 + max_result),
        }) catch |err| {
            log.worker.err("worker: amqp publisher failed: {s}", .{@errorName(err)});
            std.process.exit(1);
        };
        publisher = p;
        registry.amqp_connected.set(1);
        log.worker.info(
            "worker: amqp publisher ready at {s}:{d} (exchange '{s}')",
            .{ host, port, adapter.amqp_publisher.exchange_name },
        );
    }
    defer if (publisher) |*p| {
        registry.amqp_connected.set(0);
        p.deinit(alloc);
    };
    // serve() takes the publisher by pointer so one broker connection is
    // shared across every inbound client in the accept loop.
    const publisher_ptr: ?*adapter.amqp_publisher.Publisher = if (publisher) |*p| p else null;

    // ADR-014 §4: metrics + probes live on their own port and thread, bound
    // before the FPKG port is announced so a supervisor never sees a listening
    // worker whose observability surface failed to bind. A deployment that
    // believes it has metrics but silently does not is worse than a failed
    // start, so both an invalid address and an occupied port exit 1.
    var scrape_server: ?obs.scrape.Server = null;
    defer if (scrape_server) |*scrape| scrape.stop();
    if (std.mem.eql(u8, options.metrics_listen, "off")) {
        log.worker.info("worker: metrics disabled (--metrics-listen=off)", .{});
    } else {
        const metrics_address = obs.scrape.parseAddress(alloc, options.metrics_listen) catch {
            log.worker.err("worker: invalid --metrics-listen '{s}' (expected host:port or off)", .{options.metrics_listen});
            std.process.exit(1);
        };
        scrape_server = obs.scrape.listen(.{
            .address = metrics_address,
            .component = "worker",
            .version = version,
            .metrics_context = &registry,
            .render_metrics = renderMetrics,
            .ready_context = &registry,
            .is_ready = isReady,
        }) catch |err| {
            log.worker.err("worker: cannot bind --metrics-listen '{s}': {s}", .{
                options.metrics_listen,
                @errorName(err),
            });
            std.process.exit(1);
        };
        if (scrape_server) |*scrape| {
            scrape.start() catch |err| {
                log.worker.err("worker: cannot start the metrics listener: {s}", .{@errorName(err)});
                std.process.exit(1);
            };
            log.worker.info("worker: metrics listening on port {d} (bind {s})", .{
                scrape.port(),
                options.metrics_listen,
            });
        }
    }

    switch (options.transport) {
        .loopback => {
            var t = adapter.Loopback.init(alloc, .stdio);
            defer t.deinit();
            try serve(adapter.Loopback, &t, alloc, publisher_ptr, &registry);
        },
        .tcp => {
            const listen = options.listen orelse unreachable; // parse enforces
            const host, const port = splitHostPort(listen) catch {
                log.worker.err("worker: invalid --listen '{s}' (expected host:port)", .{listen});
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
            // the ephemeral port (--listen=...:0). The `worker: listening on `
            // substring is an integration-test contract; --log-level=err
            // suppresses the line on purpose (specs/architecture/logging.md).
            log.worker.info("worker: listening on {s}:{d}", .{ host, t.port() });
            // H-2: acceptWait bounds the accept so the loop observes the
            // shutdown flag while idle; accept() applies the per-client idle
            // deadline (H-1). On exit the current client is closed by deinit.
            while (!shutdown_requested.load(.acquire)) {
                if (!try t.acceptWait(accept_poll_ms)) continue;
                log.worker.info("worker: client accepted", .{});
                serve(adapter.Tcp, &t, alloc, publisher_ptr, &registry) catch |err| {
                    // serve() already attributes clean peer closes; only
                    // protocol errors land here.
                    // Protocol errors (InvalidMagic, Truncated,
                    // IntegrityViolation, ...) are per-connection: after a
                    // malformed frame the stream is desynchronized, so close
                    // the client and keep serving. A single bad client must
                    // never take down the worker (or its container).
                    log.worker.warn("worker: client dropped: {s}", .{@errorName(err)});
                    t.closeClient();
                    continue;
                };
            }
        },
    }
}

/// Scrape callback: renders the worker registry (ADR-014). The registry is
/// atomic, so this runs on the scrape thread without locking.
fn renderMetrics(context: *anyopaque, writer: std.io.AnyWriter) anyerror!void {
    const registry: *const metrics.Metrics = @ptrCast(@alignCast(context));
    try metrics.render(registry, writer);
}

/// Readiness callback (ADR-014 §5): the worker serves requests as soon as it
/// is listening. With `--publish=amqp` it also needs the broker link, which is
/// a startup snapshot today — ADR-016 (Week 11) owns reconnects and the
/// dead-letter path.
fn isReady(context: *anyopaque) ?[]const u8 {
    const registry: *const metrics.Metrics = @ptrCast(@alignCast(context));
    return if (registry.amqp_connected.get() > 0) null else "amqp";
}

fn splitHostPort(listen: []const u8) !struct { []const u8, u16 } {
    // R-7: support IPv6 bracket notation "[::1]:8080" in addition to IPv4 "0.0.0.0:8080".
    if (listen.len > 0 and listen[0] == '[') {
        const close = std.mem.indexOfScalar(u8, listen, ']') orelse return error.InvalidListen;
        if (close + 1 >= listen.len or listen[close + 1] != ':') return error.InvalidListen;
        const host = listen[1..close];
        const port = try std.fmt.parseInt(u16, listen[close + 2 ..], 10);
        return .{ host, port };
    }
    const idx = std.mem.lastIndexOfScalar(u8, listen, ':') orelse return error.InvalidListen;
    const host = listen[0..idx];
    const port = try std.fmt.parseInt(u16, listen[idx + 1 ..], 10);
    return .{ host, port };
}

/// Reads an AMQP credential from the environment, with CLI fallback and
/// deprecation warning (ADR-017). The env var wins if both are set.
fn readEnvCredential(env_var: []const u8, cli_value: []const u8) []const u8 {
    const env_val = std.posix.getenv(env_var) orelse "";
    if (env_val.len > 0) {
        // Env var set: warn if CLI flag was also present (env wins)
        if (!std.mem.eql(u8, cli_value, "guest") and !std.mem.eql(u8, cli_value, env_val)) {
            log.worker.warn("worker: --amqp-user/--amqp-password flags ignored (env vars take precedence)", .{});
        }
        return env_val;
    }
    // No env var: use CLI value (deprecation warning if not default)
    if (!std.mem.eql(u8, cli_value, "guest")) {
        log.worker.warn("worker: --amqp-user/--amqp-password are deprecated; use FPKG_AMQP_USER/FPKG_AMQP_PASSWORD env vars instead", .{});
    }
    return cli_value;
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
        log.worker.err("worker: {s}\n\n{s}", .{ message, usage });
        std.process.exit(1);
    };
    switch (command) {
        .help => try std.io.getStdOut().writer().writeAll(usage),
        .version => try std.io.getStdOut().writer().print("worker version {s}\n", .{version}),
        .start => |options| try start(options, alloc),
    }
}
