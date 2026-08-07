const std = @import("std");
const testing = std.testing;
const io = @import("io");

const Op = enum(u8) { first = 1, second = 2, third = 3 };
const Handler = *const fn (u32) u32;

fn double(value: u32) u32 {
    return value * 2;
}

fn triple(value: u32) u32 {
    return value * 3;
}

const table = [_]io.Entry(Op, Handler){
    .{ .op = .first, .handler = double },
    .{ .op = .third, .handler = triple },
};

const Dispatcher = io.DispatcherType(Op, Handler, &table);

test "dispatcher returns the registered handler" {
    const first = Dispatcher.lookup(.first).?;
    try testing.expectEqual(@as(u32, 4), first(2));
    try testing.expectEqual(@as(u32, 9), Dispatcher.lookup(.third).?(3));
}

test "dispatcher returns null for an unregistered op" {
    try testing.expectEqual(@as(?Handler, null), Dispatcher.lookup(.second));
}
