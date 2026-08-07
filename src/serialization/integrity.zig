/// Payload integrity (design §5): SHA-256 digest used by the FPKG frame's
/// integrity field. Defined here so serialization stays transport-free; the
/// frame header in io/frame.zig implements the same algorithm for envelope
/// validation.
const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

/// SHA-256 digest of a serialized payload.
pub fn integrityOf(payload: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    Sha256.hash(payload, &digest, .{});
    return digest;
}

/// True when `expected` matches the SHA-256 of `payload`.
pub fn integrityValid(expected: [32]u8, payload: []const u8) bool {
    return std.mem.eql(u8, &expected, &integrityOf(payload));
}
