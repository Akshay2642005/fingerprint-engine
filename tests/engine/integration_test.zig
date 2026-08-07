const std = @import("std");
const testing = std.testing;
const engine = @import("engine");
const model = @import("model");
const serialization = @import("serialization");
const builders = @import("test_utils").builders;

const Request = engine.Request;
const Response = engine.Response;
const Status = engine.Status;

test "integration: similarity returns the expected score" {
    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const a = try makeFingerprint("Mozilla/5.0", 8, arena);
    const b = try makeFingerprint("Mozilla/5.0", 8, arena);

    const a_bytes = try encodeFp(arena, a);
    const b_bytes = try encodeFp(arena, b);
    const dual = try buildDualPayload(arena, a_bytes, b_bytes);

    const result = try runOp(.similarity, dual, arena);
    try testing.expectEqual(@as(usize, 10), result.len); // f64 + u16 compared

    const score_bits = std.mem.readInt(u64, result[0..8], .little);
    const score: f64 = @bitCast(score_bits);
    try testing.expectEqual(@as(f64, 1.0), score); // identical fingerprints
    try testing.expectEqual(@as(u16, @intCast(a.features.len)), std.mem.readInt(u16, result[8..10], .little));
}

test "integration: package output embeds a re-decodable package" {
    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const fp = try makeFingerprint("Mozilla/5.0", 8, arena);
    const payload = try encodeFp(arena, fp);
    const result = try runOp(.package, payload, arena);

    // Layout: validation block, then u32 package_len | package bytes.
    var offset: usize = 0;
    offset += 1; // is_valid
    const required_count = readU16(result, &offset);
    offset += @as(usize, required_count) * 3; // feature_id u16 + is_critical u8
    const norm_count = readU16(result, &offset);
    offset += @as(usize, norm_count) * 3; // kind u8 + feature_id u16
    const package_len = readU32(result, &offset);
    const package = result[offset .. offset + package_len];

    var fbs = std.io.fixedBufferStream(package);
    const decoded = try serialization.decode(fbs.reader(), arena);
    try testing.expectEqual(@as(usize, fp.features.len), decoded.fingerprint.features.len);
    for (decoded.fingerprint.features, fp.features) |got, want| {
        try testing.expectEqual(want.id, got.id);
    }
}

test "integration: risk flags a low-coverage fingerprint" {
    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    // A nearly empty fingerprint has missing required features and low
    // coverage, so the risk score must be nonzero.
    const empty = builders.emptyFingerprint();
    const payload = try encodeFp(arena, empty);
    const result = try runOp(.risk, payload, arena);

    const score_bits = std.mem.readInt(u64, result[0..8], .little);
    const score: f64 = @bitCast(score_bits);
    try testing.expect(score > 0.0);
    try testing.expect(result.len >= 8 + 1 + 1 + 1); // score + label + flags

    const label_len = result[8];
    const flag_count = result[9 + label_len];
    try testing.expect(flag_count > 0);
}

fn makeFingerprint(user_agent: []const u8, cores: i64, arena: std.mem.Allocator) !model.Fingerprint {
    const feats = [_]model.Feature{
        builders.stringFeature(.UserAgent, user_agent),
        builders.intFeature(.HardwareConcurrency, cores),
        builders.intFeature(.ScreenWidth, 1920),
        builders.stringFeature(.Language, "en-US"),
        builders.boolFeature(.CookieEnabled, true),
    };
    return builders.makeFingerprint(try arena.dupe(model.Feature, &feats));
}

fn buildDualPayload(arena: std.mem.Allocator, a: []const u8, b: []const u8) ![]const u8 {
    var buffer: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const w = fbs.writer();
    try w.writeInt(u32, @intCast(a.len), .little);
    try w.writeAll(a);
    try w.writeAll(b);
    return arena.dupe(u8, fbs.getWritten());
}

fn readU16(bytes: []const u8, offset: *usize) u16 {
    const value = std.mem.readInt(u16, bytes[offset.*..][0..2], .little);
    offset.* += 2;
    return value;
}

fn readU32(bytes: []const u8, offset: *usize) u32 {
    const value = std.mem.readInt(u32, bytes[offset.*..][0..4], .little);
    offset.* += 4;
    return value;
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
