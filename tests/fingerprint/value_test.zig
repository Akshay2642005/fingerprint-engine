const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;

const FeatureType = features.FeatureType;

// ──────────────────────────────────────────────
// FeatureValue — Tagged Union type tags
// ──────────────────────────────────────────────

test "FeatureValue Boolean variant has correct type tag" {
    const value = fingerprint.FeatureValue{ .Boolean = true };
    try testing.expectEqual(FeatureType.Boolean, value.valueType());
}

test "FeatureValue Integer variant has correct type tag" {
    const value = fingerprint.FeatureValue{ .Integer = 42 };
    try testing.expectEqual(FeatureType.Integer, value.valueType());
}

test "FeatureValue Float variant has correct type tag" {
    const value = fingerprint.FeatureValue{ .Float = 3.14 };
    try testing.expectEqual(FeatureType.Float, value.valueType());
}

test "FeatureValue String variant has correct type tag" {
    const value = fingerprint.FeatureValue{ .String = "hello" };
    try testing.expectEqual(FeatureType.String, value.valueType());
}

test "FeatureValue Bytes variant has correct type tag" {
    const value = fingerprint.FeatureValue{ .Bytes = &[_]u8{ 0xDE, 0xAD } };
    try testing.expectEqual(FeatureType.Bytes, value.valueType());
}

test "FeatureValue StringArray variant has correct type tag" {
    const value = fingerprint.FeatureValue{ .StringArray = &[_][]const u8{ "a", "b" } };
    try testing.expectEqual(FeatureType.StringArray, value.valueType());
}

test "FeatureValue IntegerArray variant has correct type tag" {
    const value = fingerprint.FeatureValue{ .IntegerArray = &[_]i64{ 1, 2, 3 } };
    try testing.expectEqual(FeatureType.IntegerArray, value.valueType());
}

test "FeatureValue FloatArray variant has correct type tag" {
    const value = fingerprint.FeatureValue{ .FloatArray = &[_]f64{ 1.5, 2.5 } };
    try testing.expectEqual(FeatureType.FloatArray, value.valueType());
}

test "FeatureValue BytesArray variant has correct type tag" {
    const value = fingerprint.FeatureValue{ .BytesArray = &[_][]const u8{ "abc", "def" } };
    try testing.expectEqual(FeatureType.BytesArray, value.valueType());
}

// ──────────────────────────────────────────────
// FeatureValue — Value storage and retrieval
// ──────────────────────────────────────────────

test "FeatureValue Boolean stores and retrieves correctly" {
    const value = fingerprint.FeatureValue{ .Boolean = true };
    try testing.expect(value.Boolean);
}

test "FeatureValue Integer stores and retrieves correctly" {
    const value = fingerprint.FeatureValue{ .Integer = -42 };
    try testing.expectEqual(@as(i64, -42), value.Integer);
}

test "FeatureValue Float stores and retrieves correctly" {
    const value = fingerprint.FeatureValue{ .Float = 2.71828 };
    try testing.expectApproxEqRel(@as(f64, 2.71828), value.Float, 1e-9);
}

test "FeatureValue String stores and retrieves correctly" {
    const value = fingerprint.FeatureValue{ .String = "fingerprint" };
    try testing.expectEqualStrings("fingerprint", value.String);
}

// ──────────────────────────────────────────────
// FeatureValue — Layout
// ──────────────────────────────────────────────

test "FeatureValue struct size is reasonable" {
    // Largest variant: BytesArray = []const []const u8 (24 bytes on 64-bit)
    // Tag: 1 byte (u8 discriminator from FeatureType)
    // Expected: ~32 bytes with alignment
    try testing.expect(@sizeOf(fingerprint.FeatureValue) <= 40);
}
