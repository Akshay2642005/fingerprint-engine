const std = @import("std");
const testing = std.testing;
const io = @import("io");

const Ticker = struct {
    completion: io.Completion = .{ .callback = onComplete },
    order: u32 = 0,
    recorded: u32 = 0,

    fn onComplete(completion: *io.Completion) void {
        const self: *Ticker = @fieldParentPtr("completion", completion);
        self.recorded = self.order;
    }
};

test "executor drains completions in submission order" {
    var executor = io.Executor.init();
    var first = Ticker{ .order = 1 };
    var second = Ticker{ .order = 2 };
    var third = Ticker{ .order = 3 };
    try executor.submit(&first.completion);
    try executor.submit(&second.completion);
    try executor.submit(&third.completion);

    try testing.expectEqual(@as(usize, 3), executor.run());
    try testing.expectEqual(@as(u32, 1), first.recorded);
    try testing.expectEqual(@as(u32, 2), second.recorded);
    try testing.expectEqual(@as(u32, 3), third.recorded);
    try testing.expect(executor.hasPending() == false);
}

test "executor tick processes exactly one completion" {
    var executor = io.Executor.init();
    var first = Ticker{ .order = 1 };
    var second = Ticker{ .order = 2 };
    try executor.submit(&first.completion);
    try executor.submit(&second.completion);

    const ran = executor.tick().?;
    try testing.expectEqual(@as(u32, 1), first.recorded);
    try testing.expectEqual(@as(u32, 0), second.recorded);
    try testing.expect(ran == &first.completion);
    try testing.expectEqual(@as(usize, 1), executor.len());
}

test "executor tick returns null when drained" {
    var executor = io.Executor.init();
    try testing.expectEqual(@as(?*io.Completion, null), executor.tick());
    try testing.expectEqual(@as(usize, 0), executor.run());
}

test "executor rejects submission beyond capacity" {
    var executor = io.Executor.init();
    var completions: [io.completion_capacity]Ticker = undefined;
    for (&completions) |*ticker| {
        try executor.submit(&ticker.completion);
    }
    var extra = Ticker{};
    try testing.expectError(error.QueueFull, executor.submit(&extra.completion));
}
