const std = @import("std");
const testing = std.testing;
const io = @import("io");
const adapter = @import("adapter");
const Loopback = adapter.Loopback;

test "loopback memory mode round-trips a request/response pair" {
    var lp = Loopback.init(testing.allocator, .memory);
    defer lp.deinit();

    var req_buf: [io.frame.header_size + 32]u8 = undefined;
    const req = try adapter.buildFrame(.signal_package, .binary, "request", &req_buf);
    try lp.enqueueRequest(req);

    const inbound = try lp.readFrame(testing.allocator);
    defer testing.allocator.free(inbound);
    try testing.expectEqualStrings(req, inbound);

    var resp_buf: [io.frame.header_size + 32]u8 = undefined;
    const resp = try adapter.buildFrame(.fingerprint_result, .binary, "response", &resp_buf);
    try lp.writeFrame(resp);

    const outbound = lp.takeResponse().?;
    defer testing.allocator.free(outbound);
    try testing.expectEqualStrings(resp, outbound);
}

test "loopback memory mode reports end of stream when the queue is empty" {
    var lp = Loopback.init(testing.allocator, .memory);
    defer lp.deinit();
    try testing.expectError(error.EndOfStream, lp.readFrame(testing.allocator));
}

test "loopback memory mode drains requests in order" {
    var lp = Loopback.init(testing.allocator, .memory);
    defer lp.deinit();

    var first_buf: [io.frame.header_size + 32]u8 = undefined;
    var second_buf: [io.frame.header_size + 32]u8 = undefined;
    const first = try adapter.buildFrame(.signal_package, .binary, "first", &first_buf);
    const second = try adapter.buildFrame(.signal_package, .binary, "second", &second_buf);
    try lp.enqueueRequest(first);
    try lp.enqueueRequest(second);

    const a = try lp.readFrame(testing.allocator);
    defer testing.allocator.free(a);
    const b = try lp.readFrame(testing.allocator);
    defer testing.allocator.free(b);
    try testing.expectEqualStrings(first, a);
    try testing.expectEqualStrings(second, b);
}

test "loopback publish and ack are no-ops" {
    var lp = Loopback.init(testing.allocator, .memory);
    defer lp.deinit();
    try lp.publish("outbound event");
    lp.ack("poison frame");
}

test "loopback transport satisfies the transport contract" {
    comptime adapter.transport.check(Loopback);
}
