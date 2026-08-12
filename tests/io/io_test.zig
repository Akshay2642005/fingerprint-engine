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
