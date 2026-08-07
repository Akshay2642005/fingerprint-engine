const std = @import("std");
const testing = std.testing;
const engine = @import("engine");
const model = @import("model");
const serialization = @import("serialization");
const builders = @import("test_utils").builders;

const Request = engine.Request;
const Response = engine.Response;
const Status = engine.Status;

test "replay: deserialize then hash reproduces the original digest" {
    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const fp = try makeFingerprint(arena);
    const original = try encodeFp(arena, fp);
    const original_digest = try runOp(.hash, original, arena);

    // Replay the payload through deserialize → canonical bytes.
    const canonical = try runOp(.deserialize, original, arena);

    // Hashing the replayed bytes must equal hashing the original bytes.
    const replayed_digest = try runOp(.hash, canonical, arena);
    try testing.expectEqualSlices(u8, original_digest[0..32], replayed_digest[0..32]);
}

test "replay: repeated package processing is stable" {
    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const payload = try encodeFp(arena, try makeFingerprint(arena));

    const first = try runOp(.package, payload, arena);
    const second = try runOp(.package, payload, arena);
    try testing.expectEqualSlices(u8, first, second);
}

fn makeFingerprint(arena: std.mem.Allocator) !model.Fingerprint {
    const feats = [_]model.Feature{
        builders.stringFeature(.UserAgent, "Mozilla/5.0"),
        builders.intFeature(.HardwareConcurrency, 8),
        builders.intFeature(.ScreenWidth, 1920),
        builders.stringFeature(.Language, "en-US"),
        builders.boolFeature(.CookieEnabled, true),
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
