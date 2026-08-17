//! Bounded HTTP/1.1 server for the ingress (S4-c, story s4-ingress-http).
//!
//! Terminates the browser SDK's POST, validates the boundary (body size,
//! integrity, schema), wraps the body in an FPKG frame via
//! `adapter.buildFrame`, forwards it to the worker pool (pool.zig), and
//! relays the worker's reply payload verbatim with the mapped HTTP status.
//! Contains no engine code (D16); the status byte is mapped by raw wire
//! value (see `statusToHttp`).
//!
//! Connection model: HTTP/1.1 with `Connection: close` — one request per
//! connection, then close. The SDK performs one fetch per collect(), so
//! keep-alive buys nothing and costs per-connection state. Transfer-Encoding
//! (chunked) is rejected outright to close the request-smuggling surface.
//!
//! Each read stage races a deadline completion (H-1), so a slow-loris client
//! that stalls mid-head or mid-body is disconnected and the accept loop
//! keeps serving (H-2).

const std = @import("std");
const builtin = @import("builtin");
const io = @import("io");
const adapter = @import("adapter");
const version_info = @import("version");
const worker_pool = @import("pool.zig");
const log = @import("log");

const IO = io.IO;
const socket_t = IO.socket_t;

/// Cap on the request head (request line + headers). Far above any real SDK
/// request and safely below memory pressure.
pub const max_header_bytes: usize = 16 * 1024;

/// Length of the CRLFCRLF head/body terminator `readHead` searches for.
const head_terminator_len: usize = 4;

/// How many events the io instance can track; the server holds at most an
/// accept, a recv, a send, and one deadline concurrently.
const io_entries = 64;

//HTTP surface

pub const Method = enum { get, post, options, other };

pub const ParsedHead = struct {
    method: Method,
    /// Request target (e.g. `/healthz`), borrowing from the head buffer.
    target: []const u8,
    content_length: ?u64 = null,
    chunked: bool = false,
    schema_version: ?u8 = null,
    package_id: ?[]const u8 = null,
    integrity: ?[]const u8 = null,
    origin: ?[]const u8 = null,
};

pub const ParseError = error{
    MalformedRequestLine,
    UnsupportedVersion,
    MalformedHeader,
};

/// Parses a request head (everything up to, but excluding, the CRLFCRLF
/// terminator). Pure — no allocator, no io — so it is unit-testable in
/// isolation.
pub fn parseHead(head: []const u8) ParseError!ParsedHead {
    var lines = std.mem.splitSequence(u8, head, "\r\n");
    const request_line = lines.next() orelse return error.MalformedRequestLine;

    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method_str = parts.next() orelse return error.MalformedRequestLine;
    const target = parts.next() orelse return error.MalformedRequestLine;
    const version_str = parts.next() orelse return error.MalformedRequestLine;
    if (parts.next() != null) return error.MalformedRequestLine;

    if (!std.mem.eql(u8, version_str, "HTTP/1.1") and
        !std.mem.eql(u8, version_str, "HTTP/1.0")) return error.UnsupportedVersion;

    var result = ParsedHead{ .method = undefined, .target = undefined };
    if (std.mem.eql(u8, method_str, "POST")) {
        result.method = .post;
    } else if (std.mem.eql(u8, method_str, "GET")) {
        result.method = .get;
    } else if (std.mem.eql(u8, method_str, "OPTIONS")) {
        result.method = .options;
    } else {
        result.method = .other;
    }
    result.target = target;

    while (lines.next()) |line| {
        if (line.len == 0) continue; // trailing blank line
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.MalformedHeader;
        const name = std.mem.trim(u8, line[0..colon], " ");
        const value = std.mem.trim(u8, line[colon + 1 ..], " ");
        if (name.len == 0) return error.MalformedHeader;

        if (std.ascii.eqlIgnoreCase(name, "content-length")) {
            result.content_length = std.fmt.parseInt(u64, value, 10) catch return error.MalformedHeader;
        } else if (std.ascii.eqlIgnoreCase(name, "transfer-encoding")) {
            result.chunked = true;
        } else if (std.ascii.eqlIgnoreCase(name, "x-fpkg-schema-version")) {
            result.schema_version = std.fmt.parseInt(u8, value, 10) catch return error.MalformedHeader;
        } else if (std.ascii.eqlIgnoreCase(name, "x-fpkg-package-id")) {
            result.package_id = value;
        } else if (std.ascii.eqlIgnoreCase(name, "x-fpkg-integrity")) {
            result.integrity = value;
        } else if (std.ascii.eqlIgnoreCase(name, "origin")) {
            result.origin = value;
        }
    }
    return result;
}

/// Worker reply status byte → HTTP status (specs/architecture/ingress.md).
/// The ingress switches on the raw wire value without importing the engine
/// (D16): 0 ok, 1 invalid_request, 2 invalid_payload, 3 unsupported_version,
/// 4 invalid_input, 5 buffer_overflow, 6 out_of_memory, 7 internal_error.
pub fn statusToHttp(status: u8) u16 {
    return switch (status) {
        0 => 200, // ok
        1, 2, 4 => 400, // invalid_request / invalid_payload / invalid_input
        3 => 415, // unsupported_version
        5 => 413, // buffer_overflow
        else => 502, // out_of_memory / internal_error / unknown
    };
}

fn reasonPhrase(status: u16) []const u8 {
    return switch (status) {
        200 => "OK",
        400 => "Bad Request",
        404 => "Not Found",
        405 => "Method Not Allowed",
        411 => "Length Required",
        413 => "Payload Too Large",
        415 => "Unsupported Media Type",
        502 => "Bad Gateway",
        else => "Error",
    };
}

/// Renders the client's remote address as `ip:port` for log attribution.
/// A healthz probe from curl or a load balancer sends no `Origin` header, so
/// the peer address is the only reliable source; `parsed.origin` (the browser
/// CORS header) is appended when present. `buf` must hold the formatted
/// address (IPv6 needs 46 bytes + port); too small returns a truncated label.
fn peerLabel(client: socket_t, buf: []u8) []const u8 {
    if (builtin.os.tag == .windows) return "unknown"; // getpeername via winsock only
    var address = std.net.Address{ .any = undefined };
    var len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.storage);
    std.posix.getpeername(client, &address.any, &len) catch return "unknown";
    return std.fmt.bufPrint(buf, "{}", .{address}) catch buf[0..buf.len];
}

// ── Server ────────────────────────────────────────────────────────────

pub const HttpServer = struct {
    allocator: std.mem.Allocator,
    io: IO,
    listen_socket: socket_t,
    listen_address: std.net.Address,
    client: ?socket_t = null,
    /// Content-Length cap for POST bodies (413 above it).
    max_body: u64,
    /// Per-stage receive deadline for HTTP connections (H-1).
    read_timeout_ns: u64,
    pool: *worker_pool.WorkerPool,

    accept_ctx: AcceptContext = .{},
    read_ctx: ReadContext = .{},
    write_ctx: WriteContext = .{},

    pub fn init(
        allocator: std.mem.Allocator,
        host: []const u8,
        port_number: u16,
        max_body: u64,
        read_timeout_ns: u64,
        pool: *worker_pool.WorkerPool,
    ) !HttpServer {
        const address = try std.net.Address.parseIp(host, port_number);

        var io_inst = try IO.init(io_entries, 0);
        errdefer io_inst.deinit();

        const socket = try io_inst.open_socket_tcp(std.posix.AF.INET, .{
            .rcvbuf = 0,
            .sndbuf = 0,
            .keepalive = null,
            .user_timeout_ms = 0,
            .nodelay = true,
        });
        errdefer io_inst.close_socket(socket);

        const resolved = try io_inst.listen(socket, address, .{ .backlog = 128 });
        return .{
            .allocator = allocator,
            .io = io_inst,
            .listen_socket = socket,
            .listen_address = resolved,
            .max_body = max_body,
            .read_timeout_ns = read_timeout_ns,
            .pool = pool,
        };
    }

    pub fn deinit(self: *HttpServer) void {
        // Cancel any in-flight operations so no completion fires into freed
        // memory, then close the sockets and the event loop.
        self.io.cancel(&self.accept_ctx.accept_completions[0]);
        self.io.cancel(&self.accept_ctx.accept_completions[1]);
        self.io.cancel(&self.accept_ctx.timeout_completion);
        self.io.cancel(&self.read_ctx.recv_completions[0]);
        self.io.cancel(&self.read_ctx.recv_completions[1]);
        self.io.cancel(&self.read_ctx.timeout_completion);
        self.io.cancel(&self.write_ctx.send_completion);
        self.closeClient();
        self.io.close_socket(self.listen_socket);
        self.io.deinit();
    }

    /// The bound port; useful when the caller asked for port 0.
    pub fn port(self: *const HttpServer) u16 {
        return self.listen_address.getPort();
    }

    /// Waits up to `timeout_ms` for a client, returning true if one was
    /// accepted. The wait races accept against a deadline completion so the
    /// ingress accept loop can observe its shutdown flag while idle (H-2).
    pub fn acceptWait(self: *HttpServer, timeout_ms: u32) !bool {
        const ctx = &self.accept_ctx;
        self.io.cancel(&ctx.timeout_completion);

        while (ctx.accept_busy[0] and ctx.accept_busy[1]) {
            try self.io.flush(.blocking);
        }
        const slot: u1 = if (ctx.accept_busy[0]) 1 else 0;

        ctx.server = self;
        ctx.generation +%= 1;
        ctx.current_slot = slot;
        ctx.resolved = false;
        ctx.accepted = false;
        ctx.client_socket = undefined;
        ctx.err = null;
        ctx.accept_busy[slot] = true;

        const deadline_ns = std.math.mul(u64, timeout_ms, std.time.ns_per_ms) catch
            std.math.maxInt(u64);
        const timeout_ns: u63 = @intCast(@min(deadline_ns, std.math.maxInt(u63)));
        if (timeout_ns > 0) {
            self.io.timeout(
                *AcceptContext,
                ctx,
                AcceptContext.on_timeout,
                &ctx.timeout_completion,
                timeout_ns,
            );
        }
        self.io.accept(
            *AcceptContext,
            ctx,
            AcceptContext.on_accept,
            &ctx.accept_completions[slot],
            self.listen_socket,
        );

        while (!ctx.resolved) {
            try self.io.flush(.blocking);
        }
        if (ctx.err) |err| return err;
        if (!ctx.accepted) return false;

        // Close the previous client, adopt the new one.
        self.closeClient();
        self.client = ctx.client_socket;
        return true;
    }

    /// Closes the current client connection, if any.
    pub fn closeClient(self: *HttpServer) void {
        if (self.client) |client| {
            self.io.close_socket(client);
            self.client = null;
        }
    }

    /// Reads exactly `content_length` bytes into `dest`, using whatever was
    /// already buffered past the head terminator first. Shared by the real
    /// POST body read and the 405 drain path below — the byte accounting
    /// (skip the terminator, count what's already buffered) is the one
    /// place this must be right; duplicating it a second time is how the
    /// original off-by-4 happened.
    fn drainBody(
        self: *HttpServer,
        client: socket_t,
        head_buf: []const u8,
        head_end: usize,
        head_len: usize,
        dest: []u8,
    ) !void {
        const body_start = head_end + head_terminator_len;
        const buffered = head_len - body_start;
        const from_buf = @min(buffered, dest.len);
        @memcpy(dest[0..from_buf], head_buf[body_start .. body_start + from_buf]);
        var filled = from_buf;
        while (filled < dest.len) {
            const n = try self.recvSome(client, dest[filled..]);
            if (n == 0) return error.EndOfStream;
            filled += n;
        }
    }

    /// Reads and discards up to `count` body bytes (buffered head bytes
    /// first, then the socket, in bounded chunks). Used to reject a request
    /// while still draining the declared body so a well-formed client sees
    /// the error response instead of an RST from closing with unread data
    /// (macOS/Linux reset a socket closed with pending received bytes).
    /// Every recv races the H-1 deadline, so a client that stalls mid-body
    /// is dropped instead of wedging the accept loop.
    fn discardBody(
        self: *HttpServer,
        client: socket_t,
        head_end: usize,
        head_len: usize,
        count: usize,
    ) void {
        const body_start = head_end + head_terminator_len;
        const buffered = head_len - body_start;
        var remaining = count - @min(buffered, count);
        var scratch: [512]u8 = undefined;
        while (remaining > 0) {
            const n = self.recvSome(client, scratch[0..@min(scratch.len, remaining)]) catch break;
            if (n == 0) break;
            remaining -= n;
        }
    }

    /// Serves one HTTP request on the accepted client: read head, parse,
    /// boundary-check, forward to the pool, relay the reply, close. The
    /// caller closes the client afterwards (or on error).
    pub fn handleConnection(self: *HttpServer, allocator: std.mem.Allocator) !void {
        const client = self.client orelse return error.NotConnected;
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();

        // Flow trace (specs/architecture/logging.md, S3b): flow lifecycle
        // lines are info (visible at the default level); the request access
        // line and byte-count detail stay at debug.
        var peer_buf: [64]u8 = undefined;
        const peer = peerLabel(client, &peer_buf);
        log.ingress.debug("ingress: connection accepted from {s}", .{peer});

        // 1. Bounded head read (request line + headers).
        var head_buf: [max_header_bytes]u8 = undefined;
        const head = self.readHead(client, &head_buf) catch |err| {
            if (err == error.HeadersTooLarge) {
                try self.replyError(client, 413, "request headers too large", null);
                return;
            }
            return err;
        };

        // 2. Parse (errors carry their own status mapping).
        const parsed = parseHead(head_buf[0..head.end]) catch |err| {
            try self.replyError(client, 400, @errorName(err), null);
            return;
        };
        if (parsed.content_length) |cl| {
            log.ingress.debug("ingress: {s} {s} (content-length {d}) from {s}", .{ @tagName(parsed.method), parsed.target, cl, peer });
        } else {
            log.ingress.debug("ingress: {s} {s} from {s}", .{ @tagName(parsed.method), parsed.target, peer });
        }

        if (parsed.method == .options) {
            try self.replyPreflight(client, parsed.origin);
            return;
        }

        // 3. Route.
        if (parsed.method == .get) {
            if (std.mem.eql(u8, parsed.target, "/healthz")) {
                var body_buf: [128]u8 = undefined;
                const body = std.fmt.bufPrint(
                    &body_buf,
                    "{{\"status\":\"ok\",\"version\":\"{s}\"}}",
                    .{version_info.version},
                ) catch unreachable;
                // Attribute the probe to the client's real remote address:
                // monitoring/load-balancer probes send no Origin header, so
                // the peer address is the meaningful source; a browser probe's
                // Origin header (CORS) is appended when present.
                if (parsed.origin) |origin| {
                    log.ingress.info("ingress: healthz probe from {s} (origin {s})", .{ peer, origin });
                } else {
                    log.ingress.info("ingress: healthz probe from {s}", .{peer});
                }
                try self.reply(client, 200, "application/json", body, null, parsed.origin);
            } else {
                try self.replyError(client, 404, "not found", null);
            }
            return;
        }

        if (parsed.method == .other) {
            // Unsupported method with a real body (PUT/DELETE/etc): drain
            // it before closing, bounded by max_body, so a well-formed
            // client sees a clean 405 instead of a reset. Drain within the
            // cap only; an attacker-declared oversized length here closes
            // without reading so a rejected request cannot force us to read
            // arbitrary attacker-controlled bytes (the POST 413 path drains
            // its declared body — see below — because a browser SDK client
            // reliably sends it).
            if (parsed.content_length) |len| {
                if (len <= self.max_body) {
                    const scratch = a.alloc(u8, @intCast(len)) catch null;
                    if (scratch) |buf| self.drainBody(client, &head_buf, head.end, head.len, buf) catch {};
                }
            }
            log.ingress.warn("ingress: unsupported method {s} from {s}", .{ @tagName(parsed.method), parsed.origin orelse "unknown" });
            try self.replyError(client, 405, "method not allowed", parsed.origin);
            return;
        }

        // POST only beyond this point.
        if (parsed.chunked) {
            log.ingress.warn("ingress: chunked transfer from {s}", .{parsed.origin orelse "unknown"});
            try self.replyError(client, 400, "chunked transfer not supported", null);
            return;
        }
        const content_length = parsed.content_length orelse {
            log.ingress.warn("ingress: missing content-length from {s}", .{parsed.origin orelse "unknown"});
            try self.replyError(client, 411, "content-length required", null);
            return;
        };
        // Boundary: reject before reading the body.
        if (content_length > self.max_body) {
            // Drain the declared body so a well-formed client sees a clean
            // 413 instead of an RST from closing with unread data. The
            // per-recv H-1 deadline bounds a client that stalls mid-body;
            // a client that streams is bounded by the bytes it sends.
            self.discardBody(client, head.end, head.len, @intCast(content_length));
            log.ingress.warn("ingress: request body {d} exceeds max {d} from {s}", .{ content_length, self.max_body, parsed.origin orelse "unknown" });
            try self.replyError(client, 413, "request body too large", parsed.origin);
            return;
        }

        // 4. Read the body (bytes past the head terminator first).
        const body = try a.alloc(u8, @intCast(content_length));
        try self.drainBody(client, &head_buf, head.end, head.len, body);

        // 5. Boundary checks.
        if (parsed.integrity) |expected| {
            if (!integrityMatches(expected, body)) {
                log.ingress.warn("ingress: integrity mismatch from {s}", .{parsed.origin orelse "unknown"});
                try self.replyError(client, 400, "integrity mismatch", null);
                return;
            }
        }
        if (parsed.schema_version) |v| {
            if (v != 1 and v != 2) {
                log.ingress.warn("ingress: unsupported schema version {d} from {s}", .{ v, parsed.origin orelse "unknown" });
                try self.replyError(client, 415, "unsupported schema version", null);
                return;
            }
        }

        // 6. Wrap in an FPKG frame and forward to the pool.
        const frame_buf = try a.alloc(u8, io.frame.header_size + body.len);
        const frame = adapter.buildFrame(.signal_package, .binary, body, frame_buf) catch {
            try self.replyError(client, 400, "invalid body", null);
            return;
        };
        log.ingress.info("ingress: signal received from client, forwarding to worker", .{});
        log.ingress.debug("ingress: forwarding to worker ({d} payload bytes)", .{body.len});
        const worker_reply = self.pool.request(a, frame) catch |err| {
            log.ingress.warn("ingress: worker request failed: {s}", .{@errorName(err)});
            try self.replyError(client, 502, "worker unavailable", null);
            return;
        };

        // 7. Relay the payload verbatim with the mapped status.
        const payload = worker_reply[io.frame.header_size..];
        if (payload.len < 1) {
            try self.replyError(client, 502, "malformed worker reply", null);
            return;
        }
        const http_status = statusToHttp(payload[0]);
        log.ingress.info("ingress: worker reply status {d} -> http {d}", .{ payload[0], http_status });
        try self.reply(client, http_status, "application/octet-stream", payload, "fingerprint-result", parsed.origin);
        log.ingress.info("ingress: reply relayed", .{});
        log.ingress.debug("ingress: relayed reply ({d} bytes)", .{payload.len});
    }

    /// Reads the request head up to the CRLFCRLF terminator, bounded by
    /// `buf.len`. Returns the terminator offset and the total bytes read
    /// (the tail may already hold body bytes).
    fn readHead(self: *HttpServer, client: socket_t, buf: []u8) !struct { end: usize, len: usize } {
        var filled: usize = 0;
        while (filled < buf.len) {
            const n = try self.recvSome(client, buf[filled..]);
            if (n == 0) return error.EndOfStream;
            filled += n;
            if (std.mem.indexOf(u8, buf[0..filled], "\r\n\r\n")) |end| {
                return .{ .end = end, .len = filled };
            }
        }
        return error.HeadersTooLarge;
    }

    /// Receives up to `buf.len` bytes, returning how many arrived (0 = clean
    /// peer close). Each stage races the read deadline (H-1), so a stalled
    /// client cannot wedge the accept loop.
    fn recvSome(self: *HttpServer, client: socket_t, buf: []u8) !usize {
        const ctx = &self.read_ctx;
        // Cancel a leftover deadline from a previous read (the recv may have
        // won before the deadline expired).
        self.io.cancel(&ctx.timeout_completion);

        while (ctx.recv_busy[0] and ctx.recv_busy[1]) {
            try self.io.flush(.blocking);
        }
        const slot: u1 = if (ctx.recv_busy[0]) 1 else 0;

        ctx.server = self;
        ctx.generation +%= 1;
        ctx.current_slot = slot;
        ctx.client = client;
        ctx.buf = buf;
        ctx.received = 0;
        ctx.resolved = false;
        ctx.err = null;
        ctx.recv_busy[slot] = true;

        const timeout_ns: u63 = @intCast(@min(self.read_timeout_ns, std.math.maxInt(u63)));
        if (timeout_ns > 0) {
            self.io.timeout(
                *ReadContext,
                ctx,
                ReadContext.on_timeout,
                &ctx.timeout_completion,
                timeout_ns,
            );
        }
        self.io.recv(
            *ReadContext,
            ctx,
            ReadContext.on_recv,
            &ctx.recv_completions[slot],
            client,
            buf,
        );
        while (!ctx.resolved) {
            try self.io.flush(.blocking);
        }
        if (ctx.err) |err| return err;
        return ctx.received;
    }

    /// Sends the whole slice, resubmitting on partial sends.
    fn sendAll(self: *HttpServer, client: socket_t, data: []const u8) !void {
        if (data.len == 0) return;
        const ctx = &self.write_ctx;
        ctx.server = self;
        ctx.client = client;
        ctx.data = data;
        ctx.sent = 0;
        ctx.resolved = false;
        ctx.err = null;

        self.io.send(
            *WriteContext,
            ctx,
            WriteContext.on_send,
            &ctx.send_completion,
            client,
            data,
        );
        while (!ctx.resolved) {
            try self.io.flush(.blocking);
        }
        if (ctx.err) |err| return err;
    }

    /// Headers the browser SDK sends and the preflight must allow, plus the
    /// two methods the ingress actually accepts (D16: no engine, so nothing
    /// else needs to reach it). The ingress is a multi-tenant collector — any
    /// site embedding the SDK is a legitimate caller, there is no session/cookie
    /// auth on this path, so reflecting the caller's Origin (or `*` when absent,
    /// e.g. a non-browser client) is the same trust boundary as a wildcard.
    const cors_allow_headers = "content-type, x-fpkg-schema-version, x-fpkg-sdk-version, x-fpkg-package-id, x-fpkg-integrity";
    const cors_allow_methods = "POST, OPTIONS";
    const cors_max_age_seconds = 86400;

    fn writeCorsHeaders(writer: anytype, origin: ?[]const u8) !void {
        if (origin) |o| {
            try writer.print("access-control-allow-origin: {s}\r\nvary: origin\r\n", .{o});
        } else {
            try writer.writeAll("access-control-allow-origin: *\r\n");
        }
    }

    /// Sends a complete HTTP response with `connection: close`.
    fn reply(
        self: *HttpServer,
        client: socket_t,
        status: u16,
        content_type: []const u8,
        body: []const u8,
        message_type: ?[]const u8,
        origin: ?[]const u8,
    ) !void {
        var head_buf: [768]u8 = undefined;
        var stream = std.io.fixedBufferStream(&head_buf);
        const w = stream.writer();
        try w.print("HTTP/1.1 {d} {s}\r\ncontent-type: {s}\r\n", .{ status, reasonPhrase(status), content_type });
        if (message_type) |mt| try w.print("x-fpkg-message-type: {s}\r\n", .{mt});
        try writeCorsHeaders(w, origin);
        try w.print("content-length: {d}\r\nconnection: close\r\n\r\n", .{body.len});

        try self.sendAll(client, stream.getWritten());
        if (body.len > 0) try self.sendAll(client, body);
    }

    fn replyError(self: *HttpServer, client: socket_t, status: u16, reason: []const u8, origin: ?[]const u8) !void {
        try self.reply(client, status, "text/plain", reason, null, origin);
    }

    fn replyPreflight(self: *HttpServer, client: socket_t, origin: ?[]const u8) !void {
        var head_buf: [512]u8 = undefined;
        var stream = std.io.fixedBufferStream(&head_buf);
        const w = stream.writer();
        try w.writeAll("HTTP/1.1 204 No Content\r\n");
        try writeCorsHeaders(w, origin);
        try w.print(
            "access-control-allow-methods: {s}\r\naccess-control-allow-headers: {s}\r\naccess-control-max-age: {d}\r\ncontent-length: 0\r\nconnection: close\r\n\r\n",
            .{ cors_allow_methods, cors_allow_headers, cors_max_age_seconds },
        );
        try self.sendAll(client, stream.getWritten());
    }
};

/// Compares `x-fpkg-integrity` (`sha256-<64 hex>`, case-insensitive) against
/// the SHA-256 of the body.
fn integrityMatches(expected: []const u8, body: []const u8) bool {
    if (!std.mem.startsWith(u8, expected, "sha256-")) return false;
    const expected_hex = expected["sha256-".len..];
    if (expected_hex.len != 64) return false;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(body, &digest, .{});
    var hex_buf: [64]u8 = undefined;
    const actual = std.fmt.bufPrint(&hex_buf, "{s}", .{std.fmt.fmtSliceHexLower(&digest)}) catch unreachable;
    return std.ascii.eqlIgnoreCase(expected_hex, actual);
}

// ── Accept race (H-1/H-2) ─────────────────────────────────────────────

const AcceptContext = struct {
    server: *HttpServer = undefined,
    accept_completions: [2]IO.Completion = .{ IO.Completion.init(), IO.Completion.init() },
    accept_busy: [2]bool = .{ false, false },
    timeout_completion: IO.Completion = IO.Completion.init(),
    /// Bumped per acceptWait; a stale timeout (accept won first) no-ops.
    generation: u32 = 0,
    current_slot: u1 = 0,
    resolved: bool = false,
    accepted: bool = false,
    client_socket: socket_t = undefined,
    err: ?anyerror = null,

    fn on_accept(
        ctx: *AcceptContext,
        completion: *IO.Completion,
        result: IO.AcceptError!socket_t,
    ) void {
        const slot: u1 = if (completion == &ctx.accept_completions[0]) 0 else 1;
        ctx.accept_busy[slot] = false;

        if (slot != ctx.current_slot or ctx.resolved) return; // stale

        const socket = result catch |err| {
            ctx.resolved = true;
            ctx.err = err;
            return;
        };
        ctx.accepted = true;
        ctx.client_socket = socket;
        ctx.resolved = true;
        // The wait-deadline is still queued; cancel it so the next acceptWait
        // can reuse the completion struct safely.
        ctx.server.io.cancel(&ctx.timeout_completion);
    }

    fn on_timeout(
        ctx: *AcceptContext,
        completion: *IO.Completion,
        result: IO.TimeoutError!void,
    ) void {
        _ = completion;
        _ = result catch unreachable;
        if (ctx.resolved) return; // stale: the accept won first
        ctx.resolved = true;
        // Stop the pending accept so the socket can be closed cleanly; the
        // aborted delivery (error.Canceled) frees the slot.
        ctx.server.io.cancel(&ctx.accept_completions[ctx.current_slot]);
    }
};

// ── Read race (H-1) ───────────────────────────────────────────────────

const ReadContext = struct {
    server: *HttpServer = undefined,
    recv_completions: [2]IO.Completion = .{ IO.Completion.init(), IO.Completion.init() },
    recv_busy: [2]bool = .{ false, false },
    timeout_completion: IO.Completion = IO.Completion.init(),
    generation: u32 = 0,
    current_slot: u1 = 0,
    client: socket_t = undefined,
    buf: []u8 = &.{},
    received: usize = 0,
    resolved: bool = false,
    err: ?anyerror = null,

    fn on_recv(
        ctx: *ReadContext,
        completion: *IO.Completion,
        result: IO.RecvError!usize,
    ) void {
        const slot: u1 = if (completion == &ctx.recv_completions[0]) 0 else 1;
        ctx.recv_busy[slot] = false;

        if (slot != ctx.current_slot or ctx.resolved) return; // stale

        const n = result catch |err| {
            ctx.resolved = true;
            ctx.err = err;
            return;
        };
        if (n == 0) {
            // Clean peer close.
            ctx.resolved = true;
            ctx.err = error.EndOfStream;
            return;
        }
        ctx.received = n;
        ctx.resolved = true;
    }

    fn on_timeout(
        ctx: *ReadContext,
        completion: *IO.Completion,
        result: IO.TimeoutError!void,
    ) void {
        _ = completion;
        _ = result catch unreachable;
        if (ctx.resolved) return; // stale: the recv won first
        ctx.resolved = true;
        ctx.err = error.ConnectionTimedOut;
        // Stop the pending recv so the socket can be closed cleanly; the
        // aborted delivery (error.Canceled) frees the slot.
        ctx.server.io.cancel(&ctx.recv_completions[ctx.current_slot]);
    }
};

// ── Write ─────────────────────────────────────────────────────────────

const WriteContext = struct {
    server: *HttpServer = undefined,
    send_completion: IO.Completion = IO.Completion.init(),
    client: socket_t = undefined,
    data: []const u8 = &.{},
    sent: usize = 0,
    resolved: bool = false,
    err: ?anyerror = null,

    fn on_send(
        ctx: *WriteContext,
        completion: *IO.Completion,
        result: IO.SendError!usize,
    ) void {
        _ = completion;
        if (ctx.resolved) return;
        const n = result catch |err| {
            ctx.resolved = true;
            ctx.err = err;
            return;
        };
        if (n == 0) {
            // A 0-byte send on a non-empty payload means the connection is
            // gone; do not loop forever.
            ctx.resolved = true;
            ctx.err = error.ConnectionResetByPeer;
            return;
        }
        ctx.sent += n;
        if (ctx.sent == ctx.data.len) {
            ctx.resolved = true;
            return;
        }
        // Partial send: continue with the remainder.
        ctx.server.io.send(
            *WriteContext,
            ctx,
            WriteContext.on_send,
            &ctx.send_completion,
            ctx.client,
            ctx.data[ctx.sent..],
        );
    }
};
