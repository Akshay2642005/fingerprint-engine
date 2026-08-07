const std = @import("std");
const testing = std.testing;
const io = @import("io");

test "message pool make copies bytes" {
    var pool = io.MessagePool.init(testing.allocator);
    defer pool.deinit();
    const message = try pool.make("payload");
    try testing.expectEqual(@as(usize, 7), message.len());
    try testing.expectEqualStrings("payload", message.slice());
}

test "message pool makeEmpty exposes mutable payload" {
    var pool = io.MessagePool.init(testing.allocator);
    defer pool.deinit();
    var message = try pool.makeEmpty(4);
    @memcpy(message.sliceMut(), "data");
    try testing.expectEqualStrings("data", message.slice());
}

test "message pool duplicate allocates an independent copy" {
    var pool = io.MessagePool.init(testing.allocator);
    defer pool.deinit();
    const source = "original";
    const copy = try pool.duplicate(source);
    try testing.expectEqualStrings(source, copy);
    copy[0] = 'X';
    try testing.expectEqualStrings("original", source);
}

test "message pool reset recycles storage for reuse" {
    var pool = io.MessagePool.init(testing.allocator);
    defer pool.deinit();
    const first = try pool.make("one");
    try testing.expectEqualStrings("one", first.slice());
    pool.reset();
    const second = try pool.make("two");
    try testing.expectEqualStrings("two", second.slice());
}

test "message pool allocator hands out arena memory" {
    var pool = io.MessagePool.init(testing.allocator);
    defer pool.deinit();
    const bytes = try pool.allocator().alloc(u8, 3);
    @memcpy(bytes, "abc");
    try testing.expectEqualStrings("abc", bytes);
}
