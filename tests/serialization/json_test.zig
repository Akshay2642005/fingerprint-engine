const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;
const serialization = @import("core").serialization;

// ──────────────────────────────────────────────
// JSON Serialization — Encode
// ──────────────────────────────────────────────

test "json encode empty fingerprint" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
    const fp = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{},
    };

    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try serialization.jsonEncode(&w, fp);

    const json = buf[0..w.end];
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"schema_version\""));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"features\""));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"sdk_version\""));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"0.1.0\""));
}

test "json encode with Boolean and Integer features" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 1700000000,
    };
    const fp = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{ .id = features.FeatureID.CookieEnabled, .value = fingerprint.FeatureValue{ .Boolean = true } },
            fingerprint.Feature{ .id = features.FeatureID.HardwareConcurrency, .value = fingerprint.FeatureValue{ .Integer = 8 } },
            fingerprint.Feature{ .id = features.FeatureID.UserAgent, .value = fingerprint.FeatureValue{ .String = "Mozilla/5.0" } },
        },
    };

    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try serialization.jsonEncode(&w, fp);

    const json = buf[0..w.end];
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"Cookie Enabled\": true"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"Hardware Concurrency\": 8"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "Mozilla/5.0"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "1700000000"));
}
