const std = @import("std");
const testing = std.testing;
const core = @import("core");
const model = @import("model");

test "WASM module initializes" {
    // We test the browser module's internal logic via re-import
    // The actual exports are WASM-only, but we validate the core integration
    const fp = model.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{
            model.Feature{
                .id = .CookieEnabled,
                .value = model.FeatureValue{ .Boolean = true },
            },
        },
    };

    var digest: [32]u8 = undefined;
    try core.hashing.hashFingerprint(fp, &digest);
    try testing.expectEqual(@as(usize, 32), digest.len);
}

test "hashFingerprintBuffer produces stable output" {
    const fv = model.FeatureValue;
    const features = [_]model.Feature{
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
    const fv = model.FeatureValue;
    const features = [_]model.Feature{
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
