const std = @import("std");
const Allocator = std.mem.Allocator;

/// An arena-backed message: `data` is owned by `pool` and stays valid until
/// the pool's next `reset()`. Copying a Message copies the slice header,
/// not the payload — explicit ownership, exactly one owner (the pool).
pub const Message = struct {
    data: []u8,
    pool: *MessagePool,

    pub fn len(self: *const Message) usize {
        return self.data.len;
    }

    /// Immutable view of the payload.
    pub fn slice(self: *const Message) []const u8 {
        return self.data;
    }

    /// Mutable view of the payload.
    pub fn sliceMut(self: *Message) []u8 {
        return self.data;
    }
};

/// A simple arena message pool: allocations come from one arena and
/// `reset()` invalidates every outstanding message while recycling storage.
/// One owner, no individual frees — per-message allocation cost is a single
/// arena bump.
pub const MessagePool = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(backing: Allocator) MessagePool {
        return .{ .arena = std.heap.ArenaAllocator.init(backing) };
    }

    pub fn deinit(self: *MessagePool) void {
        self.arena.deinit();
    }

    /// Invalidates all outstanding messages and recycles storage.
    pub fn reset(self: *MessagePool) void {
        _ = self.arena.reset(.retain_capacity);
    }

    pub fn allocator(self: *MessagePool) Allocator {
        return self.arena.allocator();
    }

    /// Allocates an uninitialized payload of `len` bytes.
    pub fn alloc(self: *MessagePool, len: usize) ![]u8 {
        return self.arena.allocator().alloc(u8, len);
    }

    /// Copies `bytes` into a fresh pool-owned payload.
    pub fn duplicate(self: *MessagePool, bytes: []const u8) ![]u8 {
        return self.arena.allocator().dupe(u8, bytes);
    }

    /// Creates a message that copies `bytes`.
    pub fn make(self: *MessagePool, bytes: []const u8) !Message {
        return .{ .data = try self.duplicate(bytes), .pool = self };
    }

    /// Creates a message with an uninitialized payload of `len` bytes.
    pub fn makeEmpty(self: *MessagePool, len: usize) !Message {
        return .{ .data = try self.alloc(len), .pool = self };
    }
};
