const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;
const serialization = @import("core").serialization;

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
    var w = std.Io.Writer.fixed(&buf);
    try serialization.encode(&w, fp);

    const bytes = buf[0..w.end];
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
    var w = std.Io.Writer.fixed(&buf);
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
    var w = std.Io.Writer.fixed(&buf);
    try serialization.encode(&w, fp);

    const bytes = buf[0..w.end];
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
    var w1 = std.Io.Writer.fixed(&buf1);
    try serialization.encode(&w1, fp);

    var buf2: [128]u8 = undefined;
    var w2 = std.Io.Writer.fixed(&buf2);
    try serialization.encode(&w2, fp);

    const bytes1 = buf1[0..w1.end];
    const bytes2 = buf2[0..w2.end];
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
    var w = std.Io.Writer.fixed(&buf);
    try serialization.encode(&w, fp);

    const bytes = buf[0..w.end];
    try testing.expect(bytes.len > 8);
    try testing.expectEqual(@as(u8, 9), bytes[6]);
}

// ──────────────────────────────────────────────
// Binary Serialization — Round-trip encode/decode
// ──────────────────────────────────────────────

/// Helper: encode then decode, returns the decoded result. Caller must call deinit().
fn roundTrip(fp: fingerprint.Fingerprint, allocator: std.mem.Allocator) !serialization.DecodedFingerprint {
    var buf: [1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try serialization.encode(&w, fp);

    var r = std.Io.Reader.fixed(buf[0..w.end]);
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

    var r = std.Io.Reader.fixed(&invalid);
    try testing.expectError(error.InvalidMagic, serialization.decode(&r, allocator));
}

test "decode rejects truncated data" {
    const allocator = testing.allocator;
    const truncated = [_]u8{ 'F', 'N', 'G', 'R' };

    var r = std.Io.Reader.fixed(&truncated);
    if (serialization.decode(&r, allocator)) |_| {
        try testing.expect(false);
    } else |err| {
        // Reader's takeArray returns EndOfStream when data runs out
        try testing.expect(err == error.EndOfStream or err == error.Truncated);
    }
}
