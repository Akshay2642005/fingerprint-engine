// story: m6-abi-pin
// Pins the wire ABI with compile-time asserts and byte goldens so the
// ADR-012 §2 table cannot drift from the actual encoder output.

const std = @import("std");
const io = @import("io");
const model = @import("model");
const serialization = @import("serialization");

const testing = std.testing;
const frame = io.frame;
const MessageType = frame.MessageType;
const Codec = frame.Codec;

comptime {
    // envelope check
    std.debug.assert(std.mem.eql(u8, &frame.magic, "FPKG"));
    std.debug.assert(frame.current_version == 1);
    std.debug.assert(frame.header_size == 48);

    // message type check
    std.debug.assert(@intFromEnum(MessageType.signal_package) == 1);
    std.debug.assert(@intFromEnum(MessageType.validation_result) == 2);
    std.debug.assert(@intFromEnum(MessageType.normalization_result) == 3);
    std.debug.assert(@intFromEnum(MessageType.fingerprint_result) == 4);
    std.debug.assert(@intFromEnum(MessageType.risk_result) == 5);
    std.debug.assert(@intFromEnum(MessageType.similarity_result) == 6);
    std.debug.assert(@intFromEnum(MessageType.diagnostics) == 7);
    std.debug.assert(@intFromEnum(MessageType.fingerprint_computed) == 8);
    std.debug.assert(@intFromEnum(MessageType.entropy_result) == 9);

    // codec check
    std.debug.assert(@intFromEnum(Codec.binary) == 1);
    std.debug.assert(@intFromEnum(Codec.json) == 2);

    // signal_package schema check
    std.debug.assert(serialization.schema_version_v1 == 1);
    std.debug.assert(serialization.schema_version_v2 == 2);

    // tlv field width check
    std.debug.assert(@bitSizeOf(model.FeatureID) == 16);
    std.debug.assert(@bitSizeOf(model.FeatureType) == 8);
    std.debug.assert(serialization.max_feature_payload_size == 4096);

    std.debug.assert(@intFromEnum(model.FeatureType.Boolean) == 0);
    std.debug.assert(@intFromEnum(model.FeatureType.Integer) == 1);
    std.debug.assert(@intFromEnum(model.FeatureType.Float) == 2);
    std.debug.assert(@intFromEnum(model.FeatureType.String) == 3);
    std.debug.assert(@intFromEnum(model.FeatureType.Bytes) == 4);
    std.debug.assert(@intFromEnum(model.FeatureType.StringArray) == 5);
    std.debug.assert(@intFromEnum(model.FeatureType.IntegerArray) == 6);
    std.debug.assert(@intFromEnum(model.FeatureType.FloatArray) == 7);
    std.debug.assert(@intFromEnum(model.FeatureType.BytesArray) == 8);
}

/// FPKG header: magic=FPKG, version=1 (LE), message_type=signal_package(1),
/// codec=binary(1), payload_len=4, reserved=0, integrity=SHA-256[32] zeros.
const golden_fpkg_header = [48]u8{
    'F',  'P',  'K',  'G',
    0x01, 0x00, 0x01, 0x01,
    0x04, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
};

/// SignalPackage v1: FNGR | schema=1 | feature_count=1 | UserAgent(0)=String
/// "Mozilla" (type=3, len=7).
const golden_v1_body = [26]u8{
    'F', 'N', 'G', 'R',
    0x01, 0x00, // schema = 1
    0x01, 0x00, // feature_count = 1
    0x00, 0x00, // id = UserAgent (0)
    0x03, // type = String
    0x0B, 0x00, 0x00, 0x00, // payload_len = 11 (4 + 7)
    0x07, 0x00, 0x00, 0x00, // String length = 7
    'M',  'o',  'z',  'i',
    'l',  'l',  'a',
};

const v2_package_id = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };

/// SignalPackage v2: FNGR | schema=2 | sdk_len=5 | "1.0.0" | collected_at=100
/// (LE i64) | package_id (16 B) | feature_count=1 | CookieEnabled(9)=Boolean
/// true (type=0, payload 1).
const golden_v2_body = [47]u8{
    'F',  'N',  'G',  'R',
    0x02, 0x00, 0x05, 0x00,
    '1',  '.',  '0',  '.',
    '0',  0x64, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x01, 0x02,
    0x03, 0x04, 0x05, 0x06,
    0x07, 0x08, 0x09, 0x0a,
    0x0b, 0x0c, 0x0d, 0x0e,
    0x0f, 0x01, 0x00, 0x09,
    0x00, 0x00, 0x01, 0x00,
    0x00, 0x00, 0x01,
};

test "FPKG header byte layout is pinned" {
    var buf: [frame.header_size]u8 = undefined;
    var writer = io.Writer.init(&buf);

    const header = frame.FrameHeader{
        .message_type = MessageType.signal_package,
        .codec = Codec.binary,
        .payload_len = 4,
        .integrity = [_]u8{0} ** 32,
    };

    try header.encode(&writer);
    try testing.expectEqualSlices(u8, &golden_fpkg_header, writer.written());
}

test "SignalPackage v1 body byte layout is pinned" {
    const meta = model.FingerprintMetadata{
        .schema_version = serialization.schema_version_v1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };

    const fingerprint = model.Fingerprint{
        .metadata = meta,
        .features = &.{
            model.Feature{
                .id = model.FeatureID.UserAgent,
                .value = model.FeatureValue{ .String = "Mozilla" },
            },
        },
    };

    var buf: [128]u8 = undefined;
    var fixedBufferStream = std.io.fixedBufferStream(&buf);
    var writer = fixedBufferStream.writer();

    try serialization.encode(&writer, fingerprint);
    try testing.expectEqualSlices(u8, &golden_v1_body, fixedBufferStream.getWritten());
}

test "SignalPackage v2 body byte layout is pinned" {
    const meta = model.FingerprintMetadata{
        .schema_version = serialization.schema_version_v2,
        .sdk_version = "1.0.0",
        .collected_at = 100,
        .package_id = v2_package_id,
    };
    const fp = model.Fingerprint{
        .metadata = meta,
        .features = &.{
            model.Feature{
                .id = model.FeatureID.CookieEnabled,
                .value = model.FeatureValue{ .Boolean = true },
            },
        },
    };

    var buf: [128]u8 = undefined;
    var fixedBufferStream = std.io.fixedBufferStream(&buf);
    var writer = fixedBufferStream.writer();
    try serialization.encode(&writer, fp);
    try testing.expectEqualSlices(u8, &golden_v2_body, fixedBufferStream.getWritten());
}

test "SignalPackage v2 body decodes pinned identity fields" {
    var fbs = std.io.fixedBufferStream(&golden_v2_body);
    var r = fbs.reader();
    const decoded = try serialization.decode(&r, std.testing.allocator);
    defer decoded.deinit();

    const fingerprint = decoded.fingerprint;
    try testing.expectEqual(@as(u16, serialization.schema_version_v2), fingerprint.metadata.schema_version);
    try testing.expectEqualStrings("1.0.0", fingerprint.metadata.sdk_version);
    try testing.expectEqual(@as(i64, 100), fingerprint.metadata.collected_at);
    try testing.expectEqualSlices(u8, &v2_package_id, &fingerprint.metadata.package_id);
    try testing.expectEqual(@as(usize, 1), fingerprint.features.len);
    try testing.expectEqual(model.FeatureID.CookieEnabled, fingerprint.features[0].id);
    try testing.expectEqual(model.FeatureValue{ .Boolean = true }, fingerprint.features[0].value);
}
