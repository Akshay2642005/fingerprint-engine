const std = @import("std");
const testing = std.testing;
const engine = @import("engine");
const model = @import("model");
const serialization = @import("serialization");
const builders = @import("test_utils").builders;

const Operation = engine.Operation;
const Status = engine.Status;
const CodecID = engine.CodecID;
const Request = engine.Request;
const Response = engine.Response;

test "process: validate reports missing required features" {
    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const payload = try encodeFp(arena, try cleanFingerprint(arena));
    var response_buffer: [2048]u8 = undefined;
    const req = Request{ .operation = .validate, .codec = .binary, .payload = payload };
    var res = Response.init(.validate, &response_buffer);
    try engine.process(&req, &res, arena);

    try testing.expectEqual(Status.ok, res.status);
    try testing.expectEqual(Operation.validate, res.operation);
    // is_valid = 0: the registry marks ~40 features required, so a 5-feature
    // fingerprint is incomplete by design.
    try testing.expectEqual(@as(u8, 0), response_buffer[0]);
    // u16 required_count follows the is_valid byte and must be nonzero.
    const required_count = std.mem.readInt(u16, response_buffer[1..3], .little);
    try testing.expect(required_count > 0);
}

test "process: hash returns digest, feature count, and schema version" {
    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const payload = try encodeFp(arena, try cleanFingerprint(arena));
    var response_buffer: [2048]u8 = undefined;
    const req = Request{ .operation = .hash, .codec = .binary, .payload = payload };
    var res = Response.init(.hash, &response_buffer);
    try engine.process(&req, &res, arena);

    try testing.expectEqual(Status.ok, res.status);
    // 32-byte digest + u16 feature_count + u16 schema_version.
    try testing.expectEqual(@as(usize, 36), res.payload_len);
    try testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, response_buffer[34..36], .little));
}

test "process: entropy returns 8 bytes" {
    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const payload = try encodeFp(arena, try cleanFingerprint(arena));
    var response_buffer: [2048]u8 = undefined;
    const req = Request{ .operation = .entropy, .codec = .binary, .payload = payload };
    var res = Response.init(.entropy, &response_buffer);
    try engine.process(&req, &res, arena);

    try testing.expectEqual(Status.ok, res.status);
    try testing.expectEqual(@as(usize, 8), res.payload_len);
}

test "process: unknown operation maps to invalid_request" {
    const unknown: Operation = @enumFromInt(99);
    const req = Request{ .operation = unknown, .codec = .binary, .payload = "" };
    var response_buffer: [64]u8 = undefined;
    var res = Response.init(unknown, &response_buffer);
    try engine.process(&req, &res, std.testing.allocator);

    try testing.expectEqual(Status.invalid_request, res.status);
}

test "process: unknown codec maps to invalid_request" {
    const unknown_codec: CodecID = @enumFromInt(3);
    const req = Request{ .operation = .validate, .codec = unknown_codec, .payload = "" };
    var response_buffer: [64]u8 = undefined;
    var res = Response.init(.validate, &response_buffer);
    try engine.process(&req, &res, std.testing.allocator);

    try testing.expectEqual(Status.invalid_request, res.status);
}

test "process: json codec is rejected at boundary (BUG-014)" {
    const req = Request{ .operation = .validate, .codec = .json, .payload = "" };
    var response_buffer: [64]u8 = undefined;
    var res = Response.init(.validate, &response_buffer);
    try engine.process(&req, &res, std.testing.allocator);

    try testing.expectEqual(Status.invalid_request, res.status);
}

fn cleanFingerprint(arena: std.mem.Allocator) !model.Fingerprint {
    const feats = [_]model.Feature{
        builders.stringFeature(.UserAgent, "Mozilla/5.0"),
        builders.intFeature(.HardwareConcurrency, 8),
        builders.intFeature(.ScreenWidth, 1920),
        builders.stringFeature(.Language, "en-US"),
        builders.boolFeature(.CookieEnabled, true),
    };
    return builders.makeFingerprint(try arena.dupe(model.Feature, &feats));
}

fn encodeFp(arena: std.mem.Allocator, fp: model.Fingerprint) ![]const u8 {
    var buffer: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try serialization.encode(fbs.writer(), fp);
    return arena.dupe(u8, fbs.getWritten());
}
