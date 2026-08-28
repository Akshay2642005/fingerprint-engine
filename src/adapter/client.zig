//! Pooled worker client for the HTTP ingress (S4-b, story s4-ingress-http).
//!
//! The ingress is a TCP *client* to the workers: it opens long-lived pooled
//! connections and exchanges FPKG frames over them. `TcpClient` mirrors
//! `Tcp`'s structure — the same H-1 deadline race, the same slot bookkeeping,
//! the same framing — but as an outbound client. The worker serves one
//! connection at a time, so a pooled connection is the concurrency unit:
//! the pool (S4-d) wraps one `TcpClient` per desired in-flight request.
//!
//! Not a `Transport` (it never accepts; the worker is the server), but it
//! reuses `adapter.buildFrame`/`adapter.decodeFrame` so framing stays
//! single-source (design §7, D16).

const std = @import("std");
const io = @import("io");
const transport = @import("transport.zig");

const IO = io.IO;
const socket_t = IO.socket_t;

/// How many events the io instance can track; the client holds at most a
/// connect, a recv, a send, and one deadline concurrently.
const io_entries = 64;

pub const TcpClient = struct {
    allocator: std.mem.Allocator,
    io: IO,
    socket: socket_t,
    address: std.net.Address,
    /// Per-frame receive deadline (0 disables), enforced by a deadline
    /// completion racing each read stage (H-1).
    idle_timeout_ns: u64,

    connect_ctx: ConnectContext = .{},
    read_ctx: ReadContext = .{},
    write_ctx: WriteContext = .{},

    pub fn init(
        allocator: std.mem.Allocator,
        host: []const u8,
        port_number: u16,
        idle_timeout_ns: u64,
    ) !TcpClient {
        const address = try transport.resolveHost(allocator, host, port_number);

        var io_inst = try IO.init(io_entries, 0);
        errdefer io_inst.deinit();

        const socket = try io_inst.open_socket_tcp(std.posix.AF.INET, .{
            .rcvbuf = 0,
            .sndbuf = 0,
            .keepalive = null,
            .user_timeout_ms = 0,
            .nodelay = true,
        });
        return .{
            .allocator = allocator,
            .io = io_inst,
            .socket = socket,
            .address = address,
            .idle_timeout_ns = idle_timeout_ns,
        };
    }

    /// Cancels every in-flight completion so no callback fires into freed
    /// memory, then closes the socket and the event loop. Safe to call after
    /// a failed `connect` — the caller owns the socket (io.connect leaves it
    /// open on error) and close() is the single teardown path.
    pub fn close(self: *TcpClient) void {
        self.io.cancel(&self.connect_ctx.connect_completions[0]);
        self.io.cancel(&self.connect_ctx.connect_completions[1]);
        self.io.cancel(&self.connect_ctx.timeout_completion);
        self.io.cancel(&self.read_ctx.recv_completions[0]);
        self.io.cancel(&self.read_ctx.recv_completions[1]);
        self.io.cancel(&self.read_ctx.timeout_completion);
        self.io.cancel(&self.write_ctx.send_completion);
        self.io.close_socket(self.socket);
        self.io.deinit();
    }

    /// Connects to the worker, racing `io.connect` against a deadline so a
    /// dead or unreachable worker is bounded (`deadline_ns` of 0 waits
    /// forever; H-1 pattern). On a timeout win the pending connect is
    /// cancelled and `error.ConnectionTimedOut` surfaces on every platform.
    pub fn connect(self: *TcpClient, deadline_ns: u64) !void {
        const ctx = &self.connect_ctx;
        // Cancel a leftover deadline from a previous call (the connect may
        // have won before the deadline expired). Timeouts have no kernel
        // state, so this is safe even mid-flight.
        self.io.cancel(&ctx.timeout_completion);

        // A previous connect that timed out cancelled its connect; the
        // aborted delivery (error.Canceled) may still be pending. Flush until
        // a completion slot is free — a busy slot always has a delivery
        // coming, so this is bounded.
        while (ctx.connect_busy[0] and ctx.connect_busy[1]) {
            try self.io.flush(.blocking);
        }
        const slot: u1 = if (ctx.connect_busy[0]) 1 else 0;

        ctx.client = self;
        ctx.generation +%= 1;
        ctx.current_slot = slot;
        ctx.resolved = false;
        ctx.connected = false;
        ctx.err = null;
        ctx.connect_busy[slot] = true;

        if (deadline_ns > 0) {
            const timeout_ns: u63 = @intCast(@min(deadline_ns, std.math.maxInt(u63)));
            self.io.timeout(
                *ConnectContext,
                ctx,
                ConnectContext.on_timeout,
                &ctx.timeout_completion,
                timeout_ns,
            );
        }
        self.io.connect(
            *ConnectContext,
            ctx,
            ConnectContext.on_connect,
            &ctx.connect_completions[slot],
            self.socket,
            self.address,
        );

        while (!ctx.resolved) {
            try self.io.flush(.blocking);
        }
        if (ctx.err) |err| return err;
    }

    /// One inbound FPKG frame from the worker; memory is owned by the
    /// caller. The header and payload are read with per-stage deadlines
    /// (H-1), so a silent or stalled worker trips `error.ConnectionTimedOut`
    /// and the pool can drop the connection.
    pub fn readFrame(self: *TcpClient, allocator: std.mem.Allocator) ![]const u8 {
        var header_buf: [io.frame.header_size]u8 = undefined;
        try self.recvExact(&header_buf);

        var r = io.Reader.init(&header_buf);
        const header = try io.frame.FrameHeader.decode(&r);
        if (header.payload_len > transport.max_payload) return error.PayloadTooLarge;

        const frame_len = io.frame.header_size + header.payload_len;
        const full = try allocator.alloc(u8, frame_len);
        errdefer allocator.free(full);
        @memcpy(full[0..io.frame.header_size], &header_buf);
        // A zero-length payload is a complete frame after the header — an
        // empty recv would wait on a readiness event that never comes.
        if (header.payload_len > 0) {
            try self.recvExact(full[io.frame.header_size..]);
        }

        _ = try transport.decodeFrame(full); // validates integrity
        return full;
    }

    pub fn writeFrame(self: *TcpClient, frame: []const u8) !void {
        const ctx = &self.write_ctx;
        ctx.client = self;
        ctx.frame = frame;
        ctx.sent = 0;
        ctx.resolved = false;
        ctx.err = null;

        self.io.send(
            *WriteContext,
            ctx,
            WriteContext.on_send,
            &ctx.send_completion,
            self.socket,
            frame,
        );
        while (!ctx.resolved) {
            try self.io.flush(.blocking);
        }
        if (ctx.err) |err| return err;
    }

    /// Receives exactly `buf.len` bytes, racing each recv completion against
    /// the idle deadline (H-1). Partial reads keep the deadline running and
    /// resubmit for the remainder, so a worker that stalls mid-chunk is still
    /// bounded.
    fn recvExact(self: *TcpClient, buf: []u8) !void {
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

        ctx.client = self;
        ctx.generation +%= 1;
        ctx.current_slot = slot;
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
            self.socket,
            buf,
        );
        while (!ctx.resolved) {
            try self.io.flush(.blocking);
        }
        if (ctx.err) |err| return err;
    }
};

// ── Connect race (H-1) ────────────────────────────────────────────────

const ConnectContext = struct {
    client: *TcpClient = undefined,
    connect_completions: [2]IO.Completion = .{ IO.Completion.init(), IO.Completion.init() },
    /// Whether each connect completion slot is in flight (op started, or a
    /// cancelled op whose aborted delivery is still pending).
    connect_busy: [2]bool = .{ false, false },
    timeout_completion: IO.Completion = IO.Completion.init(),
    /// Bumped per connect; a stale timeout (connect won first) no-ops.
    generation: u32 = 0,
    current_slot: u1 = 0,
    resolved: bool = false,
    connected: bool = false,
    err: ?anyerror = null,

    fn on_connect(
        ctx: *ConnectContext,
        completion: *IO.Completion,
        result: IO.ConnectError!void,
    ) void {
        const slot: u1 = if (completion == &ctx.connect_completions[0]) 0 else 1;
        // The delivery was processed; the slot is reusable.
        ctx.connect_busy[slot] = false;

        if (slot != ctx.current_slot or ctx.resolved) {
            // Stale: this connect was cancelled (the deadline won) and the
            // aborted delivery arrived late, or a newer connect owns the
            // slot. The socket stays open for close().
            return;
        }

        result catch |err| {
            ctx.resolved = true;
            ctx.err = err;
            return;
        };
        ctx.connected = true;
        ctx.resolved = true;
        // The wait-deadline is still queued; cancel it so the next connect
        // can reuse the completion struct safely.
        ctx.client.io.cancel(&ctx.timeout_completion);
    }

    fn on_timeout(
        ctx: *ConnectContext,
        completion: *IO.Completion,
        result: IO.TimeoutError!void,
    ) void {
        _ = completion;
        _ = result catch unreachable;
        if (ctx.resolved) return; // stale: the connect won first
        ctx.resolved = true;
        ctx.err = error.ConnectionTimedOut;
        // Stop the pending connect so the socket can be closed cleanly; the
        // aborted delivery (error.Canceled) frees the slot.
        ctx.client.io.cancel(&ctx.connect_completions[ctx.current_slot]);
    }
};

// ── Read race (H-1) ───────────────────────────────────────────────────

const ReadContext = struct {
    client: *TcpClient = undefined,
    recv_completions: [2]IO.Completion = .{ IO.Completion.init(), IO.Completion.init() },
    /// Whether each recv completion slot is in flight (op started, or a
    /// cancelled op whose aborted delivery is still pending).
    recv_busy: [2]bool = .{ false, false },
    timeout_completion: IO.Completion = IO.Completion.init(),
    /// Bumped per recvExact; a stale timeout (recv won first) no-ops.
    generation: u32 = 0,
    current_slot: u1 = 0,
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
        // remainder on the same slot (a worker that stalls mid-chunk is
        // still bounded by H-1).
        ctx.recv_busy[slot] = true;
        ctx.client.io.recv(
            *ReadContext,
            ctx,
            ReadContext.on_recv,
            &ctx.recv_completions[slot],
            ctx.client.socket,
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
        ctx.client.io.cancel(&ctx.recv_completions[ctx.current_slot]);
    }
};

// ── Write ─────────────────────────────────────────────────────────────

const WriteContext = struct {
    client: *TcpClient = undefined,
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
        ctx.client.io.send(
            *WriteContext,
            ctx,
            WriteContext.on_send,
            &ctx.send_completion,
            ctx.client.socket,
            ctx.frame[ctx.sent..],
        );
    }
};
