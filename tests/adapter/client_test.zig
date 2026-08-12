const std = @import("std");
const testing = std.testing;
const io = @import("io");
const adapter = @import("adapter");
const Tcp = adapter.Tcp;
const TcpClient = adapter.TcpClient;

// story: s4-ingress-http

const EchoServerContext = struct {
    tcp: *Tcp,
    failed: bool = false,
};

fn serveEcho(ctx: *EchoServerContext) void {
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

test "TcpClient round-trips a frame against a spawned Tcp echo server" {
    var server = try Tcp.init(testing.allocator, "127.0.0.1", 0, 0);
    defer server.deinit();

    var ctx = EchoServerContext{ .tcp = &server };
    const thread = try std.Thread.spawn(.{}, serveEcho, .{&ctx});
    defer thread.join();

    var client = try TcpClient.init(testing.allocator, "127.0.0.1", server.port(), 0);
    defer client.close();
    try client.connect(2 * std.time.ns_per_s);

    var req_buf: [io.frame.header_size + 32]u8 = undefined;
    const req = try adapter.buildFrame(.signal_package, .binary, "ping", &req_buf);
    try client.writeFrame(req);

    const resp = try client.readFrame(testing.allocator);
    defer testing.allocator.free(resp);
    try testing.expectEqualStrings(req, resp);
    try testing.expect(!ctx.failed);
}

const SilentServerContext = struct {
    tcp: *Tcp,
    /// Set after the server accepted the connection, so the client's frame
    /// lands in a live socket before its read deadline starts.
    accepted: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

/// Accepts a client, reads its frame, then holds the connection without
/// replying — the client's read deadline (H-1) must fire instead of hanging
/// forever.
fn serveSilent(ctx: *SilentServerContext) void {
    ctx.tcp.accept() catch return;
    ctx.accepted.store(true, .release);
    const frame = ctx.tcp.readFrame(testing.allocator) catch return;
    testing.allocator.free(frame);
    std.time.sleep(2 * std.time.ns_per_s);
}

test "TcpClient readFrame fails on a silent peer after the idle timeout (H-1)" {
    // Short deadline: long enough that a slow CI box does not flake, short
    // enough to keep the suite fast.
    var server = try Tcp.init(testing.allocator, "127.0.0.1", 0, 0);
    defer server.deinit();

    var ctx = SilentServerContext{ .tcp = &server };
    const thread = try std.Thread.spawn(.{}, serveSilent, .{&ctx});
    defer thread.join();

    var client = try TcpClient.init(
        testing.allocator,
        "127.0.0.1",
        server.port(),
        200 * std.time.ns_per_ms,
    );
    defer client.close();
    try client.connect(2 * std.time.ns_per_s);

    var req_buf: [io.frame.header_size + 8]u8 = undefined;
    const req = try adapter.buildFrame(.signal_package, .binary, "hi", &req_buf);
    try client.writeFrame(req);

    // Wait up to 5s for the server to accept (the connect already completed
    // at the kernel level; the accept thread just needs to run).
    const deadline = std.time.milliTimestamp() + 5000;
    while (!ctx.accepted.load(.acquire) and std.time.milliTimestamp() < deadline) {
        std.time.sleep(10 * std.time.ns_per_ms);
    }
    try testing.expect(ctx.accepted.load(.acquire));

    // The server never replies; the client's read deadline fires.
    const result = client.readFrame(testing.allocator);
    try testing.expectError(error.ConnectionTimedOut, result);
}
