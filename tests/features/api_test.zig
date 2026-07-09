const std = @import("std");
const testing = std.testing;

// Public API test — imports only root.zig as consumers should
const features = @import("core").features;

// ──────────────────────────────────────────────
// Public API — Type Exports
// ──────────────────────────────────────────────

test "API exposes FeatureCategory" {
    try testing.expect(@typeInfo(features.FeatureCategory).@"enum".fields.len > 0);
}

test "API exposes FeatureType" {
    try testing.expect(@typeInfo(features.FeatureType).@"enum".fields.len > 0);
}

test "API exposes FeatureWeight" {
    try testing.expect(features.FeatureWeight == u8);
}

test "API exposes FeatureFlags" {
    const flags = features.FeatureFlags{};
    _ = flags;
}

test "API exposes FeatureID" {
    try testing.expectEqual(@as(u16, @intFromEnum(features.FeatureID.Count)), 37);
}

test "API exposes FeatureDefinition" {
    const def = features.FeatureDefinition{
        .id = features.FeatureID.UserAgent,
        .category = features.FeatureCategory.Navigator,
        .value_type = features.FeatureType.String,
        .weight = 50,
        .flags = features.FeatureFlags.none,
        .name = "test",
        .description = "test",
    };
    _ = def;
}

test "API exposes Registry" {
    _ = features.Registry;
}

// ──────────────────────────────────────────────
// Public API — Registry Functions
// ──────────────────────────────────────────────

test "API provides Registry.get function" {
    const def = features.Registry.get(features.FeatureID.UserAgent);
    try testing.expectEqual(def.id, features.FeatureID.UserAgent);
}

test "API provides Registry.all function" {
    const all = features.Registry.all();
    try testing.expect(all.len > 0);
}

test "API provides Registry.count function" {
    try testing.expect(features.Registry.count() > 0);
}

// ──────────────────────────────────────────────
// Public API — Named Flag Constants
// ──────────────────────────────────────────────

test "API exposes FeatureFlags.none" {
    try testing.expectEqual(@as(u8, 0), @as(u8, @bitCast(features.FeatureFlags.none)));
}

test "API exposes FeatureFlags.stable_required" {
    try testing.expect(features.FeatureFlags.stable_required.stable);
    try testing.expect(features.FeatureFlags.stable_required.required);
}

test "API exposes FeatureFlags.stable_entropy" {
    try testing.expect(features.FeatureFlags.stable_entropy.stable);
    try testing.expect(features.FeatureFlags.stable_entropy.high_entropy);
}

test "API exposes FeatureFlags.required_entropy" {
    try testing.expect(features.FeatureFlags.required_entropy.required);
    try testing.expect(features.FeatureFlags.required_entropy.high_entropy);
}

test "API exposes FeatureFlags.critical" {
    const c = features.FeatureFlags.critical;
    try testing.expect(c.stable);
    try testing.expect(c.required);
    try testing.expect(c.high_entropy);
}

// ──────────────────────────────────────────────
// Public API — Module Re-exports
// ──────────────────────────────────────────────

test "API — all public types accessible through features root" {
    // This test verifies the module's public surface is complete
    // by using every exported symbol
    const _category: features.FeatureCategory = .Navigator;
    const _type: features.FeatureType = .String;
    const _weight: features.FeatureWeight = 50;
    const _flags = features.FeatureFlags{ .stable = true };
    const _id: features.FeatureID = .UserAgent;
    const _def = features.FeatureDefinition{
        .id = _id,
        .category = _category,
        .value_type = _type,
        .weight = _weight,
        .flags = _flags,
        .name = "Test",
        .description = "Test",
    };

    try testing.expectEqual(_def.id, features.Registry.get(features.FeatureID.UserAgent).id);
    try testing.expect(features.Registry.count() > 0);
}
