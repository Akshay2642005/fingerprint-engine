const std = @import("std");
const testing = std.testing;
const engine = @import("engine");
const model = @import("model");
const serialization = @import("serialization");
const builders = @import("test_utils").builders;

const Request = engine.Request;
const Response = engine.Response;
const Status = engine.Status;

test "roundtrip: serialize then deserialize preserves every feature" {
    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const fp = try makeFingerprint(arena);
    const encoded = try runOp(.serialize, try encodeFp(arena, fp), arena);
    const decoded = try runOp(.deserialize, encoded, arena);

    // Binary v1 is canonical: decode → encode yields identical bytes.
    try testing.expectEqualSlices(u8, encoded, decoded);
}

test "roundtrip: serialize result decodes to the original feature count" {
    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const fp = try makeFingerprint(arena);
    const encoded = try runOp(.serialize, try encodeFp(arena, fp), arena);

    var fbs = std.io.fixedBufferStream(encoded);
    const decoded = try serialization.decode(fbs.reader(), arena);
    try testing.expectEqual(@as(usize, fp.features.len), decoded.fingerprint.features.len);
    for (decoded.fingerprint.features, fp.features) |got, want| {
        try testing.expectEqual(want.id, got.id);
        try testing.expectEqual(want.value.valueType(), got.value.valueType());
    }
}

fn makeFingerprint(arena: std.mem.Allocator) !model.Fingerprint {
    const feats = [_]model.Feature{
        builders.stringFeature(.UserAgent, "Mozilla/5.0"),
        builders.intFeature(.HardwareConcurrency, 8),
        builders.intFeature(.ScreenWidth, 1920),
        builders.stringFeature(.Language, "en-US"),
        builders.boolFeature(.CookieEnabled, true),
        builders.stringArrayFeature(.Languages, &.{ "en-US", "fr-FR" }),
        builders.floatFeature(.DevicePixelRatio, 2.0),
        builders.intArrayFeature(.AudioInputDevices, &.{ 1, 2 }),
    };
    return builders.makeFingerprint(try arena.dupe(model.Feature, &feats));
}

fn runOp(op: engine.Operation, payload: []const u8, arena: std.mem.Allocator) ![]const u8 {
    var response_buffer: [8192]u8 = undefined;
    const req = Request{ .operation = op, .codec = .binary, .payload = payload };
    var res = Response.init(op, &response_buffer);
    try engine.process(&req, &res, arena);
    try testing.expectEqual(Status.ok, res.status);
    return arena.dupe(u8, res.slice());
}

fn encodeFp(arena: std.mem.Allocator, fp: model.Fingerprint) ![]const u8 {
    var buffer: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try serialization.encode(fbs.writer(), fp);
    return arena.dupe(u8, fbs.getWritten());
}
