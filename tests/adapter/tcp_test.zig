const std = @import("std");
const testing = std.testing;
const io = @import("io");
const adapter = @import("adapter");
const Tcp = adapter.Tcp;

const ServerContext = struct {
    tcp: *Tcp,
    failed: bool = false,
};

fn serveEcho(ctx: *ServerContext) void {
    ctx.tcp.accept() catch {
        ctx.failed = true;
        return;
    };
    const frame = ctx.tcp.readFrame(testing.allocator) catch {
        ctx.failed = true;
        return;
    };
    defer testing.allocator.free(frame);
    ctx.tcp.writeFrame(frame) catch {
        ctx.failed = true;
    };
}

test "tcp transport round-trips a frame over a local socket" {
    var tcp = try Tcp.init(testing.allocator, "127.0.0.1", 0, 0);
    defer tcp.deinit();

    var ctx = ServerContext{ .tcp = &tcp };
    const thread = try std.Thread.spawn(.{}, serveEcho, .{&ctx});
    defer thread.join();

    var client = try std.net.tcpConnectToHost(testing.allocator, "127.0.0.1", tcp.port());
    defer client.close();

    var req_buf: [io.frame.header_size + 32]u8 = undefined;
    const req = try adapter.buildFrame(.signal_package, .binary, "ping", &req_buf);
    try client.writeAll(req);

    const resp = try adapter.readFrameFrom(client.reader(), testing.allocator);
    defer testing.allocator.free(resp);
    try testing.expectEqualStrings(req, resp);
    try testing.expect(!ctx.failed);
}

test "tcp transport round-trips a zero-payload frame" {
    var tcp = try Tcp.init(testing.allocator, "127.0.0.1", 0, 0);
    defer tcp.deinit();

    var ctx = ServerContext{ .tcp = &tcp };
    const thread = try std.Thread.spawn(.{}, serveEcho, .{&ctx});
    defer thread.join();

    var client = try std.net.tcpConnectToHost(testing.allocator, "127.0.0.1", tcp.port());
    defer client.close();

    var req_buf: [io.frame.header_size]u8 = undefined;
    const req = try adapter.buildFrame(.signal_package, .binary, "", &req_buf);
    try client.writeAll(req);

    const resp = try adapter.readFrameFrom(client.reader(), testing.allocator);
    defer testing.allocator.free(resp);
    try testing.expectEqualStrings(req, resp);
    try testing.expect(!ctx.failed);
}

test "tcp readFrame without a client reports not connected" {
    var tcp = try Tcp.init(testing.allocator, "127.0.0.1", 0, 0);
    defer tcp.deinit();
    try testing.expectError(error.NotConnected, tcp.readFrame(testing.allocator));
}

test "tcp acceptWait returns false when no client connects within the timeout" {
    var tcp = try Tcp.init(testing.allocator, "127.0.0.1", 0, 0);
    defer tcp.deinit();
    // No client connects; the wait must return false after ~100ms instead of
    // blocking forever (H-2 needs the accept loop to observe the shutdown
    // flag while idle).
    try testing.expect(!try tcp.acceptWait(100));
}

/// Connects to `port` after a short delay and holds the connection open so
/// the test thread can observe it.
fn connectAfterDelay(port: u16) void {
    std.time.sleep(50 * std.time.ns_per_ms);
    var client = std.net.tcpConnectToHost(testing.allocator, "127.0.0.1", port) catch return;
    defer client.close();
    std.time.sleep(100 * std.time.ns_per_ms);
}

test "tcp acceptWait returns true when a client connects" {
    var tcp = try Tcp.init(testing.allocator, "127.0.0.1", 0, 0);
    defer tcp.deinit();

    const thread = try std.Thread.spawn(.{}, connectAfterDelay, .{tcp.port()});
    defer thread.join();

    try testing.expect(try tcp.acceptWait(2000));
    try testing.expect(tcp.client != null);
    tcp.closeClient();
}

const ReadTimeoutContext = struct {
    tcp: *Tcp,
    /// Set after the read attempt finishes, so the main thread can safely
    /// read `err` (cross-thread handoff without a data race).
    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// The error readFrame produced, if it returned at all.
    err: ?anyerror = null,
};

/// Accepts a client and reads one frame; the idle timeout (H-1) must make
/// the read fail instead of blocking forever.
fn readFrameSilent(ctx: *ReadTimeoutContext) void {
    ctx.tcp.accept() catch |err| {
        ctx.err = err;
        return;
    };
    const result = ctx.tcp.readFrame(testing.allocator);
    ctx.err = if (result) |frame| blk: {
        testing.allocator.free(frame);
        break :blk null;
    } else |err| err;
    ctx.done.store(true, .release);
}

test "tcp readFrame fails on a silent client after the idle timeout (H-1)" {
    // Short deadline: long enough that a slow CI box does not flake, short
    // enough to keep the suite fast.
    var tcp = try Tcp.init(testing.allocator, "127.0.0.1", 0, 200 * std.time.ns_per_ms);
    defer tcp.deinit();

    var ctx = ReadTimeoutContext{ .tcp = &tcp };
    const thread = try std.Thread.spawn(.{}, readFrameSilent, .{&ctx});
    defer thread.join();

    // Connect but send nothing; the server thread accepts and reads.
    var client = try std.net.tcpConnectToHost(testing.allocator, "127.0.0.1", tcp.port());
    defer client.close();

    // Wait up to 5s for the read to fail (the idle deadline itself is 200ms;
    // the rest is CI slop).
    const deadline = std.time.milliTimestamp() + 5000;
    while (!ctx.done.load(.acquire) and std.time.milliTimestamp() < deadline) {
        std.time.sleep(10 * std.time.ns_per_ms);
    }
    try testing.expect(ctx.done.load(.acquire));
    const err = ctx.err orelse return error.TestDidNotTimeout;
    // The deadline completion won the race; the completion-based io layer
    // surfaces error.ConnectionTimedOut on every platform (worker-
    // resilience.md S1).
    try testing.expect(err == error.ConnectionTimedOut);
}

test "tcp transport satisfies the transport contract" {
    comptime adapter.transport.check(Tcp);
}
