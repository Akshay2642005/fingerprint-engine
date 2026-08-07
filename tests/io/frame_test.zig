const std = @import("std");
const testing = std.testing;
const io = @import("io");

const MessageType = io.frame.MessageType;
const Codec = io.frame.Codec;

test "frame header encodes to exactly 48 bytes" {
    var buffer: [io.frame.header_size]u8 = undefined;
    var writer = io.Writer.init(&buffer);
    const header = makeHeader("payload");
    try header.encode(&writer);
    try testing.expectEqual(@as(usize, io.frame.header_size), writer.written().len);
}

test "frame header round-trips through reader" {
    var buffer: [io.frame.header_size]u8 = undefined;
    var writer = io.Writer.init(&buffer);
    const header = makeHeader("payload");
    try header.encode(&writer);

    var reader = io.Reader.init(writer.written());
    const decoded = try io.frame.FrameHeader.decode(&reader);
    try testing.expectEqual(MessageType.signal_package, decoded.message_type);
    try testing.expectEqual(Codec.binary, decoded.codec);
    try testing.expectEqual(@as(u32, 7), decoded.payload_len);
    try testing.expectEqual(@as(u32, 0), decoded.reserved);
    try testing.expectEqual(header.integrity, decoded.integrity);
}

test "frame decode rejects bad magic" {
    var buffer: [io.frame.header_size]u8 = undefined;
    var writer = io.Writer.init(&buffer);
    const header = makeHeader("payload");
    try header.encode(&writer);

    var tampered: [io.frame.header_size]u8 = undefined;
    @memcpy(&tampered, writer.written());
    tampered[0] = 'X';
    var tampered_reader = io.Reader.init(&tampered);
    try testing.expectError(error.InvalidMagic, io.frame.FrameHeader.decode(&tampered_reader));
}

test "frame decode rejects unsupported version" {
    var buffer: [io.frame.header_size]u8 = undefined;
    var writer = io.Writer.init(&buffer);
    const header = makeHeader("payload");
    try header.encode(&writer);

    var tampered: [io.frame.header_size]u8 = undefined;
    @memcpy(&tampered, writer.written());
    tampered[4] = 2; // version = 2, little-endian u16
    tampered[5] = 0;
    var tampered_reader = io.Reader.init(&tampered);
    try testing.expectError(error.UnsupportedVersion, io.frame.FrameHeader.decode(&tampered_reader));
}

test "frame decode rejects unknown message type" {
    var buffer: [io.frame.header_size]u8 = undefined;
    var writer = io.Writer.init(&buffer);
    const header = makeHeader("payload");
    try header.encode(&writer);

    var tampered: [io.frame.header_size]u8 = undefined;
    @memcpy(&tampered, writer.written());
    tampered[6] = 9;
    var tampered_reader = io.Reader.init(&tampered);
    try testing.expectError(error.InvalidMessageType, io.frame.FrameHeader.decode(&tampered_reader));
}

test "frame decode rejects unknown codec" {
    var buffer: [io.frame.header_size]u8 = undefined;
    var writer = io.Writer.init(&buffer);
    const header = makeHeader("payload");
    try header.encode(&writer);

    var tampered: [io.frame.header_size]u8 = undefined;
    @memcpy(&tampered, writer.written());
    tampered[7] = 3;
    var tampered_reader = io.Reader.init(&tampered);
    try testing.expectError(error.InvalidCodec, io.frame.FrameHeader.decode(&tampered_reader));
}

test "frame encode fails when writer is too small" {
    var buffer: [io.frame.header_size - 1]u8 = undefined;
    var writer = io.Writer.init(&buffer);
    const header = makeHeader("payload");
    try testing.expectError(error.BufferFull, header.encode(&writer));
}

test "frame integrityOf matches the known sha256 of abc" {
    const expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    const digest = io.frame.FrameHeader.integrityOf("abc");
    const hex = std.fmt.bytesToHex(digest, .lower);
    try testing.expectEqualStrings(expected, &hex);
}

test "frame integrityValid accepts matching and rejects mismatched payloads" {
    const header = makeHeader("payload");
    try testing.expect(io.frame.FrameHeader.integrityValid(header, "payload"));
    try testing.expect(!io.frame.FrameHeader.integrityValid(header, "tampered"));
}

fn makeHeader(payload: []const u8) io.frame.FrameHeader {
    return .{
        .message_type = MessageType.signal_package,
        .codec = Codec.binary,
        .payload_len = @intCast(payload.len),
        .integrity = io.frame.FrameHeader.integrityOf(payload),
    };
}
