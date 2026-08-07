/// Result status of an engine operation. The engine never throws across the
/// API boundary: it folds every failure into a `Status` on the `Response`.
pub const Status = enum(u8) {
    ok = 0,
    invalid_request = 1, // malformed operation/codec
    invalid_payload = 2, // decode failure
    unsupported_version = 3, // envelope/body version mismatch
    invalid_input = 4, // validation/normalization failed hard
    buffer_overflow = 5, // caller buffer too small for the result
    out_of_memory = 6,
    internal_error = 7,

    /// Wire representation: the u8 tag.
    pub fn code(self: Status) u8 {
        return @intFromEnum(self);
    }
};
