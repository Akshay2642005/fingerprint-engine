const std = @import("std");
const features = @import("../features/root.zig");
const fingerprint = @import("../fingerprint/root.zig");

const Feature = fingerprint.Feature;
const Fingerprint = fingerprint.Fingerprint;
const FeatureID = features.FeatureID;
const Registry = features.Registry;

/// A warning produced when a required feature is missing from a fingerprint.
pub const RequiredWarning = struct {
    feature_id: FeatureID,
    name: []const u8,
    is_critical: bool,
};

/// Checks that all features with the `required` flag are present in the fingerprint.
/// Returns a list of missing required features (empty = all required features present).
pub fn checkRequired(fp: Fingerprint, allocator: std.mem.Allocator) ![]RequiredWarning {
    var missing: std.ArrayList(RequiredWarning) = .empty;
    defer missing.deinit(allocator);

    // Build a set of present FeatureIDs
    var present: std.StaticBitSet(@typeInfo(FeatureID).@"enum".fields.len) = .initEmpty();

    for (fp.features) |feat| {
        present.set(@intFromEnum(feat.id));
    }

    // Check every definition — if it's required and not present, warn
    for (Registry.all()) |def| {
        if (def.flags.required) {
            if (!present.isSet(@intFromEnum(def.id))) {
                try missing.append(allocator, RequiredWarning{
                    .feature_id = def.id,
                    .name = def.name,
                    .is_critical = def.flags.high_entropy and def.flags.stable,
                });
            }
        }
    }

    return try missing.toOwnedSlice(allocator);
}
