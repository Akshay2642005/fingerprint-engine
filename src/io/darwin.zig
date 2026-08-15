//! Completion-based io for Darwin (macOS/iOS/tvOS/watchOS) — kqueue
//! backend (worker-resilience.md S1). Adapted from TigerBeetle's
//! `src/io/darwin.zig` and trimmed to our flavor.
//!
//! Mechanics (as in TigerBeetle):
//! - `submit()` pushes the completion onto `completed`; the first
//!   `do_operation` pass performs the operation; on `error.WouldBlock` the
//!   completion moves to `io_pending`, from where `flush()` builds a kevent
//!   changelist (`EV.ADD | EV.ENABLE | EV.ONESHOT` — one-shot, so the kernel
//!   removes the filter after the first event).
//! - `flush()` submits the changelist and waits; every event maps back to
//!   its completion via `udata` and lands on `completed`; the second
//!   `do_operation` pass performs the real syscall (non-blocking sockets —
//!   a spurious event returns `WouldBlock` and re-queues onto `io_pending`).
//!
//! This backend requires libc (`std.posix.system` is a stub on Darwin
//! without it); build.zig links libc for darwin targets only. It is
//! compile-checked via `zig build worker -Dtarget=x86_64-macos`; runtime
//! coverage needs a Mac runner.

const std = @import("std");
const posix = std.posix;
const assert = std.debug.assert;

const common = @import("common.zig");
const QueueType = @import("queue.zig").QueueType;

pub const IO = struct {
    pub const TCPOptions = common.TCPOptions;
    pub const ListenOptions = common.ListenOptions;

    pub const FlushMode = enum {
        blocking,
        non_blocking,
    };

    kq: fd_t,
    time: common.TimeOS,
    /// Number of events submitted to the kernel and not yet harvested.
    io_inflight: usize = 0,
    /// Completions waiting for kernel registration (the kevent changelist).
    io_pending: QueueType(Completion) = .init(),
    timeouts: QueueType(Completion) = .init(),
    completed: QueueType(Completion) = .init(),
    run_for_ns_active: bool = false,

    pub fn init(entries: u12, flags: u32) !IO {
        _ = entries;
        _ = flags;

        const kq = try posix.kqueue();
        assert(kq > -1);
        return IO{ .kq = kq, .time = common.TimeOS.init() };
    }

    pub fn deinit(self: *IO) void {
        assert(self.kq > -1);
        posix.close(self.kq);
        self.kq = -1;
    }

    /// Monotonic nanoseconds since this IO instance was created.
    pub fn now(self: *const IO) u64 {
        return self.time.monotonic();
    }

    /// Non-blocking flush: submit queued io, poll once, drain.
    pub fn run(self: *IO) !void {
        assert(!self.run_for_ns_active);
        return self.flush(.non_blocking);
    }

    /// Blocking flush until a `nanoseconds` watchdog timeout fires. Used by
    /// tests and run-loops; the adapter races its own deadline instead.
    pub fn run_for_ns(self: *IO, nanoseconds: u63) !void {
        assert(!self.run_for_ns_active);
        self.run_for_ns_active = true;
        defer self.run_for_ns_active = false;

        const TimedOut = struct {
            timed_out: bool = false,

            fn on_timeout(
                ctx: *@This(),
                completion: *Completion,
                result: TimeoutError!void,
            ) void {
                _ = completion;
                _ = result catch unreachable;
                ctx.timed_out = true;
            }
        };

        var state = TimedOut{};
        var completion: Completion = undefined;

        self.timeout(
            *TimedOut,
            &state,
            TimedOut.on_timeout,
            &completion,
            nanoseconds,
        );

        while (!state.timed_out) {
            try self.flush(.blocking);
        }
    }

    /// One event-loop pass: expire timeouts, submit queued io, wait (or
    /// poll) for events, then drain every ready completion.
    pub fn flush(self: *IO, mode: FlushMode) !void {
        var events: [64]posix.Kevent = undefined;

        // Check timeouts and fill events with completions in io_pending
        // (they will be submitted through kevent). Timeouts that expired are
        // pushed to the completed queue.
        const next_timeout = self.flush_timeouts();
        const change_events = self.flush_io(&events);

        // Only call kevent() if we need to submit io events or if we need to
        // wait for completions.
        if (change_events > 0 or self.completed.empty()) {
            // Zero timeouts for kevent() implies a non-blocking poll.
            var ts = std.mem.zeroes(posix.timespec);
            var timeout_ptr: ?*const posix.timespec = &ts;

            // We need to wait (not poll) on kevent if there's nothing to
            // submit or complete. run() is non-blocking and run_for_ns()
            // always submits a timeout, so the only blocking wait without a
            // queued deadline is a bare wait for inflight kernel work — wait
            // indefinitely (kevent with a NULL timeout). macOS rejects
            // timeouts above 2^31 seconds with EINVAL, so a far-future
            // deadline is clamped to that bound; the caller's flush loop
            // re-waits if the clamped timeout fires.
            if (change_events == 0 and self.completed.empty()) {
                if (mode == .blocking) {
                    if (next_timeout) |timeout_ns| {
                        const secs = timeout_ns / std.time.ns_per_s;
                        if (secs > std.math.maxInt(i32)) {
                            ts.sec = std.math.maxInt(i32) - 1;
                            ts.nsec = std.time.ns_per_s - 1;
                        } else {
                            ts.nsec = @intCast(timeout_ns % std.time.ns_per_s);
                            ts.sec = @intCast(secs);
                        }
                    } else {
                        assert(self.io_inflight > 0);
                        timeout_ptr = null;
                    }
                } else if (self.io_inflight == 0) {
                    return;
                }
            }

            const new_events = try posix.kevent(
                self.kq,
                events[0..change_events],
                events[0..events.len],
                timeout_ptr,
            );

            // Mark the io events submitted only after kevent() successfully
            // processed them.
            self.io_inflight += change_events;
            self.io_inflight -= new_events;

            for (events[0..new_events]) |event| {
                const completion: *Completion = @ptrFromInt(event.udata);
                assert(completion.link.next == null);

                // The ONESHOT filter was consumed by this delivery.
                completion.registered = false;
                self.completed.push(completion);
            }
        }

        // Drain all ready completions. Callbacks may push new completions
        // (e.g. zero-delay timeouts) which are picked up in the same pass.
        while (self.completed.pop()) |completion| {
            (completion.callback)(Completion.Context{
                .io = self,
                .completion = completion,
            });
        }
    }

    fn flush_io(self: *IO, events: []posix.Kevent) usize {
        for (events, 0..) |*event, flushed| {
            const completion = self.io_pending.pop() orelse return flushed;

            const filter: i16 = switch (completion.operation) {
                .accept => posix.system.EVFILT.READ,
                .recv => posix.system.EVFILT.READ,
                .send => posix.system.EVFILT.WRITE,
                .connect => posix.system.EVFILT.WRITE,
                else => @panic("invalid completion operation queued for io"),
            };

            const ident: usize = switch (completion.operation) {
                .accept => |op| @intCast(op.socket),
                .recv => |op| @intCast(op.socket),
                .send => |op| @intCast(op.socket),
                .connect => |op| @intCast(op.socket),
                else => unreachable,
            };

            event.* = .{
                .ident = ident,
                .filter = filter,
                .flags = posix.system.EV.ADD |
                    posix.system.EV.ENABLE |
                    posix.system.EV.ONESHOT,
                .fflags = 0,
                .data = 0,
                .udata = @intFromPtr(completion),
            };

            completion.registered = true;
        }

        return events.len;
    }

    /// Moves expired timeouts onto `completed`; returns the min remaining
    /// nanoseconds until the next expiry (null when no timeouts are queued).
    fn flush_timeouts(self: *IO) ?u64 {
        var min_expires: ?u64 = null;

        var iterator = self.timeouts.iterate();
        while (iterator.next()) |completion| {
            const current = self.time.monotonic();
            const deadline = completion.operation.timeout.deadline;

            if (current >= deadline) {
                self.timeouts.remove(completion);
                self.completed.push(completion);
                continue;
            }

            const expires = deadline - current;

            if (min_expires) |current_min| {
                min_expires = @min(expires, current_min);
            } else {
                min_expires = expires;
            }
        }

        return min_expires;
    }

    /// This struct holds the data needed for a single IO operation.
    pub const Completion = struct {
        link: QueueType(Completion).Link = .{},
        context: ?*anyopaque,
        callback: *const fn (Context) void,
        operation: Operation,

        /// Set by `cancel`; the next drain short-circuits to
        /// `error.Canceled` instead of running `do_operation`, so a cancelled
        /// completion always completes exactly once.
        cancelled: bool = false,

        /// Whether this completion's EV.ONESHOT filter has been submitted to
        /// the kernel (flush_io) and not yet harvested. cancel uses this to
        /// EV_DELETE the registration instead of waiting for a readiness
        /// event that may never come.
        registered: bool = false,

        /// Benign initial state for completions that may be cancelled before
        /// their first submission (the adapter's defensive cancels). The
        /// callback is never invoked for a never-submitted completion.
        pub fn init() Completion {
            return .{
                .context = null,
                .callback = undefined,
                .operation = .{
                    .timeout = .{
                        .deadline = 0,
                    },
                },
            };
        }

        pub const Context = struct {
            io: *IO,
            completion: *Completion,
        };

        const Operation = union(enum) {
            accept: struct {
                socket: socket_t,
            },
            recv: struct {
                socket: socket_t,
                buf: []u8,
            },
            send: struct {
                socket: socket_t,
                buf: []const u8,
            },
            connect: struct {
                socket: socket_t,
                address: std.net.Address,

                /// Set after pass 1 parks with EINPROGRESS; pass 2 harvests
                /// the result via getsockoptError instead of re-connecting.
                pending: bool = false,
            },
            timeout: struct {
                deadline: u64,
            },
        };
    };

    fn submit(
        self: *IO,
        context: anytype,
        comptime callback: anytype,
        completion: *Completion,
        comptime op_tag: std.meta.Tag(Completion.Operation),
        op_data: std.meta.TagPayload(Completion.Operation, op_tag),
        comptime OperationImpl: type,
    ) void {
        const Callback = struct {
            fn onComplete(ctx: Completion.Context) void {
                // A cancelled completion completes exactly once, with
                // error.Canceled, without touching the kernel again.
                if (ctx.completion.cancelled) {
                    callback(
                        @ptrCast(@alignCast(ctx.completion.context)),
                        ctx.completion,
                        error.Canceled,
                    );
                    return;
                }

                const data = &@field(
                    ctx.completion.operation,
                    @tagName(op_tag),
                );

                const result = OperationImpl.do_operation(ctx, data);

                // Requeue onto io_pending if error.WouldBlock.
                switch (op_tag) {
                    .accept, .recv, .send, .connect => {
                        _ = result catch |err| switch (err) {
                            error.WouldBlock => {
                                ctx.completion.link = .{};
                                ctx.io.io_pending.push(ctx.completion);
                                return;
                            },
                            else => {},
                        };
                    },
                    else => {},
                }

                // The completion is finally ready to invoke the callback.
                callback(
                    @ptrCast(@alignCast(ctx.completion.context)),
                    ctx.completion,
                    result,
                );
            }
        };

        completion.* = .{
            .link = .{},
            .context = @ptrCast(context),
            .callback = Callback.onComplete,
            .operation = @unionInit(
                Completion.Operation,
                @tagName(op_tag),
                op_data,
            ),
        };

        switch (op_tag) {
            .timeout => self.timeouts.push(completion),
            else => self.completed.push(completion),
        }
    }

    pub const AcceptError = posix.AcceptError || error{Canceled};

    pub fn accept(
        self: *IO,
        comptime Context: type,
        context: Context,
        comptime callback: fn (
            context: Context,
            completion: *Completion,
            result: AcceptError!socket_t,
        ) void,
        completion: *Completion,
        socket: socket_t,
    ) void {
        self.submit(
            context,
            callback,
            completion,
            .accept,
            .{ .socket = socket },
            struct {
                fn do_operation(
                    _: Completion.Context,
                    op: anytype,
                ) AcceptError!socket_t {
                    const fd = try posix.accept(
                        op.socket,
                        null,
                        null,
                        posix.SOCK.NONBLOCK | posix.SOCK.CLOEXEC,
                    );

                    // Darwin doesn't support MSG_NOSIGNAL; the SO_NOSIGPIPE
                    // socket option does the same for all send()s.
                    common.setsockopt(
                        fd,
                        posix.SOL.SOCKET,
                        posix.SO.NOSIGPIPE,
                        1,
                    ) catch {};

                    return fd;
                }
            },
        );
    }

    pub const RecvError = posix.RecvFromError || error{Canceled};

    pub fn recv(
        self: *IO,
        comptime Context: type,
        context: Context,
        comptime callback: fn (
            context: Context,
            completion: *Completion,
            result: RecvError!usize,
        ) void,
        completion: *Completion,
        socket: socket_t,
        buffer: []u8,
    ) void {
        self.submit(
            context,
            callback,
            completion,
            .recv,
            .{
                .socket = socket,
                .buf = buffer,
            },
            struct {
                fn do_operation(
                    _: Completion.Context,
                    op: anytype,
                ) RecvError!usize {
                    return posix.recv(op.socket, op.buf, 0);
                }
            },
        );
    }

    pub const SendError = posix.SendError || error{Canceled};

    pub fn send(
        self: *IO,
        comptime Context: type,
        context: Context,
        comptime callback: fn (
            context: Context,
            completion: *Completion,
            result: SendError!usize,
        ) void,
        completion: *Completion,
        socket: socket_t,
        buffer: []const u8,
    ) void {
        self.submit(
            context,
            callback,
            completion,
            .send,
            .{
                .socket = socket,
                .buf = buffer,
            },
            struct {
                fn do_operation(
                    _: Completion.Context,
                    op: anytype,
                ) SendError!usize {
                    return posix.send(op.socket, op.buf, 0);
                }
            },
        );
    }

    pub const ConnectError = posix.ConnectError || error{Canceled};

    /// Outbound TCP connect (S4-a). Pass 1 starts the non-blocking connect;
    /// EINPROGRESS (error.WouldBlock) parks the completion on EVFILT.WRITE,
    /// which fires when the connect finishes — success or failure. Pass 2
    /// harvests SO_ERROR via getsockoptError. The caller owns the socket: on
    /// failure it stays open for the caller to close.
    pub fn connect(
        self: *IO,
        comptime Context: type,
        context: Context,
        comptime callback: fn (
            context: Context,
            completion: *Completion,
            result: ConnectError!void,
        ) void,
        completion: *Completion,
        socket: socket_t,
        address: std.net.Address,
    ) void {
        self.submit(
            context,
            callback,
            completion,
            .connect,
            .{
                .socket = socket,
                .address = address,
                .pending = false,
            },
            struct {
                fn do_operation(
                    _: Completion.Context,
                    op: anytype,
                ) ConnectError!void {
                    if (!op.pending) {
                        posix.connect(
                            op.socket,
                            &op.address.any,
                            op.address.getOsSockLen(),
                        ) catch |err| switch (err) {
                            error.WouldBlock => {
                                op.pending = true;
                                return error.WouldBlock;
                            },
                            else => return err,
                        };

                        return; // completed synchronously (e.g. loopback)
                    }

                    return posix.getsockoptError(op.socket);
                }
            },
        );
    }

    pub const TimeoutError = error{Canceled} || posix.UnexpectedError;

    pub fn timeout(
        self: *IO,
        comptime Context: type,
        context: Context,
        comptime callback: fn (
            context: Context,
            completion: *Completion,
            result: TimeoutError!void,
        ) void,
        completion: *Completion,
        nanoseconds: u63,
    ) void {
        assert(nanoseconds > 0);

        self.submit(
            context,
            callback,
            completion,
            .timeout,
            .{
                .deadline = self.time.monotonic() + nanoseconds,
            },
            struct {
                fn do_operation(
                    _: Completion.Context,
                    _: anytype,
                ) TimeoutError!void {
                    return; // Timeouts don't have errors for now.
                }
            },
        );
    }

    /// Aborts an in-flight operation: unlinks it from the queues and removes
    /// any kernel registration, then completes `error.Canceled` on the next
    /// drain so the caller's slot bookkeeping settles. A completion still
    /// queued for registration or already registered is both completed now —
    /// never left waiting on a readiness event that may not arrive. The user
    /// callback runs exactly once.
    pub fn cancel(self: *IO, completion: *Completion) void {
        // Timeouts have no kernel state and their callbacks never expect
        // error.Canceled (they `catch unreachable`), so unlinking is all
        // cancel does — exactly like the epoll backend. The deadline race
        // only cancels a timeout because the operation itself won first.
        if (std.meta.activeTag(completion.operation) == .timeout) {
            if (self.timeouts.contains(completion)) {
                self.timeouts.remove(completion);
            }
            return;
        }

        const was_queued =
            self.timeouts.contains(completion) or
            self.completed.contains(completion) or
            self.io_pending.contains(completion);

        if (self.timeouts.contains(completion)) {
            self.timeouts.remove(completion);
        }

        if (self.completed.contains(completion)) {
            self.completed.remove(completion);
        }

        if (self.io_pending.contains(completion)) {
            self.io_pending.remove(completion);
        }

        if (completion.registered) {
            // The EV.ONESHOT event only delivers when the fd becomes ready —
            // which may be never (no client connects, no data arrives).
            // Remove the registration so it cannot fire later, and complete
            // Canceled on the next drain.
            self.unregister(completion);
            self.io_inflight -= 1;
            completion.registered = false;
        } else if (!was_queued) {
            // Never submitted (or already resolved): leave it alone. The
            // adapter defensively cancels init-state completions — no
            // callback may fire for a completion that was never queued.
            return;
        }

        completion.cancelled = true;
        self.completed.push(completion);
    }

    /// Removes a registered EV.ONESHOT filter from the kernel. ENOENT means
    /// the event already fired and was consumed — nothing to do, and no
    /// callback will fire because ONESHOT delivers at most once.
    fn unregister(self: *IO, completion: *Completion) void {
        const filter: i16 = switch (completion.operation) {
            .accept => posix.system.EVFILT.READ,
            .recv => posix.system.EVFILT.READ,
            .send => posix.system.EVFILT.WRITE,
            .connect => posix.system.EVFILT.WRITE,
            else => unreachable,
        };

        const ident: usize = switch (completion.operation) {
            .accept => |op| @intCast(op.socket),
            .recv => |op| @intCast(op.socket),
            .send => |op| @intCast(op.socket),
            .connect => |op| @intCast(op.socket),
            else => unreachable,
        };

        var change = [_]posix.Kevent{.{
            .ident = ident,
            .filter = filter,
            .flags = posix.system.EV.DELETE,
            .fflags = 0,
            .data = 0,
            .udata = 0,
        }};

        var eventlist: [0]posix.Kevent = undefined;

        _ = posix.kevent(
            self.kq,
            &change,
            &eventlist,
            &std.mem.zeroes(posix.timespec),
        ) catch {};
    }

    pub const socket_t = posix.socket_t;
    pub const fd_t = posix.fd_t;

    /// Creates a non-blocking TCP socket.
    pub fn open_socket_tcp(
        self: *IO,
        family: u32,
        options: TCPOptions,
    ) !socket_t {
        _ = self;

        const fd = try posix.socket(
            family,
            posix.SOCK.STREAM | posix.SOCK.NONBLOCK,
            posix.IPPROTO.TCP,
        );

        errdefer posix.close(fd);

        // Darwin doesn't support SOCK_CLOEXEC.
        _ = try posix.fcntl(
            fd,
            posix.F.SETFD,
            posix.FD_CLOEXEC,
        );

        try common.tcp_options(fd, options);

        return fd;
    }

    /// Closes a socket opened by the IO instance.
    pub fn close_socket(self: *IO, socket: socket_t) void {
        _ = self;
        posix.close(socket);
    }

    /// Listen on the given TCP socket.
    /// Returns the socket's resolved address (e.g. actual port for port 0).
    pub fn listen(
        _: *IO,
        fd: socket_t,
        address: std.net.Address,
        options: ListenOptions,
    ) !std.net.Address {
        return common.listen(fd, address, options);
    }

    pub fn shutdown(
        _: *IO,
        socket: socket_t,
        how: posix.ShutdownHow,
    ) posix.ShutdownError!void {
        return posix.shutdown(socket, how);
    }
};
