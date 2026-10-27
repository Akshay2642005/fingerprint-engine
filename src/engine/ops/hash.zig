const std = @import("std");
const core = @import("core");
const model = @import("model");
const format = @import("../format.zig");
const Request = @import("../request.zig").Request;
const Response = @import("../response.zig").Response;

/// Wire layout of `fingerprint_result` v2 (ADR-013 §3).
///
/// The stable-core triple is appended at the tail, so the first 36 bytes are
/// v1 byte-for-byte and legacy readers keep parsing them. New readers gate on
/// `payload_len >= Layout.len`.
///
/// Offsets are pinned below the struct: the compile-time guard rejects any
/// edit that leaves gaps, changes a width, or disagrees with the totals.
pub const Layout = struct {
    pub const Field = struct { offset: usize, len: usize };

    pub const fingerprint_digest: Field = .{ .offset = 0, .len = 32 };
    pub const feature_count: Field = .{ .offset = 32, .len = 2 };
    pub const schema_version: Field = .{ .offset = 34, .len = 2 };
    pub const core_digest: Field = .{ .offset = 36, .len = 32 };
    pub const core_feature_count: Field = .{ .offset = 68, .len = 2 };
    pub const core_version: Field = .{ .offset = 70, .len = 2 };

    /// v1 payload length — the stable prefix.
    pub const v1_len: usize = 36;
    /// v2 payload length — v1 + the appended core triple.
    pub const len: usize = 72;
};

comptime {
    const fields = [_]Layout.Field{
        Layout.fingerprint_digest,
        Layout.feature_count,
        Layout.schema_version,
        Layout.core_digest,
        Layout.core_feature_count,
        Layout.core_version,
    };
    var end: usize = 0;
    for (fields) |field| {
        if (field.offset != end) {
            @compileError("fingerprint_result layout: fields must be contiguous");
        }
        end += field.len;
    }
    if (end != Layout.len) {
        @compileError("fingerprint_result layout: field widths must sum to Layout.len");
    }
    if (Layout.v1_len != Layout.core_digest.offset) {
        @compileError("fingerprint_result layout: the v1 prefix must end where the append begins");
    }
    if (Layout.fingerprint_digest.len != 32 or Layout.core_digest.len != 32) {
        @compileError("fingerprint_result layout: digests are SHA-256 (32 bytes)");
    }
}

/// hash: SignalPackage (canonicalized) → two-digest FingerprintResult.
///
///   [32] fingerprint_digest | u16 feature_count | u16 schema_version  ← v1
///   [32] core_digest        | u16 core_feature_count | u16 core_version
///
/// Features are sorted by FeatureID first so both digests are independent of
/// collection order — same signals, same digest, on any platform. The core
/// digest covers only registry-flagged `core` features, so a window resize
/// (volatile geometry) changes the full digest but keeps the core digest.
// story: m7-two-digest
pub fn handle(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    var fp = try format.decode(req, scratch);
    format.canonicalize(&fp);

    var digest: [32]u8 = undefined;
    core.hashing.hashFingerprintBuffer(fp.features, &digest);

    var core_digest: [32]u8 = undefined;
    const core_feature_count = core.hashing.hashCoreFingerprintBuffer(fp.features, &core_digest);

    if (res.payload.len < Layout.len) return error.BufferFull;
    const out = res.payload[0..Layout.len];

    @memcpy(
        out[Layout.fingerprint_digest.offset..][0..Layout.fingerprint_digest.len],
        &digest,
    );
    std.mem.writeInt(
        u16,
        out[Layout.feature_count.offset..][0..Layout.feature_count.len],
        @intCast(fp.features.len),
        .little,
    );
    std.mem.writeInt(
        u16,
        out[Layout.schema_version.offset..][0..Layout.schema_version.len],
        fp.metadata.schema_version,
        .little,
    );

    @memcpy(
        out[Layout.core_digest.offset..][0..Layout.core_digest.len],
        &core_digest,
    );
    std.mem.writeInt(
        u16,
        out[Layout.core_feature_count.offset..][0..Layout.core_feature_count.len],
        core_feature_count,
        .little,
    );
    std.mem.writeInt(
        u16,
        out[Layout.core_version.offset..][0..Layout.core_version.len],
        model.Registry.core_version,
        .little,
    );

    res.payload_len = Layout.len;
}
