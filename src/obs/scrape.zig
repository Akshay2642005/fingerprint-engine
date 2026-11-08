//! GET-only scrape and readiness listener (ADR-014 §3, story m8-observability).
//!
//! Prometheus scrapes HTTP; the worker's own port speaks FPKG. So both
//! components expose `/metrics` and `/readyz` on a **dedicated port**, served
//! by one blocking accept thread. The listener is deliberately separate from
//! the ingress request loop: a slow or stalled scraper must never be able to
//! stall request serving, and the ingress's single accept context is
//! load-bearing for the H-2 drain.
//!
//! Properties that matter:
//!
//! - One connection at a time, `Connection: close`.
//! - A bounded request-head read with a **total** deadline, so a client that
//!   dribbles bytes cannot hold the slot.
//! - No request bodies are read, so there is no body-parsing surface.
//! - `GET` only: `/metrics` and `/readyz`; anything else is 404, any other
//!   method is 405 with `Allow: GET`.
//! - The scrape thread polls the listen socket with a short timeout so
//!   `stop()` returns promptly without relying on close-wakes-accept.
//!
//! The caller supplies two callbacks, both context-pointer based so this
//! module never depends on engine/adapter/cmd and stays allocation-free:
//!
//! - `render_metrics` writes the registry body (see `metrics.render`).
//! - `is_ready` returns `null` when the instance can serve, or the name of a
//!   failing dependency. It must be cheap and non-blocking; callers are
//!   expected to read a cached state, not probe a socket on every scrape.

const std = @import("std");
const metrics_mod = @import("metrics.zig");

/// Body content type for `GET /metrics` (Prometheus text format 0.0.4).
pub const metrics_content_type = metrics_mod.exposition_content_type;

/// Upper bound on the request head. Scrapers send a handful of headers; a
/// `GET` never needs a large head, and the bound keeps the stack fixed.
pub const max_head_bytes: usize = 8 * 1024;

/// Default total budget for reading one request head.
pub const default_head_timeout_ns: u64 = 2 * std.time.ns_per_s;

/// Upper bound on the rendered metrics body. The catalog's bounded label sets
/// fit in a fraction of this; exceeding it is reported as a 500 rather than
/// served truncated.
pub const max_metrics_bytes: usize = 128 * 1024;

/// How long the accept loop sleeps before re-checking the stop flag.
const accept_poll_ms: i32 = 100;

/// Readiness callback: `null` means ready; otherwise the name of the failing
/// dependency (a static, identifier-like string such as `"worker_pool"`).
pub const ReadyFn = *const fn (context: *anyopaque) ?[]const u8;

/// Metrics callback: writes the registry body to a type-erased writer.
pub const RenderFn = *const fn (context: *anyopaque, writer: std.io.AnyWriter) anyerror!void;

pub const Options = struct {
    /// Address to bind. Use port 0 in tests to get an ephemeral port.
    address: std.net.Address,
    /// `ingress` or `worker`; used for `fpkg_<component>_build_info` and
    /// `fpkg_<component>_ready`.
    component: []const u8,
    /// Build version reported by `build_info` and `/readyz`.
    version: []const u8,

    metrics_context: *anyopaque,
    render_metrics: RenderFn,

    ready_context: *anyopaque,
    is_ready: ReadyFn,

    /// Total budget for reading a request head (tests shorten this).
    head_timeout_ns: u64 = default_head_timeout_ns,
};

/// A bound, optionally running listener. `listen` binds; `start` spawns the
/// thread; `stop` joins it and closes the socket.
///
/// The accept thread captures a pointer to this struct, so a `Server` must
/// live at a stable address from `start()` until `stop()` — do not return it
/// by value after starting it, and do not copy it.
pub const Server = struct {
    options: Options,
    server: std.net.Server,
    thread: ?std.Thread = null,
    stopping: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    /// The port actually bound (useful when `options.address` used port 0).
    pub fn port(self: *const Server) u16 {
        return self.server.listen_address.getPort();
    }

    /// Spawns the accept thread. The `Server` must outlive it; `stop` joins.
    pub fn start(self: *Server) !void {
        std.debug.assert(self.thread == null);
        self.thread = try std.Thread.spawn(.{}, run, .{self});
    }

    /// Signals the thread and waits for it, then closes the listen socket.
    pub fn stop(self: *Server) void {
        self.stopping.store(true, .release);
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
        self.server.deinit();
    }
};

/// Binds the metrics socket. Fails on an invalid or occupied address; the
/// caller decides how to surface that (startup should fail loudly).
pub fn listen(options: Options) !Server {
    // Non-blocking listen socket so a client that disappears between poll and
    // accept cannot wedge the loop; accepted sockets stay blocking.
    const server = try options.address.listen(.{
        .reuse_address = true,
        .kernel_backlog = 16,
        .force_nonblocking = true,
    });
    return .{ .options = options, .server = server };
}

fn run(self: *Server) void {
    while (!self.stopping.load(.acquire)) {
        var fds = [_]std.posix.pollfd{.{
            .fd = self.server.stream.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const ready = std.posix.poll(&fds, accept_poll_ms) catch |err| {
            std.log.scoped(.obs).warn("scrape: poll failed: {s}", .{@errorName(err)});
            return;
        };
        if (ready == 0) continue;
        if (fds[0].revents & std.posix.POLL.IN == 0) continue;

        const connection = self.server.accept() catch |err| switch (err) {
            error.WouldBlock => continue,
            else => {
                std.log.scoped(.obs).warn("scrape: accept failed: {s}", .{@errorName(err)});
                continue;
            },
        };
        handleConnection(self, connection.stream) catch |err| {
            std.log.scoped(.obs).debug("scrape: connection closed: {s}", .{@errorName(err)});
        };
        connection.stream.close();
    }
}

fn handleConnection(self: *Server, stream: std.net.Stream) !void {
    var head_buffer: [max_head_bytes]u8 = undefined;
    const head = readHead(stream, &head_buffer, self.options.head_timeout_ns) catch |err| {
        const status = switch (err) {
            error.HeadTimeout => Status.request_timeout,
            error.HeadTooLarge => Status.header_too_large,
            else => Status.bad_request,
        };
        sendJsonError(stream, status, jsonErrorFor(status)) catch {};
        return err;
    };

    const request = parseRequest(head) orelse {
        try sendJsonError(stream, Status.bad_request, "{\"error\":\"bad request\"}");
        return;
    };

    if (!std.mem.eql(u8, request.method, "GET")) {
        try send(stream, Status.method_not_allowed, "application/json", "{\"error\":\"method not allowed\"}", "Allow: GET\r\n");
        return;
    }

    const path = if (std.mem.indexOfScalar(u8, request.target, '?')) |i|
        request.target[0..i]
    else
        request.target;

    if (std.mem.eql(u8, path, "/metrics")) return serveMetrics(self, stream);
    if (std.mem.eql(u8, path, "/readyz")) return serveReady(self, stream);

    try sendJsonError(stream, Status.not_found, "{\"error\":\"not found\"}");
}

fn serveMetrics(self: *Server, stream: std.net.Stream) !void {
    var body_buffer: [max_metrics_bytes]u8 = undefined;
    var body_stream = std.io.fixedBufferStream(&body_buffer);
    const writer = body_stream.writer();

    renderAll(self, writer) catch |err| {
        std.log.scoped(.obs).err("scrape: metrics render failed: {s}", .{@errorName(err)});
        try sendJsonError(stream, Status.internal_error, "{\"error\":\"metrics unavailable\"}");
        return;
    };

    try send(stream, Status.ok, metrics_content_type, body_stream.getWritten(), "");
}

fn renderAll(self: *Server, writer: anytype) !void {
    try writer.print("fpkg_{s}_build_info{{version=\"", .{self.options.component});
    try writeLabelValue(writer, self.options.version);
    try writer.writeAll("\"} 1\n");

    const dependency = (self.options.is_ready)(self.options.ready_context);
    try writer.print("fpkg_{s}_ready {d}\n", .{
        self.options.component,
        @intFromBool(dependency == null),
    });

    try (self.options.render_metrics)(self.options.metrics_context, writer.any());
}

fn serveReady(self: *Server, stream: std.net.Stream) !void {
    var body_buffer: [256]u8 = undefined;
    var body_stream = std.io.fixedBufferStream(&body_buffer);
    const writer = body_stream.writer();

    const dependency = (self.options.is_ready)(self.options.ready_context);
    if (dependency) |name| {
        std.json.stringify(.{
            .ready = false,
            .component = self.options.component,
            .dependency = name,
        }, .{}, writer) catch return error.ReadyBodyTooLarge;
        try send(stream, Status.service_unavailable, "application/json", body_stream.getWritten(), "");
    } else {
        std.json.stringify(.{
            .ready = true,
            .component = self.options.component,
            .version = self.options.version,
        }, .{}, writer) catch return error.ReadyBodyTooLarge;
        try send(stream, Status.ok, "application/json", body_stream.getWritten(), "");
    }
}

const Request = struct {
    method: []const u8,
    target: []const u8,
};

/// Parses only the request line: method, target, and an HTTP/1.x version.
/// Everything else (headers, bodies) is ignored by design.
fn parseRequest(head: []const u8) ?Request {
    const line_end = std.mem.indexOf(u8, head, "\r\n") orelse return null;
    const line = head[0..line_end];

    var parts = std.mem.splitScalar(u8, line, ' ');
    const method = parts.next() orelse return null;
    const target = parts.next() orelse return null;
    const version = parts.next() orelse return null;
    if (method.len == 0 or target.len == 0) return null;
    if (!std.mem.startsWith(u8, version, "HTTP/1.")) return null;
    return .{ .method = method, .target = target };
}

/// Reads until the end of the request head (`\r\n\r\n`). The timeout is a
/// budget for the whole head, not per read: a byte-at-a-time client cannot
/// extend its slot by trickling.
fn readHead(stream: std.net.Stream, buffer: []u8, timeout_ns: u64) ![]const u8 {
    var timer = std.time.Timer.start() catch return error.TimerUnavailable;
    var used: usize = 0;

    while (true) {
        if (std.mem.indexOf(u8, buffer[0..used], "\r\n\r\n")) |end| {
            return buffer[0 .. end + 4];
        }
        if (used == buffer.len) return error.HeadTooLarge;

        const elapsed = timer.read();
        if (elapsed >= timeout_ns) return error.HeadTimeout;

        const remaining_ns = timeout_ns - elapsed;
        const timeout_ms: i32 = @intCast(@max(
            @as(u64, 1),
            @min(remaining_ns / std.time.ns_per_ms, 1000),
        ));

        var fds = [_]std.posix.pollfd{.{
            .fd = stream.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        if (try std.posix.poll(&fds, timeout_ms) == 0) return error.HeadTimeout;

        const n = stream.read(buffer[used..]) catch |err| switch (err) {
            error.WouldBlock => continue,
            else => return err,
        };
        if (n == 0) return error.ConnectionClosed;
        used += n;
    }
}

const Status = struct {
    code: u16,
    reason: []const u8,

    const ok = Status{ .code = 200, .reason = "OK" };
    const bad_request = Status{ .code = 400, .reason = "Bad Request" };
    const not_found = Status{ .code = 404, .reason = "Not Found" };
    const method_not_allowed = Status{ .code = 405, .reason = "Method Not Allowed" };
    const request_timeout = Status{ .code = 408, .reason = "Request Timeout" };
    const header_too_large = Status{ .code = 431, .reason = "Request Header Fields Too Large" };
    const internal_error = Status{ .code = 500, .reason = "Internal Server Error" };
    const service_unavailable = Status{ .code = 503, .reason = "Service Unavailable" };
};

fn jsonErrorFor(status: Status) []const u8 {
    return switch (status.code) {
        400 => "{\"error\":\"bad request\"}",
        408 => "{\"error\":\"request timeout\"}",
        431 => "{\"error\":\"request head too large\"}",
        else => "{\"error\":\"bad request\"}",
    };
}

fn sendJsonError(stream: std.net.Stream, status: Status, body: []const u8) !void {
    try send(stream, status, "application/json", body, "");
}

/// Writes a `Connection: close` response. `extra_headers` is a comptime
/// fragment (already CRLF-terminated) so callers cannot inject headers.
fn send(
    stream: std.net.Stream,
    status: Status,
    content_type: []const u8,
    body: []const u8,
    comptime extra_headers: []const u8,
) !void {
    var head_buffer: [512]u8 = undefined;
    const head = std.fmt.bufPrint(
        &head_buffer,
        "HTTP/1.1 {d} {s}\r\n" ++
            "Content-Type: {s}\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "{s}" ++
            "\r\n",
        .{ status.code, status.reason, content_type, body.len, extra_headers },
    ) catch return error.ResponseHeadTooLarge;
    try stream.writeAll(head);
    try stream.writeAll(body);
}

/// Escapes a label value for the text exposition format (`\`, `"`, newline).
fn writeLabelValue(writer: anytype, value: []const u8) !void {
    for (value) |c| switch (c) {
        '\\' => try writer.writeAll("\\\\"),
        '"' => try writer.writeAll("\\\""),
        '\n' => try writer.writeAll("\\n"),
        else => try writer.writeByte(c),
    };
}

/// Parses `host:port`, `:port`, and `[v6]:port`. An empty host binds all
/// interfaces (`0.0.0.0`). Host names are resolved with `allocator`.
pub fn parseAddress(allocator: std.mem.Allocator, text: []const u8) !std.net.Address {
    if (text.len == 0) return error.InvalidAddress;
    const colon = std.mem.lastIndexOfScalar(u8, text, ':') orelse return error.InvalidAddress;
    const port_text = text[colon + 1 ..];
    if (port_text.len == 0) return error.InvalidAddress;
    const port = std.fmt.parseInt(u16, port_text, 10) catch return error.InvalidAddress;

    const raw_host = text[0..colon];
    if (raw_host.len == 0) return std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);

    const host = if (raw_host.len >= 2 and raw_host[0] == '[' and raw_host[raw_host.len - 1] == ']')
        raw_host[1 .. raw_host.len - 1]
    else
        raw_host;

    if (std.net.Address.parseIp(host, port)) |address| return address else |_| {}
    const list = std.net.getAddressList(allocator, host, port) catch return error.InvalidAddress;
    defer list.deinit();
    if (list.addrs.len == 0) return error.UnknownHostName;
    return list.addrs[0];
}
