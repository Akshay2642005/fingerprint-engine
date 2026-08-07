const std = @import("std");
const testing = std.testing;
const io = @import("io");

const Handler = struct {
    completion: io.Completion = .{ .callback = onComplete },
    calls: u32 = 0,

    fn onComplete(completion: *io.Completion) void {
        const self: *Handler = @fieldParentPtr("completion", completion);
        self.calls += 1;
    }
};

test "embedded completion recovers parent and runs callback" {
    var handler = Handler{};
    handler.completion.complete();
    handler.completion.complete();
    try testing.expectEqual(@as(u32, 2), handler.calls);
}

fn onCompleteCtx(completion: *io.Completion) void {
    const marker: *u32 = @ptrCast(@alignCast(completion.context.?));
    marker.* += 1;
}

test "completion init stores and restores context" {
    var marker: u32 = 0;
    var completion = io.Completion.init(onCompleteCtx, @ptrCast(&marker));
    completion.complete();
    try testing.expectEqual(@as(u32, 1), marker);
}
