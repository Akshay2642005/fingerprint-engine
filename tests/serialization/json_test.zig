const std = @import("std");
const testing = std.testing;
const features = @import("model");
const fingerprint = @import("model");
const serialization = @import("serialization");

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
    var fbs = std.io.fixedBufferStream(&buf);
    var w = fbs.writer();
    try serialization.jsonEncode(&w, fp);

    const json = fbs.getWritten();
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
    var fbs = std.io.fixedBufferStream(&buf);
    var w = fbs.writer();
    try serialization.jsonEncode(&w, fp);

    const json = fbs.getWritten();
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"Cookie Enabled\": true"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"Hardware Concurrency\": 8"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "Mozilla/5.0"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "1700000000"));
}

test "json encode v2 includes package id as hex" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 2,
        .sdk_version = "0.2.0",
        .collected_at = 0,
        .package_id = .{
            0xDE, 0xAD, 0xBE, 0xEF, 0, 0, 0, 0,
            0,    0,    0,    0,    0, 0, 0, 0x42,
        },
    };
    const fp = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{},
    };

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var w = fbs.writer();
    try serialization.jsonEncode(&w, fp);

    const json = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, json, "\"package_id\": \"deadbeef000000000000000000000042\"") != null);
}

test "json encode v1 omits package id" {
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
    var fbs = std.io.fixedBufferStream(&buf);
    var w = fbs.writer();
    try serialization.jsonEncode(&w, fp);

    const json = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, json, "package_id") == null);
}

// ── BUG-013: Bytes JSON encoding uses valid \\u00XX escapes ──

test "json encode Bytes uses \\u00xx escapes (valid JSON)" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
    const fp = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{
                .id = features.FeatureID.CanvasHash,
                .value = fingerprint.FeatureValue{ .Bytes = &[_]u8{ 0xDE, 0xAD, 0xFF } },
            },
        },
    };

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var w = fbs.writer();
    try serialization.jsonEncode(&w, fp);

    const json = fbs.getWritten();
    // Must contain \u00XX, NOT \xXX
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "\\u00de"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "\\u00ad"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "\\u00ff"));
    try testing.expect(!std.mem.containsAtLeast(u8, json, 1, "\\x"));
}
