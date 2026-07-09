const std = @import("std");
const testing = std.testing;
const features = @import("core").features;

/// Asserts that a FeatureDefinition matches expected values.
pub fn expectFeatureDefinition(
    actual: *const features.FeatureDefinition,
    expected_id: features.FeatureID,
    expected_category: features.FeatureCategory,
    expected_value_type: features.FeatureType,
    expected_weight: features.FeatureWeight,
    expected_flags: features.FeatureFlags,
    expected_name: []const u8,
    expected_description: []const u8,
) !void {
    try testing.expectEqual(expected_id, actual.id);
    try testing.expectEqual(expected_category, actual.category);
    try testing.expectEqual(expected_value_type, actual.value_type);
    try testing.expectEqual(expected_weight, actual.weight);
    try testing.expectEqual(expected_flags, actual.flags);
    try testing.expectEqualStrings(expected_name, actual.name);
    try testing.expectEqualStrings(expected_description, actual.description);
}

/// Asserts that a FeatureDefinition matches another by value equality.
pub fn expectFeatureDefinitionEqual(
    actual: *const features.FeatureDefinition,
    expected: *const features.FeatureDefinition,
) !void {
    try expectFeatureDefinition(
        actual,
        expected.id,
        expected.category,
        expected.value_type,
        expected.weight,
        expected.flags,
        expected.name,
        expected.description,
    );
}

/// Asserts that a flag set has exactly the given stable/high_entropy/required/sensitive state.
pub fn expectFlags(
    flags: features.FeatureFlags,
    stable: bool,
    high_entropy: bool,
    required: bool,
    sensitive: bool,
) !void {
    try testing.expectEqual(stable, flags.stable);
    try testing.expectEqual(high_entropy, flags.high_entropy);
    try testing.expectEqual(required, flags.required);
    try testing.expectEqual(sensitive, flags.sensitive);
}
