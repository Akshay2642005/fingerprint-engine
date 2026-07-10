const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;
const normalization = @import("core").normalization;

test "validateTypes returns empty for matching types" {
    const fp = fingerprint.Fingerprint{
        .metadata = .{
            .schema_version = 1,
            .sdk_version = "0.1.0",
            .collected_at = 0,
        },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fingerprint.FeatureValue{ .Boolean = true } },
            fingerprint.Feature{ .id = .HardwareConcurrency, .value = fingerprint.FeatureValue{ .Integer = 8 } },
            fingerprint.Feature{ .id = .UserAgent, .value = fingerprint.FeatureValue{ .String = "Mozilla" } },
        },
    };

    const result = try normalization.validateTypes(fp, testing.allocator);
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 0), result.len);
}

test "validateTypes detects Boolean-String mismatch" {
    const fp = fingerprint.Fingerprint{
        .metadata = .{
            .schema_version = 1,
            .sdk_version = "0.1.0",
            .collected_at = 0,
        },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fingerprint.FeatureValue{ .String = "true" } },
        },
    };

    const result = try normalization.validateTypes(fp, testing.allocator);
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqual(features.FeatureType.Boolean, result[0].expected);
    try testing.expectEqual(features.FeatureType.String, result[0].actual);
    try testing.expectEqual(features.FeatureID.CookieEnabled, result[0].feature_id);
}

test "validateTypes detects Integer-Float mismatch" {
    const fp = fingerprint.Fingerprint{
        .metadata = .{
            .schema_version = 1,
            .sdk_version = "0.1.0",
            .collected_at = 0,
        },
        .features = &.{
            fingerprint.Feature{ .id = .DevicePixelRatio, .value = fingerprint.FeatureValue{ .Integer = 2 } },
        },
    };

    const result = try normalization.validateTypes(fp, testing.allocator);
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqual(features.FeatureType.Float, result[0].expected);
    try testing.expectEqual(features.FeatureType.Integer, result[0].actual);
}

test "validateTypes detects multiple mismatches" {
    const fp = fingerprint.Fingerprint{
        .metadata = .{
            .schema_version = 1,
            .sdk_version = "0.1.0",
            .collected_at = 0,
        },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fingerprint.FeatureValue{ .Integer = 1 } },
            fingerprint.Feature{ .id = .HardwareConcurrency, .value = fingerprint.FeatureValue{ .String = "8" } },
            fingerprint.Feature{ .id = .UserAgent, .value = fingerprint.FeatureValue{ .Boolean = false } },
        },
    };

    const result = try normalization.validateTypes(fp, testing.allocator);
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 3), result.len);
}
