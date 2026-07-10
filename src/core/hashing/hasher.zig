const std = @import("std");
const features = @import("../features/root.zig");
const fingerprint = @import("../fingerprint/root.zig");
const hashing = @import("root.zig");

const FeatureValue = fingerprint.FeatureValue;
const FeatureID = features.FeatureID;
const Sha256 = std.crypto.hash.sha2.Sha256;

/// An incremental hasher that absorbs features one at a time
/// and produces a final fingerprint digest.
///
/// The caller is responsible for feeding features in a deterministic order
/// (e.g., sorted by FeatureID) for reproducible digests.
pub const Hasher = struct {
    ctx: Sha256,
    feature_count: usize,

    /// Creates a new Hasher initialized with fingerprint metadata.
    pub fn init(schema_version: u16, sdk_version: []const u8, collected_at: i64) Hasher {
        var ctx = Sha256.init(.{});

        var schema_buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &schema_buf, schema_version, .little);
        ctx.update(&schema_buf);

        var len_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &len_buf, @as(u32, @intCast(sdk_version.len)), .little);
        ctx.update(&len_buf);
        ctx.update(sdk_version);

        var ts_buf: [8]u8 = undefined;
        std.mem.writeInt(i64, &ts_buf, collected_at, .little);
        ctx.update(&ts_buf);

        return Hasher{ .ctx = ctx, .feature_count = 0 };
    }

    /// Adds a single feature to the hash.
    pub fn add(self: *Hasher, id: FeatureID, value: FeatureValue) !void {
        var id_buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &id_buf, @intFromEnum(id), .little);
        self.ctx.update(&id_buf);

        var value_hash: [32]u8 = undefined;
        try hashing.hashFeature(value, &value_hash);
        self.ctx.update(&value_hash);

        self.feature_count += 1;
    }

    /// Returns the feature count added so far.
    pub fn count(self: Hasher) usize {
        return self.feature_count;
    }

    /// Finalizes the hash and writes the 32-byte digest to `out`.
    pub fn final(self: *Hasher, out: *[32]u8) void {
        self.ctx.final(out);
    }
};
