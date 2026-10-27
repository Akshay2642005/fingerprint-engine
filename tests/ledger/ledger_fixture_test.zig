// story: m7-ledger-contract
//! Ledger contract fixtures (M7 W6-D2).
//!
//! `deploy/ledger/` ships the platform-side schema (Postgres DDL + MongoDB
//! validator) for the ADR-013 envelope. This test keeps the committed example
//! envelope honest: it is *generated* by the production encoder from the
//! canonical SignalPackage fixture, through the real worker reply path, so a
//! schema change on either side shows up as a diff instead of a stale example
//! that no consumer can actually parse.
//!
//! The example uses an ingress context (session + arrival time) because that is
//! the normal browser path; a direct TCP/loopback collection differs only in
//! `session_id` ("") and `ingress_received_at` (0).
//!
//! Regenerate after an intentional contract change:
//!   SNAP_UPDATE=1 zig build test -- ledger

const std = @import("std");
const testing = std.testing;
const io = @import("io");
const adapter = @import("adapter");
const worker = @import("worker");

const collection_event = worker.collection_event;

const fixture_path = "tests/fixtures/ledger/collection-event-v2.json";
const package_path = "tests/fixtures/fingerprints/signal-package-v2.bin";
const session_id = "tenant42:8d56529f";
const ingress_received_at: i64 = 1757312346789;

/// Builds the example envelope exactly the way the worker does: canonical
/// package fixture → ingress context frame → engine reply → `collection_event`.
fn buildExampleEnvelope(alloc: std.mem.Allocator) ![]const u8 {
    var arena_instance = std.heap.ArenaAllocator.init(alloc);
    defer arena_instance.deinit();
    const a = arena_instance.allocator();

    const package = try std.fs.cwd().readFileAlloc(a, package_path, 1 << 16);

    const wrapped = try a.alloc(u8, io.session_context.header_len + session_id.len + package.len);
    const context = try io.session_context.wrap(wrapped, session_id, ingress_received_at, package);

    const frame_buf = try a.alloc(u8, io.frame.header_size + context.len);
    const frame = try adapter.buildFrame(.signal_package_context, .binary, context, frame_buf);

    const reply_buf = try a.alloc(u8, io.frame.header_size + 1 + worker.max_result);
    const reply = try worker.processFrame(frame, reply_buf, a);

    const out = try a.alloc(u8, io.frame.header_size + collection_event.max_payload);
    const event_frame = (try collection_event.build(frame, reply, a, out)).?;
    return alloc.dupe(u8, (try adapter.decodeFrame(event_frame)).payload);
}

fn writeFixture(data: []const u8) !void {
    try std.fs.cwd().makePath(std.fs.path.dirname(fixture_path).?);
    try std.fs.cwd().writeFile(.{ .sub_path = fixture_path, .data = data });
}

test "ledger: the committed example envelope matches the encoder" {
    const expected = try buildExampleEnvelope(testing.allocator);
    defer testing.allocator.free(expected);

    const on_disk = std.fs.cwd().readFileAlloc(testing.allocator, fixture_path, 1 << 20) catch |err| switch (err) {
        error.FileNotFound => {
            if (!std.process.hasEnvVarConstant("SNAP_UPDATE")) return err;
            try writeFixture(expected);
            return;
        },
        else => return err,
    };
    defer testing.allocator.free(on_disk);

    if (!std.mem.eql(u8, on_disk, expected)) {
        if (std.process.hasEnvVarConstant("SNAP_UPDATE")) {
            try writeFixture(expected);
            return;
        }
        std.debug.print("ledger fixture is stale; rerun with SNAP_UPDATE=1 to regenerate\n", .{});
        return error.TestUnexpectedResult;
    }
}

test "ledger: the example envelope has the frozen ADR-013 shape" {
    const raw = try std.fs.cwd().readFileAlloc(testing.allocator, fixture_path, 1 << 20);
    defer testing.allocator.free(raw);

    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, raw, .{});
    defer parsed.deinit();
    const doc = parsed.value.object;

    const required = [_][]const u8{
        "schema_version",      "package_id",   "session_id",    "fingerprint_id",
        "core_digest",         "core_version", "feature_count", "core_feature_count",
        "status",              "entropy",      "risk",          "collected_at",
        "ingress_received_at", "sdk_version",  "signals",
    };
    for (required) |key| try testing.expect(doc.get(key) != null);

    // Idempotency key: exactly the SDK-minted lowercase hex id.
    const package_id = doc.get("package_id").?.string;
    try testing.expectEqual(@as(usize, 32), package_id.len);
    for (package_id) |byte| try testing.expect(std.ascii.isHex(byte) and !std.ascii.isUpper(byte));

    // Digests are lower-hex SHA-256.
    for ([_][]const u8{ "fingerprint_id", "core_digest" }) |key| {
        const digest = doc.get(key).?.string;
        try testing.expectEqual(@as(usize, 64), digest.len);
        for (digest) |byte| try testing.expect(std.ascii.isHex(byte) and !std.ascii.isUpper(byte));
    }

    // The context this fixture was generated with.
    try testing.expectEqualStrings(session_id, doc.get("session_id").?.string);
    try testing.expectEqual(ingress_received_at, doc.get("ingress_received_at").?.integer);

    // Shapes the ledger schema validates.
    try testing.expectEqual(@as(usize, 3), doc.get("risk").?.object.count());
    try testing.expect(doc.get("signals").?.object.count() > 0);
    try testing.expectEqual(@as(i64, 0), doc.get("status").?.integer);
    try testing.expect(doc.get("entropy").?.float >= 0);
}
