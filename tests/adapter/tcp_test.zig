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
    var tcp = try Tcp.init(testing.allocator, "127.0.0.1", 0);
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

test "tcp readFrame without a client reports not connected" {
    var tcp = try Tcp.init(testing.allocator, "127.0.0.1", 0);
    defer tcp.deinit();
    try testing.expectError(error.NotConnected, tcp.readFrame(testing.allocator));
}

test "tcp transport satisfies the transport contract" {
    comptime adapter.transport.check(Tcp);
}
