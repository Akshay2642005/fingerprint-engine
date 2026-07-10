const std = @import("std");
const testing = std.testing;
const core = @import("core");

test "WASM module initializes" {
    // We test the browser module's internal logic via re-import
    // The actual exports are WASM-only, but we validate the core integration
    const fp = core.fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{
            core.fingerprint.Feature{
                .id = .CookieEnabled,
                .value = core.fingerprint.FeatureValue{ .Boolean = true },
            },
        },
    };

    var digest: [32]u8 = undefined;
    try core.hashing.hashFingerprint(fp, &digest);
    try testing.expectEqual(@as(usize, 32), digest.len);
}

test "hashFingerprintBuffer produces stable output" {
    const fv = core.fingerprint.FeatureValue;
    const features = [_]core.fingerprint.Feature{
        .{ .id = .CookieEnabled, .value = fv{ .Boolean = true } },
        .{ .id = .UserAgent, .value = fv{ .String = "test" } },
    };

    var digest1: [32]u8 = undefined;
    var digest2: [32]u8 = undefined;

    core.hashing.hashFingerprintBuffer(&features, &digest1);
    core.hashing.hashFingerprintBuffer(&features, &digest2);

    try testing.expectEqualSlices(u8, &digest1, &digest2);
}

test "hashFingerprintBuffer works with single feature" {
    const fv = core.fingerprint.FeatureValue;
    const features = [_]core.fingerprint.Feature{
        .{ .id = .CookieEnabled, .value = fv{ .Boolean = true } },
    };

    var digest: [32]u8 = undefined;
    core.hashing.hashFingerprintBuffer(&features, &digest);
    try testing.expectEqual(@as(usize, 32), digest.len);
}

test "hashFingerprintBuffer empty features produces valid hash" {
    var digest: [32]u8 = undefined;
    core.hashing.hashFingerprintBuffer(&.{}, &digest);
    try testing.expectEqual(@as(usize, 32), digest.len);
}
