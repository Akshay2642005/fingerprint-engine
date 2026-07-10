const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;

// ──────────────────────────────────────────────
// Fingerprint — Top-level runtime object
// ──────────────────────────────────────────────

test "Fingerprint can be constructed with metadata and empty features" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 1_700_000_000,
    };
    const fp = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{},
    };
    try testing.expectEqual(@as(u16, 1), fp.metadata.schema_version);
    try testing.expectEqual(@as(usize, 0), fp.features.len);
}

test "Fingerprint can be constructed with multiple features" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 1_700_000_001,
    };
    const fp = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{
                .id = features.FeatureID.UserAgent,
                .value = fingerprint.FeatureValue{ .String = "Mozilla/5.0" },
            },
            fingerprint.Feature{
                .id = features.FeatureID.CookieEnabled,
                .value = fingerprint.FeatureValue{ .Boolean = true },
            },
            fingerprint.Feature{
                .id = features.FeatureID.HardwareConcurrency,
                .value = fingerprint.FeatureValue{ .Integer = 8 },
            },
        },
    };
    try testing.expectEqual(@as(usize, 3), fp.features.len);
    try testing.expectEqual(features.FeatureID.UserAgent, fp.features[0].id);
    try testing.expectEqualStrings("Mozilla/5.0", fp.features[0].value.String);
    try testing.expect(fp.features[1].value.Boolean);
    try testing.expectEqual(@as(i64, 8), fp.features[2].value.Integer);
}

test "Fingerprint metadata can be accessed after construction" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 2,
        .sdk_version = "1.0.0",
        .collected_at = 1_700_000_002,
    };
    const fp = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{},
    };
    try testing.expectEqualStrings("1.0.0", fp.metadata.sdk_version);
    try testing.expectEqual(@as(u16, 2), fp.metadata.schema_version);
    try testing.expectEqual(@as(i64, 1_700_000_002), fp.metadata.collected_at);
}

// ──────────────────────────────────────────────
// FeatureCollection type alias
// ──────────────────────────────────────────────

test "FeatureCollection is a slice of Feature" {
    const features_slice: fingerprint.FeatureCollection = &.{
        fingerprint.Feature{
            .id = features.FeatureID.SchemaVersion,
            .value = fingerprint.FeatureValue{ .Integer = 1 },
        },
    };
    try testing.expectEqual(@as(usize, 1), features_slice.len);
}
