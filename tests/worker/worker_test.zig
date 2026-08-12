const std = @import("std");
const testing = std.testing;
const model = @import("model");
const serialization = @import("serialization");
const engine = @import("engine");
const adapter = @import("adapter");
const io = @import("io");
const worker = @import("worker");
const version_info = @import("version");

const test_package_id = [16]u8{
    0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
};

test "worker: version matches the injected build version (BUG-002)" {
    // The CLI must advertise the same version the build injected; a drift
    // here means the version single-source-of-truth was bypassed.
    try testing.expectEqualStrings(version_info.version, worker.version);
}

test "worker: parse defaults to start with loopback transport" {
    const command = try worker.parse(&.{ "worker", "start" });
    switch (command) {
        .start => |options| {
            try testing.expectEqual(worker.TransportKind.loopback, options.transport);
            try testing.expectEqual(worker.PublishKind.none, options.publish);
            try testing.expect(options.listen == null);
        },
        else => unreachable,
    }
}

test "worker: parse tcp transport requires --listen" {
    try testing.expectError(error.MissingListen, worker.parse(&.{ "worker", "start", "--transport=tcp" }));

    const command = try worker.parse(&.{ "worker", "start", "--transport=tcp", "--listen=127.0.0.1:0" });
    switch (command) {
        .start => |options| {
            try testing.expectEqual(worker.TransportKind.tcp, options.transport);
            try testing.expectEqualStrings("127.0.0.1:0", options.listen.?);
        },
        else => unreachable,
    }
}

test "worker: parse version and help commands" {
    try testing.expect(try worker.parse(&.{ "worker", "version" }) == .version);
    try testing.expect(try worker.parse(&.{"worker"}) == .help);
    try testing.expect(try worker.parse(&.{ "worker", "--help" }) == .help);
    try testing.expect(try worker.parse(&.{ "worker", "-h" }) == .help);
}

test "worker: parse idle-timeout-ms defaults to 30000" {
    const command = try worker.parse(&.{ "worker", "start" });
    switch (command) {
        .start => |options| try testing.expectEqual(@as(u64, 30_000), options.idle_timeout_ms),
        else => unreachable,
    }
}

test "worker: parse idle-timeout-ms overrides and zero disables" {
    const command = try worker.parse(&.{ "worker", "start", "--idle-timeout-ms=500" });
    switch (command) {
        .start => |options| try testing.expectEqual(@as(u64, 500), options.idle_timeout_ms),
        else => unreachable,
    }

    const disabled = try worker.parse(&.{ "worker", "start", "--idle-timeout-ms=0" });
    switch (disabled) {
        .start => |options| try testing.expectEqual(@as(u64, 0), options.idle_timeout_ms),
        else => unreachable,
    }
}

test "worker: parse rejects a non-numeric idle-timeout-ms" {
    try testing.expectError(error.InvalidOption, worker.parse(&.{ "worker", "start", "--idle-timeout-ms=soon" }));
}

test "worker: parse rejects unknown subcommands and options" {
    try testing.expectError(error.UnknownSubcommand, worker.parse(&.{ "worker", "bogus" }));
    try testing.expectError(error.UnknownOption, worker.parse(&.{ "worker", "start", "--bogus=1" }));
    try testing.expectError(error.InvalidOption, worker.parse(&.{ "worker", "start", "--transport=carrier-pigeon" }));
    try testing.expectError(error.InvalidOption, worker.parse(&.{ "worker", "start", "--publish=carrier-pigeon" }));
}

test "worker: parse amqp options default to the local broker" {
    const command = try worker.parse(&.{ "worker", "start", "--publish=amqp" });
    switch (command) {
        .start => |options| {
            try testing.expectEqual(worker.PublishKind.amqp, options.publish);
            try testing.expectEqualStrings("127.0.0.1:5672", options.amqp_address);
            try testing.expectEqualStrings("guest", options.amqp_user);
            try testing.expectEqualStrings("guest", options.amqp_password);
            try testing.expectEqualStrings("/", options.amqp_vhost);
        },
        else => unreachable,
    }
}

test "worker: parse amqp options override broker settings" {
    const command = try worker.parse(&.{
        "worker",
        "start",
        "--publish=amqp",
        "--amqp-address=10.0.0.5:5673",
        "--amqp-user=alice",
        "--amqp-password=s3cret",
        "--amqp-vhost=production",
    });
    switch (command) {
        .start => |options| {
            try testing.expectEqualStrings("10.0.0.5:5673", options.amqp_address);
            try testing.expectEqualStrings("alice", options.amqp_user);
            try testing.expectEqualStrings("s3cret", options.amqp_password);
            try testing.expectEqualStrings("production", options.amqp_vhost);
        },
        else => unreachable,
    }
}

test "worker: operationFor maps inbound message types" {
    try testing.expectEqual(engine.Operation.hash, worker.operationFor(.signal_package).?);
    try testing.expectEqual(engine.Operation.validate, worker.operationFor(.validation_result).?);
    try testing.expectEqual(engine.Operation.normalize, worker.operationFor(.normalization_result).?);
    try testing.expectEqual(engine.Operation.hash, worker.operationFor(.fingerprint_result).?);
    try testing.expectEqual(engine.Operation.risk, worker.operationFor(.risk_result).?);
    try testing.expectEqual(engine.Operation.similarity, worker.operationFor(.similarity_result).?);
    try testing.expect(worker.operationFor(.diagnostics) == null);
    try testing.expect(worker.operationFor(.fingerprint_computed) == null);
    try testing.expect(worker.operationFor(.entropy_result) == null);
}

test "worker: resultType maps operations to reply message types" {
    try testing.expectEqual(io.frame.MessageType.fingerprint_result, worker.resultType(.hash));
    try testing.expectEqual(io.frame.MessageType.validation_result, worker.resultType(.validate));
    try testing.expectEqual(io.frame.MessageType.normalization_result, worker.resultType(.normalize));
    try testing.expectEqual(io.frame.MessageType.risk_result, worker.resultType(.risk));
    try testing.expectEqual(io.frame.MessageType.similarity_result, worker.resultType(.similarity));
    try testing.expectEqual(io.frame.MessageType.entropy_result, worker.resultType(.entropy));
    try testing.expectEqual(io.frame.MessageType.signal_package, worker.resultType(.package));
}

test "worker: processFrame hashes a signal package end to end" {
    const payload = try makeSignalPackage();
    defer testing.allocator.free(payload);

    var frame_buf: [io.frame.header_size + 512]u8 = undefined;
    const frame = try adapter.buildFrame(.signal_package, .binary, payload, &frame_buf);

    // The engine allocates decoded state from scratch; an arena keeps the
    // test leak-free, matching the worker's service loop.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var reply_buf: [io.frame.header_size + 1 + worker.max_result]u8 = undefined;
    const reply = try worker.processFrame(frame, &reply_buf, arena.allocator());

    const parsed = try worker.decodeReply(reply);
    try testing.expectEqual(io.frame.MessageType.fingerprint_result, parsed.message_type);
    try testing.expectEqual(engine.Status.ok, parsed.status);
    // digest | feature_count | schema_version
    try testing.expectEqual(@as(usize, 32 + 2 + 2), parsed.payload.len);
    try testing.expectEqual(@as(u16, 3), std.mem.readInt(u16, parsed.payload[32..34], .little));
    try testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, parsed.payload[34..36], .little));

    // The reply must match the engine's own hash of the same payload.
    var res_buf: [128]u8 = undefined;
    var res = engine.Response.init(.hash, &res_buf);
    var req = engine.Request{ .operation = .hash, .codec = .binary, .payload = payload };
    try engine.process(&req, &res, arena.allocator());
    try testing.expectEqualSlices(u8, res.slice(), parsed.payload);
}

test "worker: processFrame replies invalid_request for outbound-only types" {
    var frame_buf: [io.frame.header_size + 64]u8 = undefined;
    const frame = try adapter.buildFrame(.diagnostics, .binary, "{}", &frame_buf);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var reply_buf: [io.frame.header_size + 1 + worker.max_result]u8 = undefined;
    const reply = try worker.processFrame(frame, &reply_buf, arena.allocator());

    const parsed = try worker.decodeReply(reply);
    try testing.expectEqual(engine.Status.invalid_request, parsed.status);
    try testing.expectEqual(@as(usize, 0), parsed.payload.len);
}

test "worker: processFrame rejects tampered frames" {
    const payload = try makeSignalPackage();
    defer testing.allocator.free(payload);

    var frame_buf: [io.frame.header_size + 512]u8 = undefined;
    const frame = try adapter.buildFrame(.signal_package, .binary, payload, &frame_buf);
    frame_buf[frame.len - 1] ^= 0xff;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var reply_buf: [io.frame.header_size + 1 + worker.max_result]u8 = undefined;
    try testing.expectError(
        error.IntegrityViolation,
        worker.processFrame(frame_buf[0..frame.len], &reply_buf, arena.allocator()),
    );
}

test "worker: decodeReply rejects frames without a status byte" {
    var frame_buf: [io.frame.header_size]u8 = undefined;
    const frame = try adapter.buildFrame(.fingerprint_result, .binary, "", &frame_buf);
    try testing.expectError(error.Truncated, worker.decodeReply(frame));
}

fn makeSignalPackage() ![]u8 {
    const fp = model.Fingerprint{
        .metadata = .{
            .schema_version = serialization.schema_version_v2,
            .sdk_version = "0.2.0",
            .collected_at = 1700000000123,
            .package_id = test_package_id,
        },
        .features = &.{
            model.Feature{ .id = model.FeatureID.UserAgent, .value = .{ .String = "Mozilla/5.0" } },
            model.Feature{ .id = model.FeatureID.CookieEnabled, .value = .{ .Boolean = true } },
            model.Feature{ .id = model.FeatureID.HardwareConcurrency, .value = .{ .Integer = 8 } },
        },
    };
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try serialization.encode(fbs.writer(), fp);
    return testing.allocator.dupe(u8, fbs.getWritten());
}
