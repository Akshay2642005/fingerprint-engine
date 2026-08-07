const std = @import("std");
const testing = std.testing;
const engine = @import("engine");
const model = @import("model");
const serialization = @import("serialization");
const builders = @import("test_utils").builders;

const Request = engine.Request;
const Response = engine.Response;
const Status = engine.Status;

test "determinism: identical input yields identical hash across runs" {
    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const fp = try makeFingerprint(arena);
    const payload = try encodeFp(arena, fp);

    const digest1 = try hashDigest(payload, arena);
    const digest2 = try hashDigest(payload, arena);
    try testing.expectEqualSlices(u8, digest1, digest2);
}

test "determinism: feature order does not affect the digest" {
    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const a = try makeFingerprint(arena);
    // Same set, different order: swap the first two arena-owned features.
    const feats: []model.Feature = @constCast(a.features);
    const tmp = feats[0];
    feats[0] = feats[1];
    feats[1] = tmp;

    const digest_a = try hashDigest(try encodeFp(arena, a), arena);
    const digest_b = try hashDigest(try encodeFp(arena, try makeFingerprint(arena)), arena);
    try testing.expectEqualSlices(u8, digest_a, digest_b);
}

test "determinism: entropy and risk scores are stable across runs" {
    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const payload = try encodeFp(arena, try makeFingerprint(arena));

    const entropy1 = try processBytes(.entropy, payload, arena);
    const entropy2 = try processBytes(.entropy, payload, arena);
    try testing.expectEqualSlices(u8, entropy1, entropy2);

    const risk1 = try processBytes(.risk, payload, arena);
    const risk2 = try processBytes(.risk, payload, arena);
    try testing.expectEqualSlices(u8, risk1, risk2);
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

fn hashDigest(payload: []const u8, arena: std.mem.Allocator) ![]const u8 {
    const result = try processBytes(.hash, payload, arena);
    return arena.dupe(u8, result[0..32]);
}

fn processBytes(op: engine.Operation, payload: []const u8, arena: std.mem.Allocator) ![]const u8 {
    var response_buffer: [4096]u8 = undefined;
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
