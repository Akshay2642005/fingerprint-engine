const std = @import("std");
const testing = std.testing;
const io = @import("io");

test "writer and reader round-trip bytes and integers" {
    var buffer: [32]u8 = undefined;
    var writer = io.Writer.init(&buffer);
    try writer.writeByte(0xAB);
    try writer.writeBytes("fpg");
    try writer.writeInt(u16, 0x1234);
    try writer.writeInt(u32, 0xDEADBEEF);

    var reader = io.Reader.init(writer.written());
    try testing.expectEqual(@as(u8, 0xAB), try reader.readByte());
    var rest: [3]u8 = undefined;
    try reader.readSlice(&rest);
    try testing.expectEqualStrings("fpg", &rest);
    try testing.expectEqual(@as(u16, 0x1234), try reader.readInt(u16));
    try testing.expectEqual(@as(u32, 0xDEADBEEF), try reader.readInt(u32));
    try testing.expectEqual(@as(usize, 0), reader.remaining());
}

test "integer writes are little-endian on any host" {
    var buffer: [8]u8 = undefined;
    var writer = io.Writer.init(&buffer);
    try writer.writeInt(u32, 0x78563412);
    try writer.writeInt(u16, 0x0102);
    try testing.expectEqual(@as(u8, 0x12), buffer[0]);
    try testing.expectEqual(@as(u8, 0x34), buffer[1]);
    try testing.expectEqual(@as(u8, 0x56), buffer[2]);
    try testing.expectEqual(@as(u8, 0x78), buffer[3]);
    try testing.expectEqual(@as(u8, 0x02), buffer[4]);
    try testing.expectEqual(@as(u8, 0x01), buffer[5]);
}

test "writer reports buffer full" {
    var buffer: [2]u8 = undefined;
    var writer = io.Writer.init(&buffer);
    try writer.writeBytes("ab");
    try testing.expectError(error.BufferFull, writer.writeByte(0x00));
    try testing.expectError(error.BufferFull, writer.writeInt(u32, 1));
    try testing.expectEqual(@as(usize, 0), writer.remaining());
}

test "writer writeBytes rejects oversized writes" {
    var buffer: [4]u8 = undefined;
    var writer = io.Writer.init(&buffer);
    try testing.expectError(error.BufferFull, writer.writeBytes("too long"));
    try testing.expectEqualStrings("", writer.written());
}

test "reader reports out of bounds" {
    var reader = io.Reader.init("ab");
    try testing.expectEqual(@as(u8, 'a'), try reader.readByte());
    try testing.expectEqual(@as(u8, 'b'), try reader.readByte());
    try testing.expectError(error.OutOfBounds, reader.readByte());
    var rest: [2]u8 = undefined;
    try testing.expectError(error.OutOfBounds, reader.readSlice(&rest));
    try testing.expectError(error.OutOfBounds, reader.readInt(u32));
}

test "reader readRemaining consumes without copying" {
    var reader = io.Reader.init("hello world");
    try testing.expectEqual(@as(u8, 'h'), try reader.readByte());
    try testing.expectEqualStrings("ello world", reader.readRemaining());
    try testing.expectEqual(@as(usize, 0), reader.remaining());
}

test "remaining tracks consumed bytes" {
    var reader = io.Reader.init("abcd");
    try testing.expectEqual(@as(usize, 4), reader.remaining());
    var pair: [2]u8 = undefined;
    try reader.readSlice(&pair);
    try testing.expectEqual(@as(usize, 2), reader.remaining());
}
