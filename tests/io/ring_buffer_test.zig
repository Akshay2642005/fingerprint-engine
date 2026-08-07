const std = @import("std");
const testing = std.testing;
const io = @import("io");

const Ring = io.RingBufferType(u32, 3);

test "ring buffer pushes and pops in FIFO order" {
    var ring = Ring.init();
    try ring.push(10);
    try ring.push(20);
    try ring.push(30);
    try testing.expectEqual(@as(u32, 10), ring.pop().?);
    try testing.expectEqual(@as(u32, 20), ring.pop().?);
    try testing.expectEqual(@as(u32, 30), ring.pop().?);
    try testing.expectEqual(@as(?u32, null), ring.pop());
}

test "ring buffer reports empty state" {
    var ring = Ring.init();
    try testing.expect(ring.empty());
    try testing.expectEqual(@as(usize, 0), ring.len());
    try testing.expectEqual(@as(?u32, null), ring.head());
}

test "ring buffer rejects push at capacity" {
    var ring = Ring.init();
    try ring.push(1);
    try ring.push(2);
    try ring.push(3);
    try testing.expect(ring.full());
    try testing.expectError(error.Full, ring.push(4));
    try testing.expectEqual(@as(usize, 3), ring.len());
}

test "ring buffer wraps around the slot array" {
    var ring = Ring.init();
    try ring.push(1);
    try ring.push(2);
    try ring.push(3);
    try testing.expectEqual(@as(u32, 1), ring.pop().?);
    try testing.expectEqual(@as(u32, 2), ring.pop().?);
    try ring.push(4);
    try ring.push(5);
    try testing.expectEqual(@as(u32, 3), ring.pop().?);
    try testing.expectEqual(@as(u32, 4), ring.pop().?);
    try testing.expectEqual(@as(u32, 5), ring.pop().?);
    try testing.expectEqual(@as(?u32, null), ring.pop());
}

test "ring buffer head peeks without popping" {
    var ring = Ring.init();
    try ring.push(7);
    try testing.expectEqual(@as(u32, 7), ring.head().?);
    try testing.expectEqual(@as(usize, 1), ring.len());
    try testing.expectEqual(@as(u32, 7), ring.pop().?);
}

test "ring buffer clear resets state" {
    var ring = Ring.init();
    try ring.push(1);
    try ring.push(2);
    ring.clear();
    try testing.expect(ring.empty());
    try testing.expectEqual(@as(usize, 0), ring.len());
    try ring.push(9);
    try testing.expectEqual(@as(u32, 9), ring.pop().?);
}
