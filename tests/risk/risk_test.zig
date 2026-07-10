const std = @import("std");
const testing = std.testing;
const fingerprint = @import("core").fingerprint;
const features = @import("core").features;
const risk = @import("core").risk;

const FV = fingerprint.FeatureValue;

test "low risk fingerprint scores below 0.5" {
    // Build a fingerprint with many features, all valid, high entropy
    const Registry = features.Registry;
    var buf: [256]fingerprint.Feature = undefined;
    var count: usize = 0;

    for (Registry.all()) |def| {
        if (count >= buf.len) break;
        const val = switch (def.value_type) {
            .Boolean => FV{ .Boolean = true },
            .Integer => FV{ .Integer = @as(i64, @intCast(count * 10)) + 50 },
            .Float => FV{ .Float = @as(f64, @floatFromInt(count)) + 0.5 },
            .String => FV{ .String = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" },
            .Bytes => FV{ .Bytes = &[_]u8{0x01} ** 8 },
            .StringArray => FV{ .StringArray = &[_][]const u8{ "en-US", "zh-CN" } },
            .IntegerArray => FV{ .IntegerArray = &[_]i64{ 1, 2, 3 } },
            .FloatArray => FV{ .FloatArray = &[_]f64{ 1.0, 2.0, 3.0 } },
            .BytesArray => FV{ .BytesArray = &[_][]const u8{&[_]u8{0x01} ** 4} },
        };
        buf[count] = fingerprint.Feature{ .id = def.id, .value = val };
        count += 1;
    }

    const fp = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = buf[0..count],
    };

    const result = try risk.computeRisk(fp, testing.allocator);
    defer testing.allocator.free(result.flags);
    try testing.expect(result.score >= 0.0);
    try testing.expect(result.score < 0.5);
    try testing.expectEqualStrings("low", result.label);
}

test "empty fingerprint scores high risk" {
    const fp = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{},
    };

    const result = try risk.computeRisk(fp, testing.allocator);
    defer testing.allocator.free(result.flags);
    try testing.expect(result.score > 0.5);
    try testing.expect(result.flags.len > 0);
}

test "few features with low entropy scores medium risk" {
    const fp = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = FV{ .Boolean = true } },
            fingerprint.Feature{ .id = .UserAgent, .value = FV{ .String = "aaaa" } },
        },
    };

    const result = try risk.computeRisk(fp, testing.allocator);
    defer testing.allocator.free(result.flags);
    try testing.expect(result.score > 0.0);
    try testing.expect(result.score < 1.0);
}
