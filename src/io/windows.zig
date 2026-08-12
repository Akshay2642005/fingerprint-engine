//! Completion-based io for Windows — IOCP backend (worker-resilience.md S1).
//!
//! Adapted from TigerBeetle's `src/io/windows.zig` and trimmed to our
//! flavor: accept/recv/send/timeout/cancel plus socket management. No
//! stats, no tracer, no file IO.
//!
//! Mechanics (as in TigerBeetle):
//! - `submit()` pushes the completion onto `completed`; the first
//!   `do_operation` pass starts the overlapped operation (AcceptEx, WSARecv,
//!   WSASend). On `error.WouldBlock` (WSA_IO_PENDING) the completion is
//!   parked with the kernel and `io_pending` is bumped.
//! - `flush()` calls `GetQueuedCompletionStatusEx`; every returned
//!   `OVERLAPPED_ENTRY` maps back to its completion via the embedded
//!   `Overlapped` and lands on `completed`. The second `do_operation` pass
//!   harvests the result with `WSAGetOverlappedResult`.
//! - `cancel()` fires `CancelIoEx` on an in-flight overlapped op; the
//!   aborted completion is delivered on a later flush and completes
//!   `error.Canceled`, which stale-generation checks ignore. `io_pending`
//!   balances on delivery, so cancel does not touch it.
const std = @import("std");
const os = std.os;
const posix = std.posix;
const assert = std.debug.assert;

const common = @import("./common.zig");
const QueueType = @import("./queue.zig").QueueType;

/// ConnectEx — the overlapped outbound connect used by the io layer (S4-a).
/// Loaded per socket via WSAIoctl(SIO_GET_EXTENSION_FUNCTION_POINTER,
/// WSAID_CONNECTEX); the pointer type is a plain function pointer.
const ConnectEx = *const fn (
    socket: posix.socket_t,
    name: *const posix.sockaddr,
    namelen: c_int,
    send_buffer: ?*anyopaque,
    send_data_length: os.windows.DWORD,
    bytes_sent: *os.windows.DWORD,
    overlapped: *os.windows.OVERLAPPED,
) callconv(.winapi) os.windows.BOOL;

pub const IO = struct {
    pub const TCPOptions = common.TCPOptions;
    pub const ListenOptions = common.ListenOptions;

    pub const FlushMode = enum {
        blocking,
        non_blocking,
    };

    iocp: os.windows.HANDLE,
    time: common.TimeOS,
    /// Number of operations currently in flight with the kernel.
    io_pending: usize = 0,
    timeouts: QueueType(Completion) = .init(),
    completed: QueueType(Completion) = .init(),
    run_for_ns_active: bool = false,

    pub fn init(entries: u12, flags: u32) !IO {
        _ = entries; // capacity hint; the events buffer is fixed below
        _ = flags;

        _ = try os.windows.WSAStartup(2, 2);
        errdefer os.windows.WSACleanup() catch unreachable;

        const iocp = try os.windows.CreateIoCompletionPort(
            os.windows.INVALID_HANDLE_VALUE,
            null,
            0,
            0,
        );
        return IO{ .iocp = iocp, .time = common.TimeOS.init() };
    }

    pub fn deinit(self: *IO) void {
        assert(self.iocp != os.windows.INVALID_HANDLE_VALUE);
        os.windows.CloseHandle(self.iocp);
        self.iocp = os.windows.INVALID_HANDLE_VALUE;

        os.windows.WSACleanup() catch unreachable;
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

    /// One event-loop pass: expire timeouts, wait (or poll) for IOCP
    /// completions, then drain every ready completion.
    pub fn flush(self: *IO, mode: FlushMode) !void {
        // Always check for expired timeouts, even if the completed queue
        // already has items — timeouts that expire during callback dispatch
        // are discovered on the next flush.
        var timeout_ms: ?os.windows.DWORD = null;
        if (self.flush_timeouts()) |expires_ns| {
            // 0ns expires should have been completed, not returned.
            assert(expires_ns != 0);
            // Round up sub-millisecond expire times to the next millisecond.
            const expires_ms = (expires_ns + (std.time.ns_per_ms / 2)) / std.time.ns_per_ms;
            // Saturating cast to DWORD milliseconds.
            const expires = std.math.cast(os.windows.DWORD, expires_ms) orelse
                std.math.maxInt(os.windows.DWORD);
            // Max DWORD is reserved for INFINITE so cap the cast at max - 1.
            timeout_ms = if (expires == os.windows.INFINITE) expires - 1 else expires;
        }

        // Wait for IOCP completions when there's IO pending or when we need
        // to block for timeout expiry. Without this, pure-timeout workloads
        // (io_pending == 0) would busy-loop and pick off timeouts one at a
        // time instead of batching all that expire at the same instant.
        if (self.completed.empty() and
            (self.io_pending > 0 or mode == .blocking))
        {
            const io_timeout: os.windows.DWORD = switch (mode) {
                .blocking => timeout_ms orelse blk: {
                    // Blocking with nothing to wait on would hang forever.
                    assert(self.io_pending > 0);
                    break :blk os.windows.INFINITE;
                },
                .non_blocking => 0,
            };

            var events: [64]os.windows.OVERLAPPED_ENTRY = undefined;
            const num_events: u32 = os.windows.GetQueuedCompletionStatusEx(
                self.iocp,
                &events,
                io_timeout,
                false, // Non-alertable wait.
            ) catch |err| switch (err) {
                error.Timeout => 0,
                error.Aborted => unreachable,
                else => |e| return e,
            };

            assert(self.io_pending >= num_events);
            self.io_pending -= num_events;

            for (events[0..num_events]) |event| {
                const raw_overlapped = event.lpOverlapped;
                const overlapped: *Completion.Overlapped = @fieldParentPtr(
                    "raw",
                    raw_overlapped,
                );
                const completion = overlapped.completion;
                completion.link = .{};
                self.completed.push(completion);
            }

            // After sleeping for the timeout, re-check timeouts so that
            // all timeouts expiring at the same instant are collected in
            // the same batch rather than trickling in one per flush.
            _ = self.flush_timeouts();
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

    /// Moves expired timeouts onto `completed`; returns the min remaining
    /// nanoseconds until the next expiry (null when no timeouts are queued).
    fn flush_timeouts(self: *IO) ?u64 {
        var min_expires: ?u64 = null;
        var current_time: ?u64 = null;

        var iterator = self.timeouts.iterate();
        while (iterator.next()) |completion| {
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
        /// Set by `cancel` for a queued-but-never-started op; the next drain
        /// short-circuits to `error.Canceled` instead of running
        /// `do_operation`, so a cancelled completion always completes exactly
        /// once (the Linux/Darwin contract). In-flight ops need no flag:
        /// `CancelIoEx` aborts them and the IOCP delivery surfaces
        /// `error.Canceled` through `do_operation`.
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

        const Overlapped = struct {
            raw: os.windows.OVERLAPPED,
            completion: *Completion,
        };

        const Transfer = struct {
            socket: socket_t,
            buf: os.windows.ws2_32.WSABUF,
            overlapped: Overlapped,
            pending: bool,
        };

        const Operation = union(enum) {
            accept: struct {
                overlapped: Overlapped,
                listen_socket: socket_t,
                client_socket: ?socket_t,
                addr_buffer: [(@sizeOf(std.net.Address) + 16) * 2]u8 align(4),
            },
            recv: Transfer,
            send: Transfer,
            connect: struct {
                socket: socket_t,
                address: std.net.Address,
                overlapped: Overlapped,
                /// Loaded lazily per socket (WSAIoctl, SIO_GET_EXTENSION_
                /// FUNCTION_POINTER) on the first pass; ConnectEx is not a
                /// regular ws2_32 export.
                connect_ex: ?ConnectEx = null,
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
                // A queued-but-never-started completion cancelled before its
                // first drain completes exactly once, with error.Canceled,
                // without touching the kernel (the Linux/Darwin contract).
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

                // For OVERLAPPED IO, error.WouldBlock assumes that it will
                // be completed by IOCP.
                switch (op_tag) {
                    .accept, .recv, .send, .connect => {
                        _ = result catch |err| switch (err) {
                            error.WouldBlock => {
                                ctx.io.io_pending += 1;
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

    pub const AcceptError = posix.AcceptError || posix.SetSockOptError || error{Canceled};

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
            .{
                .overlapped = undefined,
                .listen_socket = socket,
                .client_socket = null,
                .addr_buffer = undefined,
            },
            struct {
                fn do_operation(ctx: Completion.Context, op: anytype) AcceptError!socket_t {
                    var flags: os.windows.DWORD = undefined;
                    var transferred: os.windows.DWORD = undefined;

                    const rc = if (op.client_socket == null) blk: {
                        // When first called, the client_socket is invalid so
                        // we start the op. Create the socket that will be
                        // used for accept.
                        op.client_socket = ctx.io.open_socket(
                            posix.AF.INET,
                            posix.SOCK.STREAM,
                            posix.IPPROTO.TCP,
                        ) catch |err| switch (err) {
                            error.AddressFamilyNotSupported => unreachable,
                            error.ProtocolNotSupported => unreachable,
                            else => |e| return e,
                        };

                        var sync_bytes_read: os.windows.DWORD = undefined;
                        op.overlapped = .{
                            .raw = std.mem.zeroes(os.windows.OVERLAPPED),
                            .completion = ctx.completion,
                        };

                        // Start the asynchronous accept with the created socket.
                        break :blk os.windows.ws2_32.AcceptEx(
                            op.listen_socket,
                            op.client_socket.?,
                            &op.addr_buffer,
                            0,
                            @sizeOf(std.net.Address) + 16,
                            @sizeOf(std.net.Address) + 16,
                            &sync_bytes_read,
                            &op.overlapped.raw,
                        );
                    } else blk: {
                        // Called after accept was started, so get the result.
                        break :blk os.windows.ws2_32.WSAGetOverlappedResult(
                            op.listen_socket,
                            &op.overlapped.raw,
                            &transferred,
                            os.windows.FALSE, // Don't wait.
                            &flags,
                        );
                    };

                    // Return the socket if we succeed in accepting.
                    if (rc != os.windows.FALSE) {
                        // Enables getsockopt, setsockopt, getsockname,
                        // getpeername.
                        _ = os.windows.ws2_32.setsockopt(
                            op.client_socket.?,
                            os.windows.ws2_32.SOL.SOCKET,
                            os.windows.ws2_32.SO.UPDATE_ACCEPT_CONTEXT,
                            null,
                            0,
                        );

                        return op.client_socket.?;
                    }

                    // Destroy the client_socket we created if we get a
                    // non-WouldBlock error.
                    errdefer |err| switch (err) {
                        error.WouldBlock => {},
                        else => {
                            ctx.io.close_socket(op.client_socket.?);
                            op.client_socket = null;
                        },
                    };

                    return switch (os.windows.ws2_32.WSAGetLastError()) {
                        .WSA_IO_PENDING, .WSAEWOULDBLOCK, .WSA_IO_INCOMPLETE => error.WouldBlock,
                        .WSANOTINITIALISED => unreachable, // WSAStartup() was called.
                        .WSAENETDOWN => unreachable, // WinSock error.
                        .WSAENOTSOCK => error.FileDescriptorNotASocket,
                        .WSAEOPNOTSUPP => error.OperationNotSupported,
                        .WSA_INVALID_HANDLE => unreachable, // No hEvent in OVERLAPPED.
                        .WSAEFAULT, .WSA_INVALID_PARAMETER => unreachable, // Params should be ok.
                        .WSAECONNRESET => error.ConnectionAborted,
                        .WSAEMFILE => unreachable, // We create our own descriptor.
                        .WSAENOBUFS => error.SystemResources,
                        .WSAEINTR, .WSAEINPROGRESS => unreachable, // No blocking calls.
                        // Our own cancel() (CancelIoEx) or a socket teardown
                        // aborts the overlapped accept; complete Canceled so
                        // the user callback can ignore it (stale generation).
                        .WSA_OPERATION_ABORTED => error.Canceled,
                        else => |err| os.windows.unexpectedWSAError(err),
                    };
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
        const transfer = Completion.Transfer{
            .socket = socket,
            .buf = os.windows.ws2_32.WSABUF{
                .len = @intCast(common.buffer_limit(buffer.len)),
                .buf = buffer.ptr,
            },
            .overlapped = undefined,
            .pending = false,
        };

        self.submit(
            context,
            callback,
            completion,
            .recv,
            transfer,
            struct {
                fn do_operation(ctx: Completion.Context, op: anytype) RecvError!usize {
                    var flags: os.windows.DWORD = 0; // Used both as input and output.
                    var transferred: os.windows.DWORD = undefined;

                    const rc = blk: {
                        // Poll for the result if we've already started the
                        // recv op.
                        if (op.pending) {
                            break :blk os.windows.ws2_32.WSAGetOverlappedResult(
                                op.socket,
                                &op.overlapped.raw,
                                &transferred,
                                os.windows.FALSE, // Don't wait.
                                &flags,
                            );
                        }

                        op.pending = true;
                        op.overlapped = .{
                            .raw = std.mem.zeroes(os.windows.OVERLAPPED),
                            .completion = ctx.completion,
                        };

                        // Start the recv operation.
                        break :blk switch (os.windows.ws2_32.WSARecv(
                            op.socket,
                            @ptrCast(&op.buf),
                            1, // One buffer.
                            &transferred,
                            &flags,
                            &op.overlapped.raw,
                            null,
                        )) {
                            os.windows.ws2_32.SOCKET_ERROR => @as(
                                os.windows.BOOL,
                                os.windows.FALSE,
                            ),
                            0 => os.windows.TRUE,
                            else => unreachable,
                        };
                    };

                    // Return bytes received on success.
                    if (rc != os.windows.FALSE)
                        return transferred;

                    return switch (os.windows.ws2_32.WSAGetLastError()) {
                        .WSA_IO_PENDING, .WSAEWOULDBLOCK, .WSA_IO_INCOMPLETE => error.WouldBlock,
                        .WSANOTINITIALISED => unreachable, // WSAStartup() was called
                        .WSA_INVALID_HANDLE => unreachable, // No hEvent in OVERLAPPED.
                        .WSA_INVALID_PARAMETER => unreachable, // Parameters are fine.
                        .WSAECONNABORTED => error.ConnectionRefused,
                        .WSAECONNRESET => error.ConnectionResetByPeer,
                        .WSAEDISCON => unreachable, // We only stream sockets.
                        .WSAEFAULT => unreachable, // Invalid buffer.
                        .WSAEINTR => unreachable, // This is non blocking.
                        .WSAEINPROGRESS => unreachable, // This is non blocking.
                        .WSAEINVAL => unreachable, // Invalid socket type
                        .WSAEMSGSIZE => error.MessageTooBig,
                        .WSAENETDOWN => error.NetworkSubsystemFailed,
                        .WSAENETRESET => error.ConnectionResetByPeer,
                        .WSAENOTCONN => error.SocketNotConnected,
                        .WSAEOPNOTSUPP => unreachable, // No MSG_OOB or MSG_PARTIAL.
                        .WSAESHUTDOWN => error.SocketNotConnected,
                        .WSAETIMEDOUT => error.ConnectionRefused,
                        // Our own cancel() (CancelIoEx) or a socket teardown
                        // aborts the overlapped recv; complete Canceled so
                        // the user callback can ignore it (stale generation).
                        .WSA_OPERATION_ABORTED => error.Canceled,
                        else => |err| os.windows.unexpectedWSAError(err),
                    };
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
        const transfer = Completion.Transfer{
            .socket = socket,
            .buf = os.windows.ws2_32.WSABUF{
                .len = @intCast(common.buffer_limit(buffer.len)),
                .buf = @constCast(buffer.ptr),
            },
            .overlapped = undefined,
            .pending = false,
        };

        self.submit(
            context,
            callback,
            completion,
            .send,
            transfer,
            struct {
                fn do_operation(ctx: Completion.Context, op: anytype) SendError!usize {
                    var flags: os.windows.DWORD = undefined;
                    var transferred: os.windows.DWORD = undefined;

                    const rc = blk: {
                        // Poll for the result if we've already started the
                        // send op.
                        if (op.pending) {
                            break :blk os.windows.ws2_32.WSAGetOverlappedResult(
                                op.socket,
                                &op.overlapped.raw,
                                &transferred,
                                os.windows.FALSE, // Don't wait.
                                &flags,
                            );
                        }

                        op.pending = true;
                        op.overlapped = .{
                            .raw = std.mem.zeroes(os.windows.OVERLAPPED),
                            .completion = ctx.completion,
                        };

                        // Start the send operation.
                        break :blk switch (os.windows.ws2_32.WSASend(
                            op.socket,
                            @ptrCast(&op.buf),
                            1, // One buffer.
                            &transferred,
                            0, // No flags.
                            &op.overlapped.raw,
                            null,
                        )) {
                            os.windows.ws2_32.SOCKET_ERROR => @as(
                                os.windows.BOOL,
                                os.windows.FALSE,
                            ),
                            0 => os.windows.TRUE,
                            else => unreachable,
                        };
                    };

                    // Return bytes transferred on success.
                    if (rc != os.windows.FALSE)
                        return transferred;

                    return switch (os.windows.ws2_32.WSAGetLastError()) {
                        .WSA_IO_PENDING, .WSAEWOULDBLOCK, .WSA_IO_INCOMPLETE => error.WouldBlock,
                        .WSANOTINITIALISED => unreachable, // WSAStartup() was called
                        .WSA_INVALID_HANDLE => unreachable, // No hEvent in OVERLAPPED.
                        .WSA_INVALID_PARAMETER => unreachable, // Parameters are fine.
                        .WSAECONNABORTED => error.ConnectionResetByPeer,
                        .WSAECONNRESET => error.ConnectionResetByPeer,
                        .WSAEFAULT => unreachable, // Invalid buffer.
                        .WSAEINTR => unreachable, // This is non blocking.
                        .WSAEINPROGRESS => unreachable, // This is non blocking.
                        .WSAEINVAL => unreachable, // Invalid socket type.
                        .WSAEMSGSIZE => error.MessageTooBig,
                        .WSAENETDOWN => error.NetworkSubsystemFailed,
                        .WSAENETRESET => error.ConnectionResetByPeer,
                        .WSAENOBUFS => error.SystemResources,
                        .WSAENOTCONN => error.FileDescriptorNotASocket,
                        .WSAEOPNOTSUPP => unreachable, // No MSG_OOB or MSG_PARTIAL.
                        .WSAESHUTDOWN => error.BrokenPipe,
                        // Our own cancel() (CancelIoEx) or a socket teardown
                        // aborts the overlapped send; complete Canceled so
                        // the user callback can ignore it (stale generation).
                        .WSA_OPERATION_ABORTED => error.Canceled,
                        else => |err| os.windows.unexpectedWSAError(err),
                    };
                }
            },
        );
    }

    pub const ConnectError = posix.ConnectError || error{Canceled};

    /// Outbound TCP connect via ConnectEx (S4-a). ConnectEx is an overlapped
    /// operation like AcceptEx: pass 1 binds the socket (ConnectEx requires
    /// a bound socket), loads the per-socket ConnectEx pointer with WSAIoctl,
    /// and starts the overlapped connect; WSA_IO_PENDING parks the completion
    /// with IOCP. Pass 2 harvests the result with WSAGetOverlappedResult. The
    /// caller owns the socket: on failure it stays open for the caller to
    /// close.
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
                .overlapped = undefined,
                .connect_ex = null,
                .pending = false,
            },
            struct {
                fn do_operation(ctx: Completion.Context, op: anytype) ConnectError!void {
                    var flags: os.windows.DWORD = undefined;
                    var transferred: os.windows.DWORD = undefined;

                    const rc = blk: {
                        // Poll for the result if we've already started the
                        // connect op.
                        if (op.pending) {
                            break :blk os.windows.ws2_32.WSAGetOverlappedResult(
                                op.socket,
                                &op.overlapped.raw,
                                &transferred,
                                os.windows.FALSE, // Don't wait.
                                &flags,
                            );
                        }

                        // ConnectEx requires the socket to be bound first;
                        // bind to the wildcard address if not already bound.
                        var any_address = std.net.Address.parseIp("0.0.0.0", 0) catch unreachable;
                        if (os.windows.ws2_32.bind(
                            op.socket,
                            &any_address.any,
                            @intCast(any_address.getOsSockLen()),
                        ) == os.windows.ws2_32.SOCKET_ERROR) {
                            switch (os.windows.ws2_32.WSAGetLastError()) {
                                .WSAEINVAL => {}, // already bound
                                else => |err| return os.windows.unexpectedWSAError(err),
                            }
                        }

                        // ConnectEx is an extension function; load it per
                        // socket (cached for pass 2). A valid socket + known
                        // GUID cannot fail here; surface as Unexpected.
                        const connect_ex = op.connect_ex orelse load: {
                            const fn_ptr = os.windows.loadWinsockExtensionFunction(
                                ConnectEx,
                                op.socket,
                                os.windows.ws2_32.WSAID_CONNECTEX,
                            ) catch return error.Unexpected;
                            op.connect_ex = fn_ptr;
                            break :load fn_ptr;
                        };

                        op.pending = true;
                        op.overlapped = .{
                            .raw = std.mem.zeroes(os.windows.OVERLAPPED),
                            .completion = ctx.completion,
                        };

                        // Start the overlapped connect.
                        break :blk connect_ex(
                            op.socket,
                            @ptrCast(&op.address.any),
                            @intCast(op.address.getOsSockLen()),
                            null, // No send buffer.
                            0,
                            &transferred,
                            &op.overlapped.raw,
                        );
                    };

                    // Connected (or already connected on a synchronous
                    // loopback connect).
                    if (rc != os.windows.FALSE) return;

                    return switch (os.windows.ws2_32.WSAGetLastError()) {
                        .WSA_IO_PENDING, .WSAEWOULDBLOCK, .WSA_IO_INCOMPLETE => error.WouldBlock,
                        .WSANOTINITIALISED => unreachable, // WSAStartup() was called.
                        .WSAEADDRINUSE => error.AddressInUse,
                        .WSAEADDRNOTAVAIL => error.AddressNotAvailable,
                        .WSAECONNREFUSED => error.ConnectionRefused,
                        .WSAECONNRESET => error.ConnectionResetByPeer,
                        .WSAETIMEDOUT => error.ConnectionTimedOut,
                        .WSAEHOSTUNREACH, .WSAENETUNREACH => error.NetworkUnreachable,
                        .WSAEACCES => unreachable, // Socket flags are ours.
                        .WSAEFAULT => unreachable, // Address buffer is valid.
                        .WSAEINVAL => unreachable, // Bound socket, valid address.
                        .WSAEISCONN => unreachable, // Not yet connected.
                        .WSAENOTSOCK => unreachable, // Open socket from open_socket.
                        .WSAENOBUFS => error.SystemResources,
                        .WSAEAFNOSUPPORT => error.AddressFamilyNotSupported,
                        // Our own cancel() (CancelIoEx) or a socket teardown
                        // aborts the overlapped connect; complete Canceled so
                        // the user callback can ignore it (stale generation).
                        .WSA_OPERATION_ABORTED => error.Canceled,
                        else => |err| os.windows.unexpectedWSAError(err),
                    };
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

    /// Aborts an in-flight operation: unlinks it from the queues and, if the
    /// overlapped op is with the kernel, fires `CancelIoEx`. The aborted
    /// completion is delivered on a later flush and completes
    /// `error.Canceled` (stale-generation checks ignore it); `io_pending`
    /// balances on delivery, so it is not touched here. The user callback is
    /// never invoked for a cancelled operation.
    pub fn cancel(self: *IO, completion: *Completion) void {
        const was_queued = self.timeouts.contains(completion) or
            self.completed.contains(completion);
        if (self.timeouts.contains(completion)) self.timeouts.remove(completion);
        if (self.completed.contains(completion)) self.completed.remove(completion);

        var started = false;
        var handle: os.windows.HANDLE = undefined;
        var overlapped: *os.windows.OVERLAPPED = undefined;
        switch (completion.operation) {
            .accept => |*op| if (op.client_socket != null) {
                started = true;
                handle = @ptrCast(op.listen_socket);
                overlapped = &op.overlapped.raw;
            },
            .recv => |*op| if (op.pending) {
                started = true;
                handle = @ptrCast(op.socket);
                overlapped = &op.overlapped.raw;
            },
            .send => |*op| if (op.pending) {
                started = true;
                handle = @ptrCast(op.socket);
                overlapped = &op.overlapped.raw;
            },
            .connect => |*op| if (op.pending) {
                started = true;
                handle = @ptrCast(op.socket);
                overlapped = &op.overlapped.raw;
            },
            .timeout => {},
        }

        if (started) {
            // Abort the overlapped operation; the IOCP delivers the aborted
            // result, which do_operation surfaces as error.Canceled (and
            // io_pending balances on that delivery).
            _ = os.windows.kernel32.CancelIoEx(handle, overlapped);
        } else if (was_queued and
            std.meta.activeTag(completion.operation) != .timeout)
        {
            // Queued but never started (cancelled before the first flush):
            // deliver the synthetic error.Canceled on the next drain so a
            // cancelled completion always completes exactly once — the
            // Linux/Darwin contract. Timeouts complete silently: the adapter
            // cancels leftover deadlines and never expects a callback.
            completion.cancelled = true;
            self.completed.push(completion);
        }
    }

    pub const socket_t = posix.socket_t;
    pub const fd_t = posix.fd_t;

    /// Creates a TCP socket that can be used for async operations with the
    /// IO instance.
    pub fn open_socket_tcp(
        self: *IO,
        family: u32,
        options: TCPOptions,
    ) !socket_t {
        const socket = try self.open_socket(
            family,
            posix.SOCK.STREAM,
            posix.IPPROTO.TCP,
        );
        errdefer self.close_socket(socket);

        try common.tcp_options(socket, options);
        return socket;
    }

    fn open_socket(self: *IO, family: u32, sock_type: i32, protocol: i32) !socket_t {
        // Equivalent to SOCK_NONBLOCK | SOCK_CLOEXEC.
        const socket_flags: os.windows.DWORD =
            os.windows.ws2_32.WSA_FLAG_OVERLAPPED |
            os.windows.ws2_32.WSA_FLAG_NO_HANDLE_INHERIT;

        const socket = try os.windows.WSASocketW(
            @bitCast(family),
            sock_type,
            protocol,
            null,
            0,
            socket_flags,
        );
        errdefer self.close_socket(socket);

        try self.register_handle(@ptrCast(socket));
        return socket;
    }

    /// Register the IO handle for overlapped operations.
    fn register_handle(self: *IO, handle: os.windows.HANDLE) !void {
        const iocp_handle = try os.windows.CreateIoCompletionPort(handle, self.iocp, 0, 0);
        assert(iocp_handle == self.iocp);

        // Ensure that synchronous IO completion doesn't queue an unneeded
        // overlapped and that the event for the handle doesn't need setting.
        var mode: os.windows.BYTE = 0;
        mode |= os.windows.FILE_SKIP_COMPLETION_PORT_ON_SUCCESS;
        mode |= os.windows.FILE_SKIP_SET_EVENT_ON_HANDLE;
        try os.windows.SetFileCompletionNotificationModes(handle, mode);
    }

    /// Closes a socket opened by the IO instance.
    pub fn close_socket(self: *IO, socket: socket_t) void {
        _ = self;
        _ = os.windows.ws2_32.closesocket(socket);
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
