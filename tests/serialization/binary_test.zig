const std = @import("std");
const testing = std.testing;
const features = @import("model");
const fingerprint = @import("model");
const serialization = @import("serialization");

// ──────────────────────────────────────────────
// Binary Serialization — Encode header
// ──────────────────────────────────────────────

test "encode empty fingerprint produces correct magic header" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
    const fp = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{},
    };

    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var w = fbs.writer();
    try serialization.encode(&w, fp);

    const bytes = fbs.getWritten();
    try testing.expectEqual(@as(u8, 'F'), bytes[0]);
    try testing.expectEqual(@as(u8, 'N'), bytes[1]);
    try testing.expectEqual(@as(u8, 'G'), bytes[2]);
    try testing.expectEqual(@as(u8, 'R'), bytes[3]);
    try testing.expectEqual(@as(u8, 1), bytes[4]);
    try testing.expectEqual(@as(u8, 0), bytes[5]);
    try testing.expectEqual(@as(u8, 0), bytes[6]);
    try testing.expectEqual(@as(u8, 0), bytes[7]);
    try testing.expectEqual(@as(usize, 8), bytes.len);
}

test "encode with schema version 42 writes correct version bytes" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 42,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
    const fp = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{},
    };

    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var w = fbs.writer();
    try serialization.encode(&w, fp);

    try testing.expectEqual(@as(u8, 42), buf[4]);
    try testing.expectEqual(@as(u8, 0), buf[5]);
}

// ──────────────────────────────────────────────
// Binary Serialization — Encode features
// ──────────────────────────────────────────────

test "encode fingerprint with Boolean and String features" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
    const fp = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{
                .id = features.FeatureID.CookieEnabled,
                .value = fingerprint.FeatureValue{ .Boolean = true },
            },
            fingerprint.Feature{
                .id = features.FeatureID.UserAgent,
                .value = fingerprint.FeatureValue{ .String = "Mozilla" },
            },
        },
    };

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var w = fbs.writer();
    try serialization.encode(&w, fp);

    const bytes = fbs.getWritten();
    try testing.expectEqual(@as(u8, 9), bytes[8]);
    try testing.expectEqual(@as(u8, 0), bytes[9]);
    try testing.expectEqual(@as(u8, 0), bytes[10]);
    try testing.expectEqual(@as(u8, 1), bytes[11]);
    try testing.expectEqual(@as(u8, 0), bytes[12]);
    try testing.expectEqual(@as(u8, 0), bytes[13]);
    try testing.expectEqual(@as(u8, 0), bytes[14]);
    try testing.expectEqual(@as(u8, 1), bytes[15]);
    try testing.expectEqual(@as(u8, 2), bytes[6]);
}

// ──────────────────────────────────────────────
// Binary Serialization — Determinism
// ──────────────────────────────────────────────

test "encode produces identical output for same input" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
    const fp = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{
                .id = features.FeatureID.CookieEnabled,
                .value = fingerprint.FeatureValue{ .Boolean = true },
            },
        },
    };

    var buf1: [128]u8 = undefined;
    var fbs1 = std.io.fixedBufferStream(&buf1);
    var w1 = fbs1.writer();
    try serialization.encode(&w1, fp);

    var buf2: [128]u8 = undefined;
    var fbs2 = std.io.fixedBufferStream(&buf2);
    var w2 = fbs2.writer();
    try serialization.encode(&w2, fp);

    const bytes1 = fbs1.getWritten();
    const bytes2 = fbs2.getWritten();
    try testing.expectEqual(bytes1.len, bytes2.len);
    try testing.expectEqualSlices(u8, bytes1, bytes2);
}

test "encode all 9 FeatureType variants" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
    const fp = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{ .id = features.FeatureID.CookieEnabled, .value = fingerprint.FeatureValue{ .Boolean = false } },
            fingerprint.Feature{ .id = features.FeatureID.HardwareConcurrency, .value = fingerprint.FeatureValue{ .Integer = 4 } },
            fingerprint.Feature{ .id = features.FeatureID.DevicePixelRatio, .value = fingerprint.FeatureValue{ .Float = 2.0 } },
            fingerprint.Feature{ .id = features.FeatureID.UserAgent, .value = fingerprint.FeatureValue{ .String = "UA" } },
            fingerprint.Feature{ .id = features.FeatureID.CanvasHash, .value = fingerprint.FeatureValue{ .Bytes = &[_]u8{ 0x01, 0x02 } } },
            fingerprint.Feature{ .id = features.FeatureID.Languages, .value = fingerprint.FeatureValue{ .StringArray = &[_][]const u8{ "en", "fr" } } },
            fingerprint.Feature{ .id = features.FeatureID.AudioInputDevices, .value = fingerprint.FeatureValue{ .IntegerArray = &[_]i64{ 1, 2, 3 } } },
            fingerprint.Feature{ .id = features.FeatureID.AudioOutputDevices, .value = fingerprint.FeatureValue{ .FloatArray = &[_]f64{ 0.5, 1.5 } } },
            fingerprint.Feature{ .id = features.FeatureID.FontsHash, .value = fingerprint.FeatureValue{ .BytesArray = &[_][]const u8{ "abc", "def" } } },
        },
    };

    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var w = fbs.writer();
    try serialization.encode(&w, fp);

    const bytes = fbs.getWritten();
    try testing.expect(bytes.len > 8);
    try testing.expectEqual(@as(u8, 9), bytes[6]);
}

// ──────────────────────────────────────────────
// Binary Serialization — Round-trip encode/decode
// ──────────────────────────────────────────────

/// Helper: encode then decode, returns the decoded result. Caller must call deinit().
fn roundTrip(fp: fingerprint.Fingerprint, allocator: std.mem.Allocator) !serialization.DecodedFingerprint {
    var buf: [1024]u8 = undefined;
    var efbs = std.io.fixedBufferStream(&buf);
    var w = efbs.writer();
    try serialization.encode(&w, fp);

    var dfbs = std.io.fixedBufferStream(efbs.getWritten());
    var r = dfbs.reader();
    return try serialization.decode(&r, allocator);
}

test "round-trip empty fingerprint" {
    const allocator = testing.allocator;
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
    const original = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{},
    };

    var decoded = try roundTrip(original, allocator);
    defer decoded.deinit();
    const fp = decoded.fingerprint;

    try testing.expectEqual(@as(u16, 1), fp.metadata.schema_version);
    try testing.expectEqual(@as(usize, 0), fp.features.len);
}

test "round-trip with Boolean and Integer features" {
    const allocator = testing.allocator;
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
    const original = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{ .id = features.FeatureID.CookieEnabled, .value = fingerprint.FeatureValue{ .Boolean = true } },
            fingerprint.Feature{ .id = features.FeatureID.HardwareConcurrency, .value = fingerprint.FeatureValue{ .Integer = -42 } },
        },
    };

    var decoded = try roundTrip(original, allocator);
    defer decoded.deinit();
    const fp = decoded.fingerprint;

    try testing.expectEqual(@as(usize, 2), fp.features.len);
    try testing.expectEqual(features.FeatureID.CookieEnabled, fp.features[0].id);
    try testing.expect(fp.features[0].value.Boolean);
    try testing.expectEqual(features.FeatureID.HardwareConcurrency, fp.features[1].id);
    try testing.expectEqual(@as(i64, -42), fp.features[1].value.Integer);
}

test "round-trip with String feature" {
    const allocator = testing.allocator;
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
    const original = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{ .id = features.FeatureID.UserAgent, .value = fingerprint.FeatureValue{ .String = "Mozilla/5.0" } },
        },
    };

    var decoded = try roundTrip(original, allocator);
    defer decoded.deinit();
    const fp = decoded.fingerprint;

    try testing.expectEqualStrings("Mozilla/5.0", fp.features[0].value.String);
}

test "round-trip with Bytes feature" {
    const allocator = testing.allocator;
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
    const original = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{ .id = features.FeatureID.CanvasHash, .value = fingerprint.FeatureValue{ .Bytes = &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF } } },
        },
    };

    var decoded = try roundTrip(original, allocator);
    defer decoded.deinit();
    const fp = decoded.fingerprint;

    try testing.expectEqualSlices(u8, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF }, fp.features[0].value.Bytes);
}

test "round-trip with StringArray feature" {
    const allocator = testing.allocator;
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
    const original = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{ .id = features.FeatureID.Languages, .value = fingerprint.FeatureValue{ .StringArray = &[_][]const u8{ "en-US", "fr-FR" } } },
        },
    };

    var decoded = try roundTrip(original, allocator);
    defer decoded.deinit();
    const fp = decoded.fingerprint;

    try testing.expectEqual(@as(usize, 2), fp.features[0].value.StringArray.len);
    try testing.expectEqualStrings("en-US", fp.features[0].value.StringArray[0]);
    try testing.expectEqualStrings("fr-FR", fp.features[0].value.StringArray[1]);
}

test "round-trip with all 9 value types" {
    const allocator = testing.allocator;
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
    const original = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{ .id = features.FeatureID.CookieEnabled, .value = fingerprint.FeatureValue{ .Boolean = true } },
            fingerprint.Feature{ .id = features.FeatureID.HardwareConcurrency, .value = fingerprint.FeatureValue{ .Integer = 8 } },
            fingerprint.Feature{ .id = features.FeatureID.DevicePixelRatio, .value = fingerprint.FeatureValue{ .Float = 2.0 } },
            fingerprint.Feature{ .id = features.FeatureID.UserAgent, .value = fingerprint.FeatureValue{ .String = "Test" } },
            fingerprint.Feature{ .id = features.FeatureID.CanvasHash, .value = fingerprint.FeatureValue{ .Bytes = &[_]u8{0x01} } },
            fingerprint.Feature{ .id = features.FeatureID.Languages, .value = fingerprint.FeatureValue{ .StringArray = &[_][]const u8{"a"} } },
            fingerprint.Feature{ .id = features.FeatureID.AudioInputDevices, .value = fingerprint.FeatureValue{ .IntegerArray = &[_]i64{1} } },
            fingerprint.Feature{ .id = features.FeatureID.AudioOutputDevices, .value = fingerprint.FeatureValue{ .FloatArray = &[_]f64{0.5} } },
            fingerprint.Feature{ .id = features.FeatureID.FontsHash, .value = fingerprint.FeatureValue{ .BytesArray = &[_][]const u8{"x"} } },
        },
    };

    var decoded = try roundTrip(original, allocator);
    defer decoded.deinit();
    const fp = decoded.fingerprint;

    try testing.expectEqual(@as(usize, 9), fp.features.len);
    try testing.expect(fp.features[0].value.Boolean);
    try testing.expectEqual(@as(i64, 8), fp.features[1].value.Integer);
    try testing.expectEqual(@as(f64, 2.0), fp.features[2].value.Float);
    try testing.expectEqualStrings("Test", fp.features[3].value.String);
    try testing.expectEqualSlices(u8, &[_]u8{0x01}, fp.features[4].value.Bytes);
    try testing.expectEqualStrings("a", fp.features[5].value.StringArray[0]);
    try testing.expectEqual(@as(i64, 1), fp.features[6].value.IntegerArray[0]);
    try testing.expectEqual(@as(f64, 0.5), fp.features[7].value.FloatArray[0]);
    try testing.expectEqualStrings("x", fp.features[8].value.BytesArray[0]);
}

// ──────────────────────────────────────────────
// Binary Serialization — Error handling
// ──────────────────────────────────────────────

test "decode rejects invalid magic bytes" {
    const allocator = testing.allocator;
    const invalid = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };

    var fbs = std.io.fixedBufferStream(&invalid);
    var r = fbs.reader();
    try testing.expectError(error.InvalidMagic, serialization.decode(&r, allocator));
}

test "decode rejects truncated data" {
    const allocator = testing.allocator;
    const truncated = [_]u8{ 'F', 'N', 'G', 'R' };

    var fbs = std.io.fixedBufferStream(&truncated);
    var r = fbs.reader();
    if (serialization.decode(&r, allocator)) |_| {
        try testing.expect(false);
    } else |err| {
        // decode maps exhausted input to error.Truncated
        try testing.expect(err == error.EndOfStream or err == error.Truncated);
    }
}

// ──────────────────────────────────────────────
// Binary Serialization — v2 body (design §5.1)
// ──────────────────────────────────────────────

const test_package_id = [16]u8{
    0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
};

test "v2: encode writes sdk metadata, collection time, and package id" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 2,
        .sdk_version = "0.2.0",
        .collected_at = 1700000000123,
        .package_id = test_package_id,
    };
    const fp = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{},
    };

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var w = fbs.writer();
    try serialization.encode(&w, fp);

    const bytes = fbs.getWritten();
    // magic (4) | version u16 | sdk_len u16 | sdk (5) | collected i64 |
    // package_id (16) | feature_count u16
    try testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, bytes[4..6], .little));
    try testing.expectEqual(@as(u16, 5), std.mem.readInt(u16, bytes[6..8], .little));
    try testing.expectEqualStrings("0.2.0", bytes[8..13]);
    try testing.expectEqual(@as(i64, 1700000000123), std.mem.readInt(i64, bytes[13..21], .little));
    try testing.expectEqualSlices(u8, &test_package_id, bytes[21..37]);
    try testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, bytes[37..39], .little));
    try testing.expectEqual(@as(usize, 39), bytes.len);
}

test "v2: round-trip preserves metadata and features" {
    const allocator = testing.allocator;
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 2,
        .sdk_version = "0.2.0",
        .collected_at = 1700000000123,
        .package_id = test_package_id,
    };
    const original = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{ .id = features.FeatureID.CookieEnabled, .value = fingerprint.FeatureValue{ .Boolean = true } },
            fingerprint.Feature{ .id = features.FeatureID.UserAgent, .value = fingerprint.FeatureValue{ .String = "Mozilla/5.0" } },
        },
    };

    var decoded = try roundTrip(original, allocator);
    defer decoded.deinit();
    const fp = decoded.fingerprint;

    try testing.expectEqual(@as(u16, 2), fp.metadata.schema_version);
    try testing.expectEqualStrings("0.2.0", fp.metadata.sdk_version);
    try testing.expectEqual(@as(i64, 1700000000123), fp.metadata.collected_at);
    try testing.expectEqualSlices(u8, &test_package_id, &fp.metadata.package_id);
    try testing.expectEqual(@as(usize, 2), fp.features.len);
    try testing.expect(fp.features[0].value.Boolean);
    try testing.expectEqualStrings("Mozilla/5.0", fp.features[1].value.String);
}

test "v2: empty sdk version round-trips" {
    const allocator = testing.allocator;
    const original = fingerprint.Fingerprint{
        .metadata = .{
            .schema_version = 2,
            .sdk_version = "",
            .collected_at = 0,
            .package_id = test_package_id,
        },
        .features = &.{},
    };

    var decoded = try roundTrip(original, allocator);
    defer decoded.deinit();
    try testing.expectEqual(@as(usize, 0), decoded.fingerprint.metadata.sdk_version.len);
    try testing.expectEqualSlices(u8, &test_package_id, &decoded.fingerprint.metadata.package_id);
}

test "v2: truncated metadata maps to Truncated" {
    const allocator = testing.allocator;
    // v2 header claims 5 sdk bytes but the body is cut off mid-metadata.
    const partial = [_]u8{ 'F', 'N', 'G', 'R', 2, 0, 5, 0, '0', '.', '2', '.', '0' };

    var fbs = std.io.fixedBufferStream(&partial);
    var r = fbs.reader();
    try testing.expectError(error.Truncated, serialization.decode(&r, allocator));
}

test "decode rejects unsupported schema version" {
    const allocator = testing.allocator;
    const unsupported = [_]u8{ 'F', 'N', 'G', 'R', 3, 0, 0, 0 };

    var fbs = std.io.fixedBufferStream(&unsupported);
    var r = fbs.reader();
    try testing.expectError(error.UnsupportedVersion, serialization.decode(&r, allocator));
}
