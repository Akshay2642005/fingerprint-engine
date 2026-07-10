const std = @import("std");
const features = @import("../features/root.zig");
const fingerprint = @import("../fingerprint/root.zig");

const Feature = fingerprint.Feature;
const FeatureID = features.FeatureID;
const FeatureType = features.FeatureType;
const Fingerprint = fingerprint.Fingerprint;
const Registry = features.Registry;

/// A warning produced when a feature's value type does not match its definition.
pub const TypeWarning = struct {
    feature_id: FeatureID,
    expected: FeatureType,
    actual: FeatureType,
    name: []const u8,
};

/// Validates that every feature in a fingerprint has the correct value type
/// according to its FeatureDefinition. Returns a list of mismatches (empty if all match).
/// The caller owns the returned slice (allocated with `allocator`).
pub fn validateTypes(fp: Fingerprint, allocator: std.mem.Allocator) ![]TypeWarning {
    // Count mismatches first so we can allocate exactly
    var mismatch_count: usize = 0;
    for (fp.features) |feat| {
        const def = Registry.get(feat.id);
        const actual_type = feat.value.valueType();
        if (actual_type != def.value_type) {
            mismatch_count += 1;
        }
    }

    if (mismatch_count == 0) return &[_]TypeWarning{};

    const result = try allocator.alloc(TypeWarning, mismatch_count);
    var idx: usize = 0;
    for (fp.features) |feat| {
        const def = Registry.get(feat.id);
        const actual_type = feat.value.valueType();
        if (actual_type != def.value_type) {
            result[idx] = TypeWarning{
                .feature_id = feat.id,
                .expected = def.value_type,
                .actual = actual_type,
                .name = def.name,
            };
            idx += 1;
        }
    }

    return result;
}
