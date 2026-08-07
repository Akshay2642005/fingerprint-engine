const std = @import("std");
const testing = std.testing;
const serialization = @import("serialization");
const engine = @import("engine");

const CodecID = serialization.CodecID;

test "codec ids are stable wire tags" {
    try testing.expectEqual(@as(u8, 1), @intFromEnum(CodecID.binary));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(CodecID.json));
}

test "schema version constants match the design" {
    try testing.expectEqual(@as(u16, 1), serialization.schema_version_v1);
    try testing.expectEqual(@as(u16, 2), serialization.schema_version_v2);
}

test "engine codec ids are the same type as serialization codec ids" {
    // The engine aliases the serialization CodecID so wire tags can never
    // drift between the codec registry and the request path.
    try testing.expect(CodecID == engine.CodecID);
    try testing.expectEqual(CodecID.binary, engine.CodecID.binary);
    try testing.expectEqual(CodecID.json, engine.CodecID.json);
}
