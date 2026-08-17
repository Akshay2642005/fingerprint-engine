const std = @import("std");
const assert = std.debug.assert;

/// Intrusive singly-linked FIFO. The element type `T` must embed a
/// `link: QueueType(T).Link` field; recovery is via `@fieldParentPtr`, so
/// queue membership costs zero extra allocation.
///
/// This is the io backends' substrate (timeouts/completed queues), adapted
/// from TigerBeetle's `src/queue.zig` and trimmed to what the event loop
/// needs: push/pop/remove/iterate — no names, no verify hooks, no counters
/// beyond `count`.
const QueueLink = struct {
    next: ?*QueueLink = null,
};

pub fn QueueType(comptime T: type) type {
    return struct {
        pub const Link = QueueLink;
        const Queue = @This();

        in: ?*QueueLink = null,
        out: ?*QueueLink = null,
        len: usize = 0,

        pub fn init() Queue {
            return .{};
        }

        pub inline fn push(self: *Queue, link: *T) void {
            assert(link.link.next == null);
            if (self.in) |in| {
                in.next = &link.link;
                self.in = &link.link;
            } else {
                assert(self.out == null);
                self.in = &link.link;
                self.out = &link.link;
            }
            self.len += 1;
        }

        pub inline fn pop(self: *Queue) ?*T {
            const link = self.out orelse return null;
            self.out = link.next;
            link.next = null;
            if (self.in == link) self.in = null;
            self.len -= 1;
            return @alignCast(@fieldParentPtr("link", link));
        }

        pub inline fn peek(self: *const Queue) ?*T {
            const link = self.out orelse return null;
            return @alignCast(@fieldParentPtr("link", link));
        }

        pub inline fn peek_last(self: *const Queue) ?*T {
            const link = self.in orelse return null;
            return @alignCast(@fieldParentPtr("link", link));
        }

        pub inline fn empty(self: *const Queue) bool {
            return self.peek() == null;
        }

        pub inline fn count(self: *const Queue) usize {
            return self.len;
        }

        /// Whether the linked list contains `needle` (pointer comparison).
        pub fn contains(self: *const Queue, needle: *const T) bool {
            var link = self.out;
            while (link) |current| : (link = current.next) {
                if (current == &needle.link) return true;
            }
            return false;
        }

        /// Removes `to_remove`, which must be in the queue. O(N) — the io
        /// queues hold a handful of completions, so this is fine.
        pub fn remove(self: *Queue, to_remove: *T) void {
            if (to_remove == self.peek()) {
                _ = self.pop();
                return;
            }
            var link = self.out;
            while (link) |current| : (link = current.next) {
                const candidate: *T = @fieldParentPtr("link", current.next.?);
                if (to_remove == candidate) {
                    const removed_link = current.next.?;
                    if (to_remove == self.peek_last()) self.in = current;
                    current.next = removed_link.next;
                    removed_link.next = null;
                    self.len -= 1;
                    return;
                }
            } else unreachable; // to_remove is not in the queue
        }

        pub fn reset(self: *Queue) void {
            self.* = .{};
        }

        pub fn iterate(self: *const Queue) Iterator {
            return .{ .link = self.out };
        }

        pub const Iterator = struct {
            link: ?*QueueLink,

            pub fn next(iterator: *Iterator) ?*T {
                const link = iterator.link orelse return null;
                iterator.link = link.next;
                return @alignCast(@fieldParentPtr("link", link));
            }
        };
    };
}

const testing = std.testing;

test "queue: push/pop/peek/remove/iterate" {
    const Item = struct { value: u32, link: QueueType(@This()).Link = .{} };
    const Queue = QueueType(Item);

    var one = Item{ .value = 1 };
    var two = Item{ .value = 2 };
    var three = Item{ .value = 3 };

    var queue = Queue.init();
    try testing.expect(queue.empty());
    try testing.expectEqual(@as(?*Item, null), queue.pop());

    queue.push(&one);
    queue.push(&two);
    queue.push(&three);
    try testing.expectEqual(@as(usize, 3), queue.count());
    try testing.expectEqual(@as(?*Item, &one), queue.peek());
    try testing.expectEqual(@as(?*Item, &three), queue.peek_last());
    try testing.expect(queue.contains(&two));
    try testing.expect(!queue.contains(&Item{ .value = 4 }));

    queue.remove(&two);
    try testing.expectEqual(@as(usize, 2), queue.count());
    try testing.expectEqual(@as(?*Item, &one), queue.pop());
    try testing.expectEqual(@as(?*Item, &three), queue.pop());
    try testing.expectEqual(@as(?*Item, null), queue.pop());
    try testing.expect(queue.empty());
}

test "queue: remove head and tail" {
    const Item = struct { value: u32, link: QueueType(@This()).Link = .{} };
    const Queue = QueueType(Item);

    var one = Item{ .value = 1 };
    var two = Item{ .value = 2 };
    var three = Item{ .value = 3 };

    var queue = Queue.init();
    queue.push(&one);
    queue.push(&two);
    queue.push(&three);

    queue.remove(&one); // head
    try testing.expectEqual(@as(?*Item, &two), queue.pop());

    queue.push(&one);
    queue.remove(&three); // tail
    try testing.expectEqual(@as(?*Item, &two), queue.pop());
    try testing.expectEqual(@as(?*Item, &one), queue.pop());
    try testing.expect(queue.empty());
}

test "queue: iterate visits every element once" {
    const Item = struct { value: u32, link: QueueType(@This()).Link = .{} };
    const Queue = QueueType(Item);

    var items = [_]Item{ .{ .value = 1 }, .{ .value = 2 }, .{ .value = 3 } };
    var queue = Queue.init();
    for (&items) |*item| queue.push(item);

    var seen: u32 = 0;
    var iterator = queue.iterate();
    while (iterator.next()) |item| seen += item.value;
    try testing.expectEqual(@as(u32, 6), seen);
}
