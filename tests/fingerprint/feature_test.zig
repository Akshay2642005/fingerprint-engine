const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;

// ──────────────────────────────────────────────
// Feature — Construction and field access
// ──────────────────────────────────────────────

test "Feature can be constructed with String value" {
    const feat = fingerprint.Feature{
        .id = features.FeatureID.UserAgent,
        .value = fingerprint.FeatureValue{ .String = "Mozilla/5.0" },
    };
    try testing.expectEqual(features.FeatureID.UserAgent, feat.id);
    try testing.expectEqualStrings("Mozilla/5.0", feat.value.String);
}

test "Feature can be constructed with Integer value" {
    const feat = fingerprint.Feature{
        .id = features.FeatureID.HardwareConcurrency,
        .value = fingerprint.FeatureValue{ .Integer = 8 },
    };
    try testing.expectEqual(features.FeatureID.HardwareConcurrency, feat.id);
    try testing.expectEqual(@as(i64, 8), feat.value.Integer);
}

test "Feature can be constructed with Boolean value" {
    const feat = fingerprint.Feature{
        .id = features.FeatureID.CookieEnabled,
        .value = fingerprint.FeatureValue{ .Boolean = true },
    };
    try testing.expect(feat.value.Boolean);
}

test "Feature struct size is reasonable" {
    // FeatureID (u16) + FeatureValue (~32 bytes with tag + alignment)
    try testing.expect(@sizeOf(fingerprint.Feature) <= 48);
}
