const std = @import("std");
const Operation = @import("operation.zig").Operation;

/// Codec identifiers shared by the engine and the FPKG envelope. Single source
/// of truth is serialization/codec.zig (wire-stable tags); the engine aliases
/// it so the request path can never drift from the codec registry.
pub const CodecID = @import("serialization").CodecID;

/// An immutable engine request. `payload` is borrowed input: the caller
/// owns it and the engine never mutates or frees it. The engine is
/// stateless — the same Request always yields the same Response.
pub const Request = struct {
    operation: Operation,
    codec: CodecID, // binary = 1, json = 2 (default binary)
    /// Serialized input. For similarity this is the dual-encoded `{a, b}`
    /// payload: u32 a_len | a bytes | b bytes.
    payload: []const u8,

    pub fn init(op: Operation, codec_id: CodecID, payload: []const u8) Request {
        std.debug.assert(payload.len > 0 or op == .validate or op == .hash);
        return .{ .operation = op, .codec = codec_id, .payload = payload };
    }
};
