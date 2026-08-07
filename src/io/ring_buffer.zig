const std = @import("std");

/// A fixed-capacity FIFO ring buffer over `T` slots. Single-producer
/// single-consumer by construction: `push` from one side, `pop` from the
/// other. `capacity` is comptime so the storage is inline (no allocation).
pub fn RingBufferType(comptime T: type, comptime capacity: usize) type {
    comptime std.debug.assert(capacity > 0);
    return struct {
        const Self = @This();

        pub const count_max = capacity;

        slots: [capacity]T = undefined,
        /// Slot index of the first item (the next pop).
        index: usize = 0,
        /// Number of items currently stored.
        count: usize = 0,

        pub fn init() Self {
            return .{};
        }

        pub fn empty(self: *const Self) bool {
            return self.count == 0;
        }

        pub fn full(self: *const Self) bool {
            return self.count == capacity;
        }

        pub fn len(self: *const Self) usize {
            return self.count;
        }

        pub fn clear(self: *Self) void {
            self.index = 0;
            self.count = 0;
        }

        /// Next item to pop, without removing it.
        pub fn head(self: *const Self) ?T {
            if (self.empty()) return null;
            return self.slots[self.index];
        }

        /// Appends an item; `error.Full` when at capacity.
        pub fn push(self: *Self, item: T) error{Full}!void {
            if (self.full()) return error.Full;
            const slot = (self.index + self.count) % capacity;
            self.slots[slot] = item;
            self.count += 1;
        }

        /// Removes and returns the oldest item, or null when empty.
        pub fn pop(self: *Self) ?T {
            if (self.empty()) return null;
            const item = self.slots[self.index];
            self.index = (self.index + 1) % capacity;
            self.count -= 1;
            return item;
        }
    };
}
