// story: m7-collection-event-publish
//! Collection envelope wiring (ADR-013 §1): the worker publishes one
//! `collection_event` frame next to the unchanged digest reply. These tests
//! drive the real package → `processFrame` → envelope path, so what the ledger
//! receives is what the engine actually computed — digests, counts, and
//! metadata are cross-checked against the reply, not against a fixture that
//! could drift from it.

const std = @import("std");
const testing = std.testing;
const model = @import("model");
const serialization = @import("serialization");
const engine = @import("engine");
const adapter = @import("adapter");
const io = @import("io");
const worker = @import("worker");

const collection_event = worker.collection_event;

const event_buf_len = io.frame.header_size + collection_event.max_payload;

fn makePackage() ![]u8 {
    const fp = model.Fingerprint{
        .metadata = .{
            .schema_version = serialization.schema_version_v2,
            .sdk_version = "1.0.0-rc.1",
            .collected_at = 1757312345678,
            .package_id = .{
                0x8d, 0x56, 0x52, 0x9f, 0x06, 0x04, 0x0b, 0x90,
                0xdf, 0x4c, 0xb2, 0x5a, 0x38, 0x11, 0xa1, 0x0e,
            },
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

fn inboundFrame(payload: []const u8, buf: []u8) ![]const u8 {
    return adapter.buildFrame(.signal_package, .binary, payload, buf);
}

fn inboundContextFrame(
    payload: []const u8,
    session_id: []const u8,
    ingress_received_at: i64,
    wrap_buf: []u8,
    frame_buf: []u8,
) ![]const u8 {
    const wrapped = try io.session_context.wrap(wrap_buf, session_id, ingress_received_at, payload);
    return adapter.buildFrame(.signal_package_context, .binary, wrapped, frame_buf);
}

fn hex(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |byte, i| {
        _ = std.fmt.bufPrint(out[i * 2 ..][0..2], "{x:0>2}", .{byte}) catch unreachable;
    }
    return out;
}

test "collection event: builds the ADR-013 envelope from a real package" {
    const payload = try makePackage();
    defer testing.allocator.free(payload);

    var frame_buf: [io.frame.header_size + 512]u8 = undefined;
    const frame = try inboundFrame(payload, &frame_buf);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var reply_buf: [io.frame.header_size + 1 + worker.max_result]u8 = undefined;
    const reply = try worker.processFrame(frame, &reply_buf, a);
    const reply_view = try worker.decodeReply(reply);
    try testing.expectEqual(engine.Status.ok, reply_view.status);

    const out = try testing.allocator.alloc(u8, event_buf_len);
    defer testing.allocator.free(out);
    const event_frame = (try collection_event.build(frame, reply, a, out)).?;

    // Outbound contract: a JSON collection_event frame, not a reply — no
    // status byte, the payload is the document itself (ADR-013 §1).
    const decoded = try adapter.decodeFrame(event_frame);
    try testing.expectEqual(io.frame.MessageType.collection_event, decoded.header.message_type);
    try testing.expectEqual(io.frame.Codec.json, decoded.header.codec);
    try testing.expectEqual(@as(u32, @intCast(decoded.payload.len)), decoded.header.payload_len);

    var parsed = try std.json.parseFromSlice(std.json.Value, a, decoded.payload, .{});
    defer parsed.deinit();
    const doc = parsed.value.object;

    try testing.expectEqual(@as(i64, 2), doc.get("schema_version").?.integer);

    // Idempotency key and metadata are carried verbatim from the package.
    try testing.expectEqualStrings(
        "8d56529f06040b90df4cb25a3811a10e",
        doc.get("package_id").?.string,
    );
    try testing.expectEqualStrings("", doc.get("session_id").?.string);
    try testing.expectEqual(@as(i64, 1757312345678), doc.get("collected_at").?.integer);
    // A plain frame did not traverse the ingress.
    try testing.expectEqual(@as(i64, 0), doc.get("ingress_received_at").?.integer);
    try testing.expectEqualStrings("1.0.0-rc.1", doc.get("sdk_version").?.string);

    // The digests and counts must agree with the in-band reply, byte for byte.
    const result = reply_view.payload;
    const Layout = engine.ops.hash.Layout;
    const fingerprint_hex = try hex(a, result[Layout.fingerprint_digest.offset..][0..32]);
    const core_hex = try hex(a, result[Layout.core_digest.offset..][0..32]);
    try testing.expectEqualStrings(fingerprint_hex, doc.get("fingerprint_id").?.string);
    try testing.expectEqualStrings(core_hex, doc.get("core_digest").?.string);
    try testing.expectEqual(
        @as(i64, std.mem.readInt(u16, result[Layout.feature_count.offset..][0..2], .little)),
        doc.get("feature_count").?.integer,
    );
    try testing.expectEqual(
        @as(i64, std.mem.readInt(u16, result[Layout.core_feature_count.offset..][0..2], .little)),
        doc.get("core_feature_count").?.integer,
    );
    try testing.expectEqual(@as(i64, 0), doc.get("status").?.integer);

    // Canonicalized signals, keyed by registry name — the same order the
    // engine hashed (FeatureID ascending: UserAgent=0, CookieEnabled=9,
    // HardwareConcurrency=11 in the registry).
    const signals = doc.get("signals").?.object;
    try testing.expectEqual(@as(usize, 3), signals.count());
    try testing.expectEqualStrings("Mozilla/5.0", signals.get("User Agent").?.string);
    try testing.expectEqual(@as(i64, 8), signals.get("Hardware Concurrency").?.integer);
    try testing.expectEqual(true, signals.get("Cookie Enabled").?.bool);

    const risk = doc.get("risk").?.object;
    switch (risk.get("score").?) {
        .float, .integer => {},
        else => return error.TestUnexpectedResult,
    }
    try testing.expect(risk.get("label").?.string.len > 0);
}

test "collection event: propagates the ingress context (session id + arrival time)" {
    const payload = try makePackage();
    defer testing.allocator.free(payload);

    var wrap_buf: [io.session_context.header_len + 64 + 512]u8 = undefined;
    var frame_buf: [io.frame.header_size + 512]u8 = undefined;
    const frame = try inboundContextFrame(
        payload,
        "tenant42:8d56529f",
        1757312346789,
        &wrap_buf,
        &frame_buf,
    );

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var reply_buf: [io.frame.header_size + 1 + worker.max_result]u8 = undefined;
    const reply = try worker.processFrame(frame, &reply_buf, a);

    const out = try testing.allocator.alloc(u8, event_buf_len);
    defer testing.allocator.free(out);
    const event_frame = (try collection_event.build(frame, reply, a, out)).?;

    var parsed = try std.json.parseFromSlice(std.json.Value, a, (try adapter.decodeFrame(event_frame)).payload, .{});
    defer parsed.deinit();

    try testing.expectEqualStrings("tenant42:8d56529f", parsed.value.object.get("session_id").?.string);
    try testing.expectEqual(@as(i64, 1757312346789), parsed.value.object.get("ingress_received_at").?.integer);
}

test "collection event: nothing is published for a failed collection" {
    const payload = try makePackage();
    defer testing.allocator.free(payload);

    var frame_buf: [io.frame.header_size + 512]u8 = undefined;
    const frame = try inboundFrame(payload, &frame_buf);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const out = try testing.allocator.alloc(u8, event_buf_len);
    defer testing.allocator.free(out);

    // An error reply: a failed decode cannot have produced trustworthy
    // digests, so the envelope is skipped rather than published with zeros.
    var failed_buf: [io.frame.header_size + 1]u8 = undefined;
    const failed = try adapter.buildFrame(
        .fingerprint_result,
        .binary,
        &.{engine.Status.invalid_payload.code()},
        &failed_buf,
    );
    try testing.expectEqual(@as(?[]const u8, null), try collection_event.build(frame, failed, a, out));

    // A v1-length result (36 bytes) is parseable as a reply but lacks the core
    // triple the envelope requires, so it is skipped too.
    var v1_reply_payload: [36]u8 = [_]u8{0} ** 36;
    v1_reply_payload[0] = engine.Status.ok.code();
    var v1_buf: [io.frame.header_size + 37]u8 = undefined;
    const v1_reply = try adapter.buildFrame(.fingerprint_result, .binary, &v1_reply_payload, &v1_buf);
    try testing.expectEqual(@as(?[]const u8, null), try collection_event.build(frame, v1_reply, a, out));
}

test "collection event: non-collection inbound frames produce no envelope" {
    // The outbound-only types are never collections: even with a successful
    // reply they must not emit a ledger row.
    const payload = try makePackage();
    defer testing.allocator.free(payload);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var frame_buf: [io.frame.header_size + 512]u8 = undefined;
    const frame = try adapter.buildFrame(.signal_package, .binary, payload, &frame_buf);
    var reply_buf: [io.frame.header_size + 1 + worker.max_result]u8 = undefined;
    const reply = try worker.processFrame(frame, &reply_buf, a);

    const out = try testing.allocator.alloc(u8, event_buf_len);
    defer testing.allocator.free(out);

    var diag_buf: [io.frame.header_size + 2]u8 = undefined;
    const diag = try adapter.buildFrame(.diagnostics, .binary, "{}", &diag_buf);
    try testing.expectEqual(@as(?[]const u8, null), try collection_event.build(diag, reply, a, out));
}

test "collection event: a short output buffer is refused, not truncated" {
    const payload = try makePackage();
    defer testing.allocator.free(payload);

    var frame_buf: [io.frame.header_size + 512]u8 = undefined;
    const frame = try inboundFrame(payload, &frame_buf);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var reply_buf: [io.frame.header_size + 1 + worker.max_result]u8 = undefined;
    const reply = try worker.processFrame(frame, &reply_buf, a);

    var tiny: [io.frame.header_size + 8]u8 = undefined;
    try testing.expectError(error.EventTooLarge, collection_event.build(frame, reply, a, &tiny));
}
