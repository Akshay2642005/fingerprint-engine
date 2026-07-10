const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;
const hashing = @import("core").hashing;

test "hashFingerprint produces 32-byte digest for empty fingerprint" {
    const fp = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{},
    };
    var digest: [32]u8 = undefined;
    try hashing.hashFingerprint(fp, &digest);
    try testing.expectEqual(@as(usize, 32), digest.len);
}

test "hashFingerprint deterministic for same fingerprint" {
    const fp = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fingerprint.FeatureValue{ .Boolean = true } },
            fingerprint.Feature{ .id = .UserAgent, .value = fingerprint.FeatureValue{ .String = "Mozilla" } },
        },
    };
    var d1: [32]u8 = undefined;
    var d2: [32]u8 = undefined;
    try hashing.hashFingerprint(fp, &d1);
    try hashing.hashFingerprint(fp, &d2);
    try testing.expectEqualSlices(u8, &d1, &d2);
}

test "hashFingerprint ignores feature insertion order" {
    const meta = fingerprint.FingerprintMetadata{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 };

    // Same features, different order
    const fp1 = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{ .id = .UserAgent, .value = fingerprint.FeatureValue{ .String = "UA" } },
            fingerprint.Feature{ .id = .CookieEnabled, .value = fingerprint.FeatureValue{ .Boolean = true } },
        },
    };
    const fp2 = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fingerprint.FeatureValue{ .Boolean = true } },
            fingerprint.Feature{ .id = .UserAgent, .value = fingerprint.FeatureValue{ .String = "UA" } },
        },
    };

    var d1: [32]u8 = undefined;
    var d2: [32]u8 = undefined;
    try hashing.hashFingerprint(fp1, &d1);
    try hashing.hashFingerprint(fp2, &d2);
    try testing.expectEqualSlices(u8, &d1, &d2);
}

test "hashFingerprint different features produce different digests" {
    const meta = fingerprint.FingerprintMetadata{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 };

    const fp1 = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fingerprint.FeatureValue{ .Boolean = true } },
        },
    };
    const fp2 = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fingerprint.FeatureValue{ .Boolean = false } },
        },
    };

    var d1: [32]u8 = undefined;
    var d2: [32]u8 = undefined;
    try hashing.hashFingerprint(fp1, &d1);
    try hashing.hashFingerprint(fp2, &d2);
    try testing.expect(!std.mem.eql(u8, &d1, &d2));
}
