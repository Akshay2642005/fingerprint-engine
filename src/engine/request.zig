const Operation = @import("operation.zig").Operation;

/// Codec identifiers shared by the engine and the FPKG envelope. Values are
/// explicit wire tags; non-exhaustive so unknown tags map to
/// `invalid_request` rather than a misread payload.
pub const CodecID = enum(u8) {
    binary = 1,
    json = 2,
    _,
};

/// An immutable engine request. `payload` is borrowed input: the caller
/// owns it and the engine never mutates or frees it. The engine is
/// stateless — the same Request always yields the same Response.
pub const Request = struct {
    operation: Operation,
    codec: CodecID, // binary = 1, json = 2 (default binary)
    /// Serialized input. For similarity this is the dual-encoded `{a, b}`
    /// payload: u32 a_len | a bytes | b bytes.
    payload: []const u8,
};
