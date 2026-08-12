//! Completion-based io for Linux — epoll backend (worker-resilience.md S1).
//!
//! Modeled on TigerBeetle's `src/io/linux.zig`, but epoll (level-triggered)
//! rather than io_uring: io_uring is the documented design vision for when
//! the ingress needs concurrent per-worker requests; the completion contract
//! (`Completion`/`submit`/`flush`) is identical, so swapping backends is a
//! drop-in change.
//!
//! How readiness works here (vs overlapped IO on Windows):
//! - `submit()` pushes the completion onto `completed`; the first
//!   `do_operation` pass registers the fd with `EPOLL_CTL_ADD`
//!   (level-triggered, completion pointer in `data.ptr`), flips
//!   `op.pending`, bumps `io_pending`, and returns `error.WouldBlock`.
//! - `flush()`'s `epoll_wait` returns ready fds; each event pushes its
//!   completion back onto `completed`; the second `do_operation` pass
//!   performs the syscall. A spurious wake returns `WouldBlock` and the
//!   level-triggered registration simply re-fires. On finish (success or
//!   error) the fd is unregistered and `io_pending` is decremented.
//! - `io_pending` therefore counts registered fds; it exists so a blocking
//!   flush with no deadline cannot wait forever on nothing.
const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const assert = std.debug.assert;

const common = @import("./common.zig");
const QueueType = @import("./queue.zig").QueueType;

const linux = std.os.linux;

const Interest = enum { in, out };

pub const IO = struct {
    pub const TCPOptions = common.TCPOptions;
    pub const ListenOptions = common.ListenOptions;

    pub const FlushMode = enum {
        blocking,
        non_blocking,
    };

    epoll_fd: i32,
    time: common.TimeOS,
    /// Number of fds currently registered for readiness.
    io_pending: usize = 0,
    timeouts: QueueType(Completion) = .init(),
    completed: QueueType(Completion) = .init(),
    run_for_ns_active: bool = false,

    pub fn init(entries: u12, flags: u32) !IO {
        _ = entries; // capacity hint; the events buffer is fixed below
        _ = flags;
        const epoll_fd = try posix.epoll_create1(linux.EPOLL.CLOEXEC);
        errdefer posix.close(epoll_fd);
        return IO{ .epoll_fd = epoll_fd, .time = common.TimeOS.init() };
    }

    pub fn deinit(self: *IO) void {
        posix.close(self.epoll_fd);
        self.epoll_fd = -1;
    }

    /// Monotonic nanoseconds since this IO instance was created.
    pub fn now(self: *const IO) u64 {
        return self.time.monotonic();
    }

    /// Non-blocking flush: poll once, drain everything ready.
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
        self.timeout(*TimedOut, &state, TimedOut.on_timeout, &completion, nanoseconds);

        while (!state.timed_out) {
            try self.flush(.blocking);
        }
    }

    /// One event-loop pass: expire timeouts, wait (or poll) for readiness,
    /// then drain every ready completion. Callbacks may submit new
    /// completions, which are picked up in the same drain.
    pub fn flush(self: *IO, mode: FlushMode) !void {
        var timeout_ms: ?i32 = null;
        if (self.flush_timeouts()) |expires_ns| {
            // 0ns expires should have been completed, not returned.
            assert(expires_ns != 0);
            const expires_ms = (expires_ns + (std.time.ns_per_ms / 2)) / std.time.ns_per_ms;
            timeout_ms = @intCast(@min(expires_ms, std.math.maxInt(i32) - 1));
        }

        const wait_ms: i32 = switch (mode) {
            .blocking => timeout_ms orelse blk: {
                // Blocking with nothing to wait on would hang forever.
                assert(self.io_pending > 0);
                break :blk -1; // wait indefinitely
            },
            .non_blocking => 0,
        };

        var events: [64]linux.epoll_event = undefined;
        const num_events = posix.epoll_wait(self.epoll_fd, &events, wait_ms);
        for (events[0..num_events]) |event| {
            const completion: *Completion = @ptrFromInt(event.data.ptr);
            // The fd is still registered until do_operation harvests it.
            assert(completion.link.next == null);
            self.completed.push(completion);
        }

        // After sleeping for the timeout, re-check so all timeouts expiring
        // at the same instant are collected in the same batch.
        _ = self.flush_timeouts();

        while (self.completed.pop()) |completion| {
            (completion.callback)(Completion.Context{
                .io = self,
                .completion = completion,
            });
        }
    }

    /// Moves expired timeouts onto `completed`; returns the min remaining
    /// nanoseconds until the next expiry (null when no timeouts are queued).
    fn flush_timeouts(self: *IO) ?u64 {
        var min_expires: ?u64 = null;
        var current_time: ?u64 = null;

        var iterator = self.timeouts.iterate();
        while (iterator.next()) |completion| {
            // Lazily sample the clock once per pass.
            const current = current_time orelse self.time.monotonic();
            current_time = current;

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

        /// Benign initial state for completions that may be cancelled before
        /// their first submission (the adapter's defensive cancels). The
        /// callback is never invoked for a never-submitted completion.
        pub fn init() Completion {
            return .{
                .context = null,
                .callback = undefined,
                .operation = .{ .timeout = .{ .deadline = 0 } },
            };
        }

        pub const Context = struct {
            io: *IO,
            completion: *Completion,
        };

        const Operation = union(enum) {
            accept: struct {
                listen_socket: socket_t,
                pending: bool = false,
            },
            recv: struct {
                socket: socket_t,
                buf: []u8,
                pending: bool = false,
            },
            send: struct {
                socket: socket_t,
                buf: []const u8,
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

                // Perform the operation and get the result.
                const data = &@field(ctx.completion.operation, @tagName(op_tag));
                const result = OperationImpl.do_operation(ctx, data);

                // The first pass registers the fd and returns WouldBlock; the
                // completion is parked with the kernel. Subsequent passes
                // (after epoll_wait) do the real syscall — a spurious wake
                // returns WouldBlock and the level-triggered registration
                // re-fires. do_operation owns the io_pending accounting
                // (register on start, unregister on finish), so nothing to do
                // here on WouldBlock.
                switch (op_tag) {
                    .accept, .recv, .send => {
                        _ = result catch |err| switch (err) {
                            error.WouldBlock => return,
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

        // Setup the completion with the callback wrapper above.
        completion.* = .{
            .link = .{},
            .context = @ptrCast(context),
            .callback = Callback.onComplete,
            .operation = @unionInit(Completion.Operation, @tagName(op_tag), op_data),
        };

        // Submit the completion onto the right queue.
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
            .{ .listen_socket = socket, .pending = false },
            struct {
                fn do_operation(ctx: Completion.Context, op: anytype) AcceptError!socket_t {
                    if (!op.pending) {
                        // First pass: register the listen socket for
                        // readability; epoll delivers the event.
                        try ctx.io.register(op.listen_socket, .in, ctx.completion);
                        op.pending = true;
                        return error.WouldBlock;
                    }
                    // Ready: accept. SOCK.NONBLOCK|SOCK.CLOEXEC via accept4.
                    const fd = try posix.accept(
                        op.listen_socket,
                        null,
                        null,
                        posix.SOCK.NONBLOCK | posix.SOCK.CLOEXEC,
                    );
                    ctx.io.unregister(op.listen_socket, ctx.completion);
                    ctx.io.io_pending -= 1;
                    op.pending = false;
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
            .{ .socket = socket, .buf = buffer, .pending = false },
            struct {
                fn do_operation(ctx: Completion.Context, op: anytype) RecvError!usize {
                    if (!op.pending) {
                        try ctx.io.register(op.socket, .in, ctx.completion);
                        op.pending = true;
                        return error.WouldBlock;
                    }
                    const n = posix.recv(op.socket, op.buf, 0) catch |err| switch (err) {
                        // Spurious wake (level-triggered epoll re-fires).
                        error.WouldBlock => return error.WouldBlock,
                        else => |e| {
                            ctx.io.unregister(op.socket, ctx.completion);
                            ctx.io.io_pending -= 1;
                            op.pending = false;
                            return e;
                        },
                    };
                    ctx.io.unregister(op.socket, ctx.completion);
                    ctx.io.io_pending -= 1;
                    op.pending = false;
                    return n;
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
            .{ .socket = socket, .buf = buffer, .pending = false },
            struct {
                fn do_operation(ctx: Completion.Context, op: anytype) SendError!usize {
                    if (!op.pending) {
                        try ctx.io.register(op.socket, .out, ctx.completion);
                        op.pending = true;
                        return error.WouldBlock;
                    }
                    const n = posix.send(op.socket, op.buf, 0) catch |err| switch (err) {
                        // Send buffer full; level-triggered EPOLLOUT re-fires
                        // once there is room.
                        error.WouldBlock => return error.WouldBlock,
                        else => |e| {
                            ctx.io.unregister(op.socket, ctx.completion);
                            ctx.io.io_pending -= 1;
                            op.pending = false;
                            return e;
                        },
                    };
                    ctx.io.unregister(op.socket, ctx.completion);
                    ctx.io.io_pending -= 1;
                    op.pending = false;
                    return n;
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
        // Use `next_tick()` if you're looking for a yield.
        assert(nanoseconds > 0);

        self.submit(
            context,
            callback,
            completion,
            .timeout,
            .{ .deadline = self.time.monotonic() + nanoseconds },
            struct {
                fn do_operation(_: Completion.Context, _: anytype) TimeoutError!void {
                    return; // Timeouts don't have errors for now.
                }
            },
        );
    }

    /// Aborts an in-flight operation: unlinks it from the queues and
    /// unregisters its fd, then delivers a synthetic `error.Canceled` so the
    /// completion completes exactly once (the caller's slot bookkeeping
    /// settles). Cancelling a timeout just unlinks it — no kernel state, no
    /// callback.
    pub fn cancel(self: *IO, completion: *Completion) void {
        if (self.timeouts.contains(completion)) self.timeouts.remove(completion);
        if (self.completed.contains(completion)) self.completed.remove(completion);

        switch (completion.operation) {
            .accept => |*op| if (op.pending) {
                self.unregister(op.listen_socket, completion);
                self.io_pending -= 1;
                op.pending = false;
            },
            .recv => |*op| if (op.pending) {
                self.unregister(op.socket, completion);
                self.io_pending -= 1;
                op.pending = false;
            },
            .send => |*op| if (op.pending) {
                self.unregister(op.socket, completion);
                self.io_pending -= 1;
                op.pending = false;
            },
            .timeout => return,
        }

        // Deliver the synthetic Canceled on the next drain (callbacks may
        // already be running; pushing onto completed picks it up in the same
        // pass).
        completion.cancelled = true;
        self.completed.push(completion);
    }

    fn register(self: *IO, fd: i32, interest: Interest, completion: *Completion) error{SystemResources}!void {
        const event = linux.epoll_event{
            .events = switch (interest) {
                .in => linux.EPOLL.IN,
                .out => linux.EPOLL.OUT,
            },
            .data = .{ .ptr = @intFromPtr(completion) },
        };
        // The epoll-specific error space cannot flow through the op error
        // sets (AcceptError/RecvError/SendError), and every real failure is
        // a programming error or resource exhaustion — map to the one error
        // every set shares.
        posix.epoll_ctl(self.epoll_fd, linux.EPOLL.CTL_ADD, fd, @constCast(&event)) catch |err| switch (err) {
            error.FileDescriptorAlreadyPresentInSet => unreachable, // one registration per op
            error.OperationCausesCircularLoop => unreachable,
            error.FileDescriptorNotRegistered => unreachable, // ADD, not MOD/DEL
            error.FileDescriptorIncompatibleWithEpoll => unreachable, // sockets are supported
            error.UserResourceLimitReached => return error.SystemResources,
            error.SystemResources => return error.SystemResources,
            else => return error.SystemResources,
        };
    }

    fn unregister(self: *IO, fd: i32, completion: *Completion) void {
        _ = completion;
        // ENOENT means the fd was already closed (auto-removed by the kernel)
        // — nothing to do.
        posix.epoll_ctl(self.epoll_fd, linux.EPOLL.CTL_DEL, fd, null) catch |err| switch (err) {
            error.FileDescriptorNotRegistered => {},
            else => unreachable,
        };
    }

    pub const socket_t = posix.socket_t;
    pub const fd_t = posix.fd_t;

    /// Creates a non-blocking TCP socket (SOCK.NONBLOCK|SOCK.CLOEXEC are
    /// passed straight into the syscall on Linux).
    pub fn open_socket_tcp(
        self: *IO,
        family: u32,
        options: TCPOptions,
    ) !socket_t {
        _ = self;
        const socket = try posix.socket(
            family,
            posix.SOCK.STREAM | posix.SOCK.NONBLOCK | posix.SOCK.CLOEXEC,
            posix.IPPROTO.TCP,
        );
        errdefer posix.close(socket);

        try common.tcp_options(socket, options);
        return socket;
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

    pub fn shutdown(_: *IO, socket: socket_t, how: posix.ShutdownHow) posix.ShutdownError!void {
        return posix.shutdown(socket, how);
    }
};
