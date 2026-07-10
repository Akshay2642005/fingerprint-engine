const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;
const entropy = @import("core").entropy;

test "shannonEntropy of empty slice is 0" {
    const h = entropy.shannonEntropy(&[_]u8{});
    try testing.expectEqual(@as(f64, 0.0), h);
}

test "shannonEntropy of single repeated byte is 0" {
    const h = entropy.shannonEntropy(&[_]u8{0x00} ** 16);
    try testing.expectEqual(@as(f64, 0.0), h);
}

test "shannonEntropy of all 256 bytes is 8.0" {
    var buf: [256]u8 = undefined;
    for (&buf, 0..) |*b, i| {
        b.* = @intCast(i);
    }
    const h = entropy.shannonEntropy(&buf);
    try testing.expectEqual(@as(f64, 8.0), @round(h * 100.0) / 100.0);
}

test "shannonEntropy of varied bytes is between 0 and 8" {
    const h = entropy.shannonEntropy("hello world");
    try testing.expect(h > 0.0 and h < 8.0);
}

test "featureEntropy of Boolean true" {
    const fv = fingerprint.FeatureValue{ .Boolean = true };
    const h = entropy.featureEntropy(fv);
    try testing.expect(h >= 0.0 and h <= 8.0);
}

test "featureEntropy of Integer 42" {
    const fv = fingerprint.FeatureValue{ .Integer = 42 };
    const h = entropy.featureEntropy(fv);
    try testing.expect(h >= 0.0 and h <= 8.0);
}

test "featureEntropy of String" {
    const fv = fingerprint.FeatureValue{ .String = "Mozilla/5.0 (Windows NT 10.0)" };
    const h = entropy.featureEntropy(fv);
    try testing.expect(h > 0.0 and h <= 8.0);
}

test "fingerprintEntropy returns value between 0 and 8" {
    const fv = fingerprint.FeatureValue;
    const fp = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fv{ .Boolean = true } },
            fingerprint.Feature{ .id = .UserAgent, .value = fv{ .String = "Mozilla/5.0" } },
            fingerprint.Feature{ .id = .ScreenWidth, .value = fv{ .Integer = 1920 } },
        },
    };
    const h = entropy.fingerprintEntropy(fp);
    try testing.expect(h >= 0.0 and h <= 8.0);
}

test "fingerprintEntropy of empty fingerprint" {
    const fp = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{},
    };
    const h = entropy.fingerprintEntropy(fp);
    try testing.expectEqual(@as(f64, 0.0), h);
}
