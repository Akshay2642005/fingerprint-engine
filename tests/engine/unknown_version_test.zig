const std = @import("std");
const testing = std.testing;
const engine = @import("engine");
const model = @import("model");
const serialization = @import("serialization");
const builders = @import("test_utils").builders;

const Request = engine.Request;
const Response = engine.Response;
const Status = engine.Status;

test "unknown version: mutated schema version maps to unsupported_version" {
    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const fp = builders.makeFingerprint(try arena.dupe(
        model.Feature,
        &[_]model.Feature{
            builders.stringFeature(.UserAgent, "Mozilla/5.0"),
            builders.intFeature(.HardwareConcurrency, 8),
        },
    ));
    const payload = try encodeFp(arena, fp);

    // FNGR body: magic (4) | schema_version u16 LE | feature_count u16 | ...
    try testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, payload[4..6], .little));
    var tampered = try arena.dupe(u8, payload);
    tampered[4] = 2;
    tampered[5] = 0;

    var response_buffer: [2048]u8 = undefined;
    const req = Request{ .operation = .validate, .codec = .binary, .payload = tampered };
    var res = Response.init(.validate, &response_buffer);
    try engine.process(&req, &res, arena);

    try testing.expectEqual(Status.unsupported_version, res.status);
    try testing.expectEqual(@as(usize, 0), res.payload_len);
}

test "unknown version: truncated payload maps to invalid_payload" {
    var response_buffer: [64]u8 = undefined;
    const req = Request{ .operation = .validate, .codec = .binary, .payload = "FNG" };
    var res = Response.init(.validate, &response_buffer);
    try engine.process(&req, &res, std.testing.allocator);

    try testing.expectEqual(Status.invalid_payload, res.status);
}

fn encodeFp(arena: std.mem.Allocator, fp: model.Fingerprint) ![]const u8 {
    var buffer: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try serialization.encode(fbs.writer(), fp);
    return arena.dupe(u8, fbs.getWritten());
}
