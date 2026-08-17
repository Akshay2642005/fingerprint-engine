const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const io = @import("io");

const IO = io.IO;
const posix = std.posix;

const tcp_options = IO.TCPOptions{
    .rcvbuf = 0,
    .sndbuf = 0,
    .keepalive = null,
    .user_timeout_ms = 0,
    .nodelay = true,
};

test "io: run returns immediately when idle" {
    var ioo = try IO.init(64, 0);
    defer ioo.deinit();

    // Non-blocking flush with nothing pending must not hang or fail.
    try ioo.run();
}

const TimeoutCtx = struct {
    io: *IO,
    fired: bool = false,
    fired_at: u64 = 0,

    fn on_timeout(
        ctx: *TimeoutCtx,
        completion: *IO.Completion,
        result: IO.TimeoutError!void,
    ) void {
        _ = completion;
        _ = result catch unreachable;
        ctx.fired = true;
        ctx.fired_at = ctx.io.now();
    }
};

test "io: timeout fires after its deadline" {
    var ioo = try IO.init(64, 0);
    defer ioo.deinit();

    var ctx = TimeoutCtx{ .io = &ioo };
    var completion: IO.Completion = undefined;
    ioo.timeout(*TimeoutCtx, &ctx, TimeoutCtx.on_timeout, &completion, 10 * std.time.ns_per_ms);

    const start = ioo.now();
    // run_for_ns submits its own watchdog; our 10ms timeout must fire first.
    try ioo.run_for_ns(100 * std.time.ns_per_ms);
    try testing.expect(ctx.fired);
    try testing.expect(ctx.fired_at - start >= 10 * std.time.ns_per_ms);
}

test "io: timeouts complete in deadline order" {
    var ioo = try IO.init(64, 0);
    defer ioo.deinit();

    var later = TimeoutCtx{ .io = &ioo };
    var sooner = TimeoutCtx{ .io = &ioo };
    var later_completion: IO.Completion = undefined;
    var sooner_completion: IO.Completion = undefined;
    ioo.timeout(*TimeoutCtx, &later, TimeoutCtx.on_timeout, &later_completion, 30 * std.time.ns_per_ms);
    ioo.timeout(*TimeoutCtx, &sooner, TimeoutCtx.on_timeout, &sooner_completion, 10 * std.time.ns_per_ms);

    try ioo.run_for_ns(100 * std.time.ns_per_ms);
    try testing.expect(sooner.fired);
    try testing.expect(later.fired);
    try testing.expect(sooner.fired_at <= later.fired_at);
}

test "io: cancel prevents a queued timeout from firing" {
    var ioo = try IO.init(64, 0);
    defer ioo.deinit();

    var ctx = TimeoutCtx{ .io = &ioo };
    var completion: IO.Completion = undefined;
    ioo.timeout(*TimeoutCtx, &ctx, TimeoutCtx.on_timeout, &completion, 10 * std.time.ns_per_ms);
    ioo.cancel(&completion);

    try ioo.run_for_ns(50 * std.time.ns_per_ms);
    try testing.expect(!ctx.fired);
}

const AcceptCtx = struct {
    done: bool = false,
    client: ?IO.socket_t = null,
    err: ?anyerror = null,

    fn on_accept(
        ctx: *AcceptCtx,
        completion: *IO.Completion,
        result: IO.AcceptError!IO.socket_t,
    ) void {
        _ = completion;
        if (ctx.done) return; // stale
        ctx.client = result catch |err| {
            ctx.err = err;
            ctx.done = true;
            return;
        };
        ctx.done = true;
    }
};

fn connectToPort(port: u16) void {
    var client = std.net.tcpConnectToHost(testing.allocator, "127.0.0.1", port) catch return;
    client.close();
}

test "io: accept completes when a client connects" {
    var ioo = try IO.init(64, 0);
    defer ioo.deinit();

    const listen_socket = try ioo.open_socket_tcp(posix.AF.INET, tcp_options);
    defer ioo.close_socket(listen_socket);
    const address = try ioo.listen(
        listen_socket,
        try std.net.Address.parseIp("127.0.0.1", 0),
        .{ .backlog = 16 },
    );

    var ctx = AcceptCtx{};
    var completion: IO.Completion = undefined;
    ioo.accept(*AcceptCtx, &ctx, AcceptCtx.on_accept, &completion, listen_socket);

    const thread = try std.Thread.spawn(.{}, connectToPort, .{address.getPort()});
    defer thread.join();

    while (!ctx.done) try ioo.flush(.blocking);
    try testing.expect(ctx.err == null);
    try testing.expect(ctx.client != null);
    if (ctx.client) |client| ioo.close_socket(client);
}

const AcceptTimeoutCtx = struct {
    io: *IO,
    accept_completion: IO.Completion = undefined,
    timeout_completion: IO.Completion = undefined,
    accepted: bool = false,
    timed_out: bool = false,

    fn on_accept(
        ctx: *AcceptTimeoutCtx,
        completion: *IO.Completion,
        result: IO.AcceptError!IO.socket_t,
    ) void {
        _ = completion;
        _ = result catch return;
        ctx.accepted = true;
    }

    fn on_timeout(
        ctx: *AcceptTimeoutCtx,
        completion: *IO.Completion,
        result: IO.TimeoutError!void,
    ) void {
        _ = completion;
        _ = result catch unreachable;
        ctx.timed_out = true;
        // Stop the pending accept; the race is over.
        ctx.io.cancel(&ctx.accept_completion);
    }
};

test "io: accept loses to the deadline when no client connects" {
    var ioo = try IO.init(64, 0);
    defer ioo.deinit();

    const listen_socket = try ioo.open_socket_tcp(posix.AF.INET, tcp_options);
    defer ioo.close_socket(listen_socket);
    _ = try ioo.listen(
        listen_socket,
        try std.net.Address.parseIp("127.0.0.1", 0),
        .{ .backlog = 16 },
    );

    var ctx = AcceptTimeoutCtx{ .io = &ioo };
    ioo.accept(
        *AcceptTimeoutCtx,
        &ctx,
        AcceptTimeoutCtx.on_accept,
        &ctx.accept_completion,
        listen_socket,
    );
    ioo.timeout(
        *AcceptTimeoutCtx,
        &ctx,
        AcceptTimeoutCtx.on_timeout,
        &ctx.timeout_completion,
        50 * std.time.ns_per_ms,
    );

    while (!ctx.timed_out and !ctx.accepted) try ioo.flush(.blocking);
    try testing.expect(ctx.timed_out);
    try testing.expect(!ctx.accepted);
}

const AcceptCancelCtx = struct {
    io: *IO,
    accept_completion: IO.Completion = undefined,
    timeout_completion: IO.Completion = undefined,
    accepted: bool = false,
    timed_out: bool = false,

    fn on_accept(
        ctx: *AcceptCancelCtx,
        completion: *IO.Completion,
        result: IO.AcceptError!IO.socket_t,
    ) void {
        _ = completion;
        _ = result catch return;
        ctx.accepted = true;
        // Mirror the adapter: cancel the queued poll-deadline right after
        // the accept wins (this is where the worker crashed).
        ctx.io.cancel(&ctx.timeout_completion);
    }

    fn on_timeout(
        ctx: *AcceptCancelCtx,
        completion: *IO.Completion,
        result: IO.TimeoutError!void,
    ) void {
        _ = completion;
        _ = result catch unreachable;
        ctx.timed_out = true;
        // Stop the pending accept; the race is over.
        ctx.io.cancel(&ctx.accept_completion);
    }
};

test "io: accept wins then cancels its poll deadline" {
    var ioo = try IO.init(64, 0);
    defer ioo.deinit();

    const listen_socket = try ioo.open_socket_tcp(posix.AF.INET, tcp_options);
    defer ioo.close_socket(listen_socket);
    const address = try ioo.listen(
        listen_socket,
        try std.net.Address.parseIp("127.0.0.1", 0),
        .{ .backlog = 16 },
    );

    var ctx = AcceptCancelCtx{ .io = &ioo };
    ioo.accept(
        *AcceptCancelCtx,
        &ctx,
        AcceptCancelCtx.on_accept,
        &ctx.accept_completion,
        listen_socket,
    );
    ioo.timeout(
        *AcceptCancelCtx,
        &ctx,
        AcceptCancelCtx.on_timeout,
        &ctx.timeout_completion,
        2 * std.time.ns_per_s,
    );

    const thread = try std.Thread.spawn(.{}, connectToPort, .{address.getPort()});
    defer thread.join();

    while (!ctx.accepted and !ctx.timed_out) try ioo.flush(.blocking);
    try testing.expect(ctx.accepted);
    try testing.expect(!ctx.timed_out);
    if (ctx.accepted) {
        // Reconnect path: a second accept after the first succeeded must
        // still work (the cancelled deadline must not wedge the queue).
        var again = AcceptCancelCtx{ .io = &ioo };
        ioo.accept(
            *AcceptCancelCtx,
            &again,
            AcceptCancelCtx.on_accept,
            &again.accept_completion,
            listen_socket,
        );
        ioo.timeout(
            *AcceptCancelCtx,
            &again,
            AcceptCancelCtx.on_timeout,
            &again.timeout_completion,
            2 * std.time.ns_per_s,
        );
        const thread2 = try std.Thread.spawn(.{}, connectToPort, .{address.getPort()});
        defer thread2.join();
        while (!again.accepted and !again.timed_out) try ioo.flush(.blocking);
        try testing.expect(again.accepted);
    }
}

test "io: platform supports an event loop" {
    // The compile-time dispatch itself is the assertion here: every
    // supported platform (linux/windows/darwin) must expose the contract the
    // adapter relies on.
    _ = IO;
    try testing.expect(builtin.target.os.tag == .linux or
        builtin.target.os.tag == .windows or
        builtin.target.os.tag == .macos or
        builtin.target.os.tag == .ios or
        builtin.target.os.tag == .tvos or
        builtin.target.os.tag == .watchos);
}

// ── connect (S4-a) ────────────────────────────────────────────────────

const ConnectCtx = struct {
    done: bool = false,
    connected: bool = false,
    err: ?anyerror = null,

    fn on_connect(
        ctx: *ConnectCtx,
        completion: *IO.Completion,
        result: IO.ConnectError!void,
    ) void {
        _ = completion;
        if (ctx.done) return; // stale
        result catch |err| {
            ctx.err = err;
            ctx.done = true;
            return;
        };
        ctx.connected = true;
        ctx.done = true;
    }
};

/// Accepts one connection on `server` and holds it open briefly so the
/// connecting side observes a live peer.
fn acceptAndHold(server: *std.net.Server, accepted: *std.atomic.Value(bool)) void {
    const conn = server.accept() catch return;
    defer conn.stream.close();
    accepted.store(true, .release);
    std.time.sleep(200 * std.time.ns_per_ms);
}

test "io: connect completes when a listener accepts" {
    var ioo = try IO.init(64, 0);
    defer ioo.deinit();

    var server = try std.net.Address.listen(
        try std.net.Address.parseIp("127.0.0.1", 0),
        .{ .reuse_address = true },
    );
    defer server.deinit();

    var accepted = std.atomic.Value(bool).init(false);
    const thread = try std.Thread.spawn(.{}, acceptAndHold, .{ &server, &accepted });
    defer thread.join();

    const socket = try ioo.open_socket_tcp(posix.AF.INET, tcp_options);
    defer ioo.close_socket(socket);

    var ctx = ConnectCtx{};
    var completion: IO.Completion = undefined;
    ioo.connect(
        *ConnectCtx,
        &ctx,
        ConnectCtx.on_connect,
        &completion,
        socket,
        server.listen_address,
    );

    while (!ctx.done) try ioo.flush(.blocking);
    try testing.expect(ctx.err == null);
    try testing.expect(ctx.connected);
    // The connect completed at the kernel level as soon as the listener's
    // backlog accepted the handshake; give the accept() thread time to run
    // so the connection is genuinely held when the test ends.
    const deadline = std.time.milliTimestamp() + 2000;
    while (!accepted.load(.acquire) and std.time.milliTimestamp() < deadline) {
        std.time.sleep(10 * std.time.ns_per_ms);
    }
    try testing.expect(accepted.load(.acquire));
}

test "io: connect fails with ConnectionRefused when nothing listens" {
    var ioo = try IO.init(64, 0);
    defer ioo.deinit();

    // Bind an ephemeral port, release it, and connect to the now-empty
    // address: loopback refuses immediately on every platform.
    var server = try std.net.Address.listen(
        try std.net.Address.parseIp("127.0.0.1", 0),
        .{ .reuse_address = true },
    );
    const address = server.listen_address;
    server.deinit();

    const socket = try ioo.open_socket_tcp(posix.AF.INET, tcp_options);
    defer ioo.close_socket(socket);

    var ctx = ConnectCtx{};
    var completion: IO.Completion = undefined;
    ioo.connect(
        *ConnectCtx,
        &ctx,
        ConnectCtx.on_connect,
        &completion,
        socket,
        address,
    );

    while (!ctx.done) try ioo.flush(.blocking);
    const connect_err = ctx.err orelse return error.TestDidNotRefuse;
    try testing.expect(connect_err == error.ConnectionRefused);
    try testing.expect(!ctx.connected);
}

const ConnectTimeoutCtx = struct {
    io: *IO,
    connect_completion: IO.Completion = undefined,
    timeout_completion: IO.Completion = undefined,
    connected: bool = false,
    timed_out: bool = false,
    connect_error: ?anyerror = null,

    fn on_connect(
        ctx: *ConnectTimeoutCtx,
        completion: *IO.Completion,
        result: IO.ConnectError!void,
    ) void {
        _ = completion;
        if (ctx.timed_out) return; // stale: the deadline won first
        result catch |err| {
            // The environment resolved the connect before the deadline (no
            // default route to drop the SYN); surface it instead of hanging.
            ctx.connect_error = err;
            return;
        };
        ctx.connected = true;
    }

    fn on_timeout(
        ctx: *ConnectTimeoutCtx,
        completion: *IO.Completion,
        result: IO.TimeoutError!void,
    ) void {
        _ = completion;
        _ = result catch unreachable;
        ctx.timed_out = true;
        // Stop the pending connect; the race is over.
        ctx.io.cancel(&ctx.connect_completion);
    }
};

test "io: connect loses to the deadline when the peer never responds" {
    var ioo = try IO.init(64, 0);
    defer ioo.deinit();

    // 192.0.2.1 is TEST-NET-1 (RFC 5737): routers must not forward it, so a
    // SYN to it is silently dropped on any network with a default route and
    // the connect hangs until the deadline fires. (Environments without a
    // default route fail fast instead; loopback cannot be used because a
    // refused loopback connect errors immediately and never parks.)
    const address = std.net.Address.parseIp("192.0.2.1", 9) catch unreachable;

    const socket = try ioo.open_socket_tcp(posix.AF.INET, tcp_options);
    defer ioo.close_socket(socket);

    var ctx = ConnectTimeoutCtx{ .io = &ioo };
    ioo.connect(
        *ConnectTimeoutCtx,
        &ctx,
        ConnectTimeoutCtx.on_connect,
        &ctx.connect_completion,
        socket,
        address,
    );
    ioo.timeout(
        *ConnectTimeoutCtx,
        &ctx,
        ConnectTimeoutCtx.on_timeout,
        &ctx.timeout_completion,
        100 * std.time.ns_per_ms,
    );

    while (!ctx.timed_out and !ctx.connected and ctx.connect_error == null) {
        try ioo.flush(.blocking);
    }
    try testing.expect(ctx.connect_error == null);
    try testing.expect(ctx.timed_out);
    try testing.expect(!ctx.connected);
}

test "io: a cancelled connect completes with Canceled and never connects" {
    var ioo = try IO.init(64, 0);
    defer ioo.deinit();

    const socket = try ioo.open_socket_tcp(posix.AF.INET, tcp_options);
    defer ioo.close_socket(socket);

    var ctx = ConnectCtx{};
    var completion: IO.Completion = undefined;
    ioo.connect(
        *ConnectCtx,
        &ctx,
        ConnectCtx.on_connect,
        &completion,
        socket,
        try std.net.Address.parseIp("127.0.0.1", 1),
    );
    ioo.cancel(&completion);

    // The aborted delivery surfaces on the next drain — exactly once, with
    // error.Canceled, never a kernel result (the adapter's race relies on
    // this: the deadline winner cancels the loser, whose stale delivery is
    // ignored). Nothing is pending after the cancel, so a blocking flush
    // would assert on io_pending == 0; a non-blocking drain suffices.
    try ioo.flush(.non_blocking);
    try testing.expect(ctx.done);
    const connect_err = ctx.err orelse return error.TestDidNotCancel;
    try testing.expect(connect_err == error.Canceled);
    try testing.expect(!ctx.connected);
}
