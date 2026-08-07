const std = @import("std");
const model = @import("model");
const core = @import("core");
const serialization = @import("serialization");
const Request = @import("request.zig").Request;

/// Decode failures with a stable mapping to `Status` (see engine.mapError).
pub const DecodeError = error{
    InvalidPayload,
    UnsupportedVersion,
    OutOfMemory,
};

/// The FNGR body schema versions this engine understands. v1 is the legacy
/// layout (schema + feature_count + features); v2 (serialization rewrite)
/// adds sdk metadata, collection time, and replay identity. Unknown versions
/// are rejected at the boundary before the codec parses anything.
pub const schema_versions = [_]u16{
    serialization.schema_version_v1,
    serialization.schema_version_v2,
};

/// Warning-kind tags shared by the validate/normalize/package result layouts.
pub const kind_type_mismatch: u8 = 1;
pub const kind_bound_violation: u8 = 2;

/// Decodes the request payload into a Fingerprint. The returned fingerprint
/// borrows from `scratch` (arena); no deinit is required.
pub fn decode(req: *const Request, scratch: std.mem.Allocator) DecodeError!model.Fingerprint {
    if (req.codec != .binary) return error.InvalidPayload; // json decode lands with the serialization rewrite
    return decodePayload(req.payload, scratch);
}

/// Decodes a bare binary-encoded Fingerprint payload (FNGR v1 or v2).
/// Rejects unknown body schema versions before handing off to the codec.
pub fn decodePayload(payload: []const u8, scratch: std.mem.Allocator) DecodeError!model.Fingerprint {
    var fbs = std.io.fixedBufferStream(payload);
    const decoded = serialization.decode(fbs.reader(), scratch) catch |err| switch (err) {
        error.InvalidMagic, error.Truncated => return error.InvalidPayload,
        error.OutOfMemory => return error.OutOfMemory,
        error.UnsupportedVersion => return error.UnsupportedVersion,
    };
    if (std.mem.indexOfScalar(u16, &schema_versions, decoded.fingerprint.metadata.schema_version) == null) {
        return error.UnsupportedVersion;
    }
    return decoded.fingerprint;
}

/// Sorts features in place by FeatureID. Deterministic hashing requires a
/// canonical feature order; scratch-owned decoded memory is safe to reorder.
pub fn canonicalize(fp: *model.Fingerprint) void {
    const feats: []model.Feature = @constCast(fp.features);
    std.mem.sort(model.Feature, feats, {}, struct {
        fn lessThan(_: void, a: model.Feature, b: model.Feature) bool {
            return @intFromEnum(a.id) < @intFromEnum(b.id);
        }
    }.lessThan);
}

/// Writes `u16 count | (u8 kind | u16 feature_id)×count` — the shared
/// normalization-warning block of the normalize/validate/package results.
pub fn writeNormalizationWarnings(
    w: anytype,
    norm: []const core.normalization.NormalizationWarning,
) !void {
    try w.writeInt(u16, @intCast(norm.len), .little);
    for (norm) |nw| switch (nw) {
        .type_mismatch => |tw| {
            try w.writeByte(kind_type_mismatch);
            try w.writeInt(u16, @intFromEnum(tw.feature_id), .little);
        },
        .bound_violation => |bw| {
            try w.writeByte(kind_bound_violation);
            try w.writeInt(u16, @intFromEnum(bw.feature_id), .little);
        },
    };
}

/// Writes the validation result block used by the validate op:
/// `u8 is_valid | u16 required_count | (u16 feature_id | u8 is_critical)×N |
/// normalization block`. The package op embeds the same block ahead of the
/// serialized package so consumers get diagnostics with the payload.
pub fn writeValidationResult(
    w: anytype,
    required: []const core.validation.RequiredWarning,
    norm: []const core.normalization.NormalizationWarning,
) !void {
    try w.writeByte(if (required.len == 0 and norm.len == 0) 1 else 0);
    try w.writeInt(u16, @intCast(required.len), .little);
    for (required) |rw| {
        try w.writeInt(u16, @intFromEnum(rw.feature_id), .little);
        try w.writeByte(if (rw.is_critical) 1 else 0);
    }
    try writeNormalizationWarnings(w, norm);
}
