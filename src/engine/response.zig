const std = @import("std");
const Operation = @import("operation.zig").Operation;
const Status = @import("status.zig").Status;

/// The engine's reply to a Request. `payload` is a caller-owned buffer the
/// engine writes into; `payload_len` reports how many bytes were written.
/// The caller owns the buffer and decides its lifetime.
pub const Response = struct {
    operation: Operation,
    status: Status,
    payload: []u8,
    payload_len: usize,

    pub fn init(operation: Operation, buffer: []u8) Response {
        return .{
            .operation = operation,
            .status = .ok,
            .payload = buffer,
            .payload_len = 0,
        };
    }

    /// Bytes written by the engine, without the unused tail of the buffer.
    pub fn slice(self: *const Response) []const u8 {
        std.debug.assert(self.payload_len <= self.payload.len);
        return self.payload[0..self.payload_len];
    }
};
