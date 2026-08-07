const std = @import("std");
const Completion = @import("completion.zig").Completion;
const RingBufferType = @import("ring_buffer.zig").RingBufferType;

/// A typed single-producer single-consumer channel over a fixed ring
/// buffer. `trySend`/`tryRecv` are the non-blocking core; `send` adds a
/// completion-based variant that parks the item when the buffer is full and
/// completes the waiter as soon as `recv` frees a slot (backpressure
/// without blocking).
pub fn ChannelType(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        const PendingSend = struct {
            item: T,
            completion: *Completion,
        };

        ring: RingBufferType(T, capacity) = .init(),
        pending: ?PendingSend = null,

        pub fn init() Self {
            return .{};
        }

        pub fn trySend(self: *Self, item: T) error{Full}!void {
            try self.ring.push(item);
        }

        pub fn tryRecv(self: *Self) ?T {
            return self.ring.pop();
        }

        /// Completion-based send. Stores the item and completes `completion`
        /// inline, returning true; when full, parks the pair until the next
        /// `recv` frees a slot and returns false. Single-producer contract:
        /// only one send may be parked at a time.
        pub fn send(self: *Self, item: T, completion: *Completion) bool {
            self.ring.push(item) catch {
                std.debug.assert(self.pending == null);
                self.pending = .{ .item = item, .completion = completion };
                return false;
            };
            completion.complete();
            return true;
        }

        /// Pops an item; if a send was parked, stores it and completes the
        /// waiter.
        pub fn recv(self: *Self) ?T {
            const item = self.ring.pop() orelse return null;
            self.flushPending();
            return item;
        }

        fn flushPending(self: *Self) void {
            const pending = self.pending orelse return;
            self.pending = null;
            self.ring.push(pending.item) catch unreachable;
            pending.completion.complete();
        }
    };
}
