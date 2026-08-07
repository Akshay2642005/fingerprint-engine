const std = @import("std");
const testing = std.testing;
const io = @import("io");

const Channel = io.ChannelType(u32, 2);

test "channel trySend and tryRecv round trip" {
    var channel = Channel.init();
    try channel.trySend(1);
    try channel.trySend(2);
    try testing.expectEqual(@as(u32, 1), channel.tryRecv().?);
    try testing.expectEqual(@as(u32, 2), channel.tryRecv().?);
}

test "channel rejects trySend at capacity and tryRecv when empty" {
    var channel = Channel.init();
    try channel.trySend(1);
    try channel.trySend(2);
    try testing.expectError(error.Full, channel.trySend(3));
    _ = channel.tryRecv();
    _ = channel.tryRecv();
    try testing.expectEqual(@as(?u32, null), channel.tryRecv());
}

const Receiver = struct {
    completion: io.Completion = .{ .callback = onComplete },
    received: u32 = 0,

    fn onComplete(completion: *io.Completion) void {
        const self: *Receiver = @fieldParentPtr("completion", completion);
        self.received += 1;
    }
};

test "completion-based send completes inline when space is available" {
    var channel = Channel.init();
    var receiver = Receiver{};
    const sent = channel.send(42, &receiver.completion);
    try testing.expect(sent);
    try testing.expectEqual(@as(u32, 1), receiver.received);
    try testing.expectEqual(@as(u32, 42), channel.tryRecv().?);
}

test "completion-based send parks when full and flushes on recv" {
    var channel = Channel.init();
    var first = Receiver{};
    var second = Receiver{};
    var third = Receiver{};
    try testing.expect(channel.send(1, &first.completion));
    try testing.expect(channel.send(2, &second.completion));
    try testing.expect(!channel.send(3, &third.completion));
    try testing.expectEqual(@as(u32, 0), third.received);

    try testing.expectEqual(@as(u32, 1), channel.recv().?);
    try testing.expectEqual(@as(u32, 1), third.received);
    try testing.expectEqual(@as(u32, 2), channel.recv().?);
    try testing.expectEqual(@as(u32, 3), channel.recv().?);
}
