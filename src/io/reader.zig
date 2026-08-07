const std = @import("std");

/// A fixed-buffer reader over an immutable byte slice. Owns no memory and
/// performs no allocation; it only advances `position`. The method shape
/// (`readByte`, `readInt`, `readSlice`) is what the serialization codecs
/// consume, so `Reader` works as an `anytype` reader without depending on
/// std.io.
pub const Reader = struct {
    buffer: []const u8,
    position: usize = 0,

    pub fn init(buffer: []const u8) Reader {
        return .{ .buffer = buffer };
    }

    /// Bytes not yet consumed.
    pub fn remaining(self: *const Reader) usize {
        return self.buffer.len - self.position;
    }

    pub fn readByte(self: *Reader) error{OutOfBounds}!u8 {
        if (self.position >= self.buffer.len) return error.OutOfBounds;
        const byte = self.buffer[self.position];
        self.position += 1;
        return byte;
    }

    /// Reads `dest.len` bytes into a caller-owned buffer.
    pub fn readSlice(self: *Reader, dest: []u8) error{OutOfBounds}!void {
        if (self.remaining() < dest.len) return error.OutOfBounds;
        @memcpy(dest, self.buffer[self.position .. self.position + dest.len]);
        self.position += dest.len;
    }

    /// Little-endian fixed-width integer read, portable across hosts.
    pub fn readInt(self: *Reader, comptime T: type) error{OutOfBounds}!T {
        const size = @sizeOf(T);
        if (self.remaining() < size) return error.OutOfBounds;
        const ptr: *align(1) const T = @ptrCast(self.buffer.ptr + self.position);
        const value = std.mem.littleToNative(T, ptr.*);
        self.position += size;
        return value;
    }

    /// Returns the remaining bytes without copying and consumes them.
    pub fn readRemaining(self: *Reader) []const u8 {
        const rest = self.buffer[self.position..];
        self.position = self.buffer.len;
        return rest;
    }
};
