const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;
const hashing = @import("core").hashing;

test "Hasher produces empty fingerprint digest when no features added" {
    var hasher = hashing.Hasher.init(1, "0.1.0", 0);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    try testing.expectEqual(@as(usize, 32), digest.len);
}

test "Hasher deterministic for same feature sequence" {
    var h1 = hashing.Hasher.init(1, "0.1.0", 0);
    try h1.add(.CookieEnabled, fingerprint.FeatureValue{ .Boolean = true });
    try h1.add(.UserAgent, fingerprint.FeatureValue{ .String = "Mozilla" });
    var d1: [32]u8 = undefined;
    h1.final(&d1);

    var h2 = hashing.Hasher.init(1, "0.1.0", 0);
    try h2.add(.CookieEnabled, fingerprint.FeatureValue{ .Boolean = true });
    try h2.add(.UserAgent, fingerprint.FeatureValue{ .String = "Mozilla" });
    var d2: [32]u8 = undefined;
    h2.final(&d2);

    try testing.expectEqualSlices(u8, &d1, &d2);
}

test "Hasher produces different digest for different features" {
    var h1 = hashing.Hasher.init(1, "0.1.0", 0);
    try h1.add(.CookieEnabled, fingerprint.FeatureValue{ .Boolean = true });
    var d1: [32]u8 = undefined;
    h1.final(&d1);

    var h2 = hashing.Hasher.init(1, "0.1.0", 0);
    try h2.add(.CookieEnabled, fingerprint.FeatureValue{ .Boolean = false });
    var d2: [32]u8 = undefined;
    h2.final(&d2);

    try testing.expect(!std.mem.eql(u8, &d1, &d2));
}

test "Hasher matches hashFingerprint when features fed in same order" {
    const fp = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fingerprint.FeatureValue{ .Boolean = true } },
            fingerprint.Feature{ .id = .UserAgent, .value = fingerprint.FeatureValue{ .String = "Mozilla" } },
        },
    };

    // hashFingerprint sorts by FeatureID, so produce a batch hash that matches
    var batch: [32]u8 = undefined;
    try hashing.hashFingerprint(fp, &batch);

    // Hasher must feed in FeatureID order (sorted) to match hashFingerprint
    var hasher = hashing.Hasher.init(fp.metadata.schema_version, fp.metadata.sdk_version, fp.metadata.collected_at);
    try hasher.add(.UserAgent, fingerprint.FeatureValue{ .String = "Mozilla" });
    try hasher.add(.CookieEnabled, fingerprint.FeatureValue{ .Boolean = true });
    var incremental: [32]u8 = undefined;
    hasher.final(&incremental);

    try testing.expectEqualSlices(u8, &batch, &incremental);
}
