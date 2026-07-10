const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;
const similarity = @import("core").similarity;

test "identical fingerprints score 1.0" {
    const fv = fingerprint.FeatureValue;
    const fp1 = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fv{ .Boolean = true } },
            fingerprint.Feature{ .id = .UserAgent, .value = fv{ .String = "Mozilla" } },
        },
    };
    const fp2 = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fv{ .Boolean = true } },
            fingerprint.Feature{ .id = .UserAgent, .value = fv{ .String = "Mozilla" } },
        },
    };

    const score = similarity.fingerprintScore(fp1, fp2);
    try testing.expectEqual(@as(f64, 1.0), score);
}

test "completely different fingerprints score 0" {
    const fv = fingerprint.FeatureValue;
    const fp1 = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fv{ .Boolean = true } },
        },
    };
    const fp2 = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fv{ .Boolean = false } },
        },
    };

    const score = similarity.fingerprintScore(fp1, fp2);
    try testing.expectEqual(@as(f64, 0.0), score);
}

test "partially matching fingerprints score between 0 and 1" {
    const fv = fingerprint.FeatureValue;
    const fp1 = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fv{ .Boolean = true } },
            fingerprint.Feature{ .id = .UserAgent, .value = fv{ .String = "Mozilla" } },
        },
    };
    const fp2 = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fv{ .Boolean = true } },
            fingerprint.Feature{ .id = .UserAgent, .value = fv{ .String = "Chrome" } },
        },
    };

    const score = similarity.fingerprintScore(fp1, fp2);
    try testing.expect(score > 0.0 and score < 1.0);
}

test "fingerprints with no overlapping features score 0" {
    const fv = fingerprint.FeatureValue;
    const fp1 = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fv{ .Boolean = true } },
        },
    };
    const fp2 = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{
            fingerprint.Feature{ .id = .HardwareConcurrency, .value = fv{ .Integer = 8 } },
        },
    };

    const score = similarity.fingerprintScore(fp1, fp2);
    try testing.expectEqual(@as(f64, 0.0), score);
}
