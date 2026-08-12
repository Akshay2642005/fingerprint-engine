/// TCP request/response transport (design §7.3, D16): an FPKG-framed
/// server for the ingress → worker inbound path. One client at a time;
/// the worker drives `accept → readFrame → process → writeFrame` and this
/// type owns only the socket state. Frames are read with the io layer, so
/// integrity is validated at the boundary.
///
/// H-1/H-2 (worker-resilience.md S1): every socket operation is completion-
/// based over `io.IO` (epoll on Linux, IOCP on Windows, kqueue on Darwin).
/// An idle or slow-loris client cannot wedge the single-client accept loop:
/// reads race a deadline completion and fail `error.ConnectionTimedOut` on
/// every platform, after which the worker closes the client. `acceptWait`
/// bounds the accept wait so the worker can observe its shutdown flag while
/// idle. There is no SO_RCVTIMEO anywhere — it is unreliable on Windows once
/// a socket has been non-blocking (see worker-resilience.md).
///
/// Cancellation and slots: `cancel()` guarantees the user callback runs
/// exactly once (error.Canceled) — synchronously on epoll/darwin, via the
/// aborted IOCP delivery on Windows. Because an aborted delivery can arrive
/// after `cancel` returns, the accept and read contexts rotate between two
/// completion slots and only reuse a slot whose delivery was processed (the
/// stale callback frees it). A slot is never reused while its kernel
/// operation could still deliver.
///
/// story: s1-bug001-timeouts-shutdown
const std = @import("std");
const io = @import("io");
const transport = @import("transport.zig");

const IO = io.IO;
const socket_t = IO.socket_t;

/// How many events the io instance can track; the worker holds at most an
/// accept, a recv, a send, and one deadline concurrently.
const io_entries = 64;

pub const Tcp = struct {
    allocator: std.mem.Allocator,
    io: IO,
    listen_socket: socket_t,
    listen_address: std.net.Address,
    client: ?socket_t = null,
    /// Per-connection receive deadline (0 disables), enforced by a deadline
    /// completion racing each read stage (H-1).
    idle_timeout_ns: u64,

    accept_ctx: AcceptContext = .{},
    read_ctx: ReadContext = .{},
    write_ctx: WriteContext = .{},

    pub fn init(
        allocator: std.mem.Allocator,
        host: []const u8,
        port_number: u16,
        idle_timeout_ns: u64,
    ) !Tcp {
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
            .idle_timeout_ns = idle_timeout_ns,
        };
    }

    pub fn deinit(self: *Tcp) void {
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
    pub fn port(self: *const Tcp) u16 {
        return self.listen_address.getPort();
    }

    /// Blocks until a client connects (a previous client, if any, is closed
    /// first — the transport serves one connection at a time). The accepted
    /// socket gets the idle receive deadline via the read race (H-1).
    pub fn accept(self: *Tcp) !void {
        _ = try self.acceptWait(0); // 0 = wait indefinitely
    }

    /// Waits up to `timeout_ms` for a client, returning true if one was
    /// accepted. The wait races accept against a deadline completion so the
    /// worker's accept loop can observe its shutdown flag while idle (H-2).
    pub fn acceptWait(self: *Tcp, timeout_ms: u32) !bool {
        const ctx = &self.accept_ctx;
        // Cancel a leftover wait-deadline from a previous call (the accept
        // may have won before the deadline expired). Timeouts have no kernel
        // state, so this is safe even mid-flight.
        self.io.cancel(&ctx.timeout_completion);

        // A previous acceptWait that timed out cancelled its accept; the
        // aborted delivery (error.Canceled) may still be pending. Flush until
        // a completion slot is free — a busy slot always has a delivery
        // coming, so this is bounded.
        while (ctx.accept_busy[0] and ctx.accept_busy[1]) {
            try self.io.flush(.blocking);
        }
        const slot: u1 = if (ctx.accept_busy[0]) 1 else 0;

        ctx.tcp = self;
        ctx.generation +%= 1;
        ctx.current_slot = slot;
        ctx.resolved = false;
        ctx.accepted = false;
        ctx.client_socket = undefined;
        ctx.err = null;
        ctx.accept_busy[slot] = true;

        const deadline_ns = std.math.mul(u64, timeout_ms, std.time.ns_per_ms) catch
            std.math.maxInt(u64);
        // io.timeout takes a u63 (positive signed range); clamp the deadline
        // so an absurd --idle-timeout-ms cannot overflow.
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

    /// Closes the current client connection, if any. Used to drop a client
    /// after a protocol error or idle timeout so it observes the disconnect
    /// instead of hanging; the accept loop then waits for the next
    /// connection.
    pub fn closeClient(self: *Tcp) void {
        if (self.client) |client| {
            self.io.close_socket(client);
            self.client = null;
        }
    }

    /// One inbound FPKG frame from the accepted client; memory is owned by
    /// the caller. The header and payload are read with per-stage deadlines
    /// (H-1), so a silent or slow client trips `error.ConnectionTimedOut`
    /// and the worker drops the connection.
    pub fn readFrame(self: *Tcp, allocator: std.mem.Allocator) ![]const u8 {
        const client = self.client orelse return error.NotConnected;

        var header_buf: [io.frame.header_size]u8 = undefined;
        try self.recvExact(client, &header_buf);

        var r = io.Reader.init(&header_buf);
        const header = try io.frame.FrameHeader.decode(&r);
        if (header.payload_len > transport.max_payload) return error.PayloadTooLarge;

        const frame_len = io.frame.header_size + header.payload_len;
        const full = try allocator.alloc(u8, frame_len);
        errdefer allocator.free(full);
        @memcpy(full[0..io.frame.header_size], &header_buf);
        try self.recvExact(client, full[io.frame.header_size..]);

        _ = try transport.decodeFrame(full); // validates integrity
        return full;
    }

    pub fn writeFrame(self: *Tcp, frame: []const u8) !void {
        const client = self.client orelse return error.NotConnected;
        const ctx = &self.write_ctx;
        ctx.tcp = self;
        ctx.frame = frame;
        ctx.sent = 0;
        ctx.resolved = false;
        ctx.err = null;

        self.io.send(
            *WriteContext,
            ctx,
            WriteContext.on_send,
            &ctx.send_completion,
            client,
            frame,
        );
        while (!ctx.resolved) {
            try self.io.flush(.blocking);
        }
        if (ctx.err) |err| return err;
    }

    /// Outbound events are a v1 no-op for tcp (no downstream consumer).
    pub fn publish(self: *Tcp, payload: []const u8) !void {
        _ = self;
        _ = payload;
    }

    /// Poison-frame handling is a v1 no-op for tcp.
    pub fn ack(self: *Tcp, frame: []const u8) void {
        _ = self;
        _ = frame;
    }

    /// Receives exactly `buf.len` bytes, racing each recv completion against
    /// the idle deadline (H-1). Partial reads keep the deadline running and
    /// resubmit for the remainder, so a slow-loris that stalls mid-chunk is
    /// still bounded.
    fn recvExact(self: *Tcp, client: socket_t, buf: []u8) !void {
        const ctx = &self.read_ctx;
        // Cancel the previous read's leftover deadline (the recv may have
        // won before the deadline expired). Timeouts have no kernel state,
        // so this is safe even mid-flight.
        self.io.cancel(&ctx.timeout_completion);

        // A previous read that timed out cancelled its recv; the aborted
        // delivery may still be pending. Flush until a slot is free.
        while (ctx.recv_busy[0] and ctx.recv_busy[1]) {
            try self.io.flush(.blocking);
        }
        const slot: u1 = if (ctx.recv_busy[0]) 1 else 0;

        ctx.tcp = self;
        ctx.generation +%= 1;
        ctx.current_slot = slot;
        ctx.client = client;
        ctx.buf = buf;
        ctx.filled = 0;
        ctx.resolved = false;
        ctx.err = null;
        ctx.recv_busy[slot] = true;

        if (self.idle_timeout_ns > 0) {
            const timeout_ns: u63 = @intCast(@min(self.idle_timeout_ns, std.math.maxInt(u63)));
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
    }
};

// ── Accept race (H-2) ─────────────────────────────────────────────────

const AcceptContext = struct {
    tcp: *Tcp = undefined,
    accept_completions: [2]IO.Completion = .{ IO.Completion.init(), IO.Completion.init() },
    /// Whether each accept completion slot is in flight (op started, or a
    /// cancelled op whose aborted delivery is still pending).
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
        // The delivery was processed; the slot is reusable.
        ctx.accept_busy[slot] = false;

        if (slot != ctx.current_slot or ctx.resolved) {
            // Stale: this accept was cancelled (a deadline won) and the
            // aborted delivery arrived late, or a newer acceptWait owns the
            // slot. Close a late-arriving socket so it cannot leak.
            if (result catch null) |client| ctx.tcp.io.close_socket(client);
            return;
        }

        ctx.accepted = true;
        ctx.client_socket = result catch |err| {
            ctx.err = err;
            ctx.resolved = true;
            return;
        };
        ctx.resolved = true;
        // The wait-deadline is still queued; cancel it so the next
        // acceptWait can reuse the completion struct safely.
        ctx.tcp.io.cancel(&ctx.timeout_completion);
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
        ctx.accepted = false;
        // Stop the pending accept so the listen socket is clean; the aborted
        // delivery (error.Canceled) frees the slot.
        ctx.tcp.io.cancel(&ctx.accept_completions[ctx.current_slot]);
    }
};

// ── Read race (H-1) ───────────────────────────────────────────────────

const ReadContext = struct {
    tcp: *Tcp = undefined,
    recv_completions: [2]IO.Completion = .{ IO.Completion.init(), IO.Completion.init() },
    /// Whether each recv completion slot is in flight (op started, or a
    /// cancelled op whose aborted delivery is still pending).
    recv_busy: [2]bool = .{ false, false },
    timeout_completion: IO.Completion = IO.Completion.init(),
    /// Bumped per recvExact; a stale timeout (recv won first) no-ops.
    generation: u32 = 0,
    current_slot: u1 = 0,
    client: socket_t = undefined,
    buf: []u8 = &.{},
    filled: usize = 0,
    resolved: bool = false,
    err: ?anyerror = null,

    fn on_recv(
        ctx: *ReadContext,
        completion: *IO.Completion,
        result: IO.RecvError!usize,
    ) void {
        const slot: u1 = if (completion == &ctx.recv_completions[0]) 0 else 1;
        // The delivery was processed; the slot is reusable.
        ctx.recv_busy[slot] = false;

        if (slot != ctx.current_slot or ctx.resolved) return; // stale

        const n = result catch |err| {
            ctx.resolved = true;
            ctx.err = err;
            return;
        };
        if (n == 0) {
            // Clean peer close; the frame read is over.
            ctx.resolved = true;
            ctx.err = error.EndOfStream;
            return;
        }
        ctx.filled += n;
        if (ctx.filled == ctx.buf.len) {
            ctx.resolved = true;
            return;
        }
        // Partial read: keep the same deadline and continue with the
        // remainder on the same slot (a slow-loris mid-chunk is still
        // bounded by H-1).
        ctx.recv_busy[slot] = true;
        ctx.tcp.io.recv(
            *ReadContext,
            ctx,
            ReadContext.on_recv,
            &ctx.recv_completions[slot],
            ctx.client,
            ctx.buf[ctx.filled..],
        );
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
        ctx.tcp.io.cancel(&ctx.recv_completions[ctx.current_slot]);
    }
};

// ── Write ─────────────────────────────────────────────────────────────

const WriteContext = struct {
    tcp: *Tcp = undefined,
    send_completion: IO.Completion = IO.Completion.init(),
    frame: []const u8 = &.{},
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
            // A 0-byte send on a non-empty frame means the connection is
            // gone; do not loop forever.
            ctx.resolved = true;
            ctx.err = error.ConnectionResetByPeer;
            return;
        }
        ctx.sent += n;
        if (ctx.sent == ctx.frame.len) {
            ctx.resolved = true;
            return;
        }
        // Partial send: continue with the remainder.
        ctx.tcp.io.send(
            *WriteContext,
            ctx,
            WriteContext.on_send,
            &ctx.send_completion,
            ctx.tcp.client.?,
            ctx.frame[ctx.sent..],
        );
    }
};

comptime {
    transport.check(Tcp);
}
