const std = @import("std");
const features = @import("../features/root.zig");
const fingerprint = @import("../fingerprint/root.zig");
const hashing = @import("root.zig");

const Feature = fingerprint.Feature;
const Fingerprint = fingerprint.Fingerprint;
const FeatureID = features.FeatureID;
const Sha256 = std.crypto.hash.sha2.Sha256;

const MAX_FEATURES = @typeInfo(FeatureID).@"enum".fields.len;

/// Hashes a full fingerprint into a 32-byte digest.
/// Features are sorted by FeatureID before hashing for determinism
/// regardless of insertion order.
pub fn hashFingerprint(fp: Fingerprint, out: *[32]u8) !void {
    var ctx = Sha256.init(.{});

    // Hash metadata
    var schema_buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &schema_buf, fp.metadata.schema_version, .little);
    ctx.update(&schema_buf);

    var len_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_buf, @as(u32, @intCast(fp.metadata.sdk_version.len)), .little);
    ctx.update(&len_buf);
    ctx.update(fp.metadata.sdk_version);

    var ts_buf: [8]u8 = undefined;
    std.mem.writeInt(i64, &ts_buf, fp.metadata.collected_at, .little);
    ctx.update(&ts_buf);

    // Hash features sorted by FeatureID
    var indices: [MAX_FEATURES]usize = undefined;
    for (fp.features, 0..) |_, i| {
        indices[i] = i;
    }

    // Simple selection sort by FeatureID
    const n = fp.features.len;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        var min_idx = i;
        var j = i + 1;
        while (j < n) : (j += 1) {
            if (@intFromEnum(fp.features[indices[j]].id) < @intFromEnum(fp.features[indices[min_idx]].id)) {
                min_idx = j;
            }
        }
        const tmp = indices[i];
        indices[i] = indices[min_idx];
        indices[min_idx] = tmp;

        const feat = fp.features[indices[i]];
        // Write feature ID
        var id_buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &id_buf, @intFromEnum(feat.id), .little);
        ctx.update(&id_buf);

        // Write feature value hash
        var value_hash: [32]u8 = undefined;
        try hashing.hashFeature(feat.value, &value_hash);
        ctx.update(&value_hash);
    }

    ctx.final(out);
}
