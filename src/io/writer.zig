const std = @import("std");

/// A fixed-buffer writer over a mutable byte slice. Owns no memory; writes
/// advance `position` until the buffer is exhausted (`error.BufferFull`).
/// Written bytes are exposed via `written()`. The method shape matches what
/// the serialization codecs consume, so `Writer` works as an `anytype`
/// writer without depending on std.io.
pub const Writer = struct {
    buffer: []u8,
    position: usize = 0,

    pub fn init(buffer: []u8) Writer {
        return .{ .buffer = buffer };
    }

    /// Bytes not yet used.
    pub fn remaining(self: *const Writer) usize {
        return self.buffer.len - self.position;
    }

    pub fn writeByte(self: *Writer, byte: u8) error{BufferFull}!void {
        if (self.position >= self.buffer.len) return error.BufferFull;
        self.buffer[self.position] = byte;
        self.position += 1;
    }

    pub fn writeBytes(self: *Writer, bytes: []const u8) error{BufferFull}!void {
        if (self.remaining() < bytes.len) return error.BufferFull;
        @memcpy(self.buffer[self.position .. self.position + bytes.len], bytes);
        self.position += bytes.len;
    }

    /// Little-endian fixed-width integer write, portable across hosts.
    pub fn writeInt(self: *Writer, comptime T: type, value: T) error{BufferFull}!void {
        const size = @sizeOf(T);
        if (self.remaining() < size) return error.BufferFull;
        const ptr: *align(1) T = @ptrCast(self.buffer.ptr + self.position);
        ptr.* = std.mem.nativeToLittle(T, value);
        self.position += size;
    }

    /// Bytes written so far.
    pub fn written(self: *const Writer) []const u8 {
        return self.buffer[0..self.position];
    }
};
