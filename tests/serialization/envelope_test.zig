const std = @import("std");
const testing = std.testing;
const model = @import("model");
const serialization = @import("serialization");

const CollectionEvent = serialization.CollectionEvent;

test "collection_event: deterministic golden bytes and fixed key order" {
    const event = fixture();
    const actual = try encode(&event);

    const expected =
        \\{
        \\  "schema_version": 2,
        \\  "package_id": "000102030405060708090a0b0c0d0e0f",
        \\  "session_id": "sess-1",
        \\  "fingerprint_id": "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
        \\  "core_digest": "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
        \\  "core_version": 1,
        \\  "feature_count": 3,
        \\  "core_feature_count": 1,
        \\  "status": 0,
        \\  "entropy": 4.5,
        \\  "risk": {
        \\    "score": 0.15,
        \\    "label": "low",
        \\    "flags": []
        \\  },
        \\  "collected_at": 1757312345,
        \\  "ingress_received_at": 1757312346,
        \\  "sdk_version": "0.4.1",
        \\  "signals": {
        \\    "Language": "en-US",
        \\    "Inner Width": 600
        \\  }
        \\}
    ;

    try testing.expectEqualStrings(expected, actual.slice());
}

test "collection_event: payload starts with JSON, not a status byte" {
    const actual = try encode(&fixture());

    // Engine replies are `u8 status | result`; the event is a bare JSON
    // document (ADR-013 §2), so byte 0 is `{` and there is no status prefix.
    try testing.expectEqual(@as(u8, '{'), actual.slice()[0]);
    try testing.expect(!std.mem.eql(u8, actual.slice()[0..1], &[_]u8{0}));
}

test "collection_event: keys appear in the frozen order" {
    const actual = try encode(&fixture());
    const keys = [_][]const u8{
        "schema_version",
        "package_id",
        "session_id",
        "fingerprint_id",
        "core_digest",
        "core_version",
        "feature_count",
        "core_feature_count",
        "status",
        "entropy",
        "risk",
        "collected_at",
        "ingress_received_at",
        "sdk_version",
        "signals",
    };

    var previous: usize = 0;
    for (keys, 0..) |key, i| {
        const needle = try std.fmt.allocPrint(testing.allocator, "\"{s}\":", .{key});
        defer testing.allocator.free(needle);
        const at = std.mem.indexOf(u8, actual.slice(), needle) orelse {
            std.debug.print("missing key: {s}\n", .{key});
            return error.TestUnexpectedResult;
        };
        if (i > 0) try testing.expect(at > previous);
        previous = at;
    }
}

test "collection_event: signal keys use registry names (canonicalized)" {
    const actual = try encode(&fixture());

    // The wire FeatureID is `InnerWidth`, but the ledger key is the registry
    // display name — the same mapping `jsonEncode` uses.
    try testing.expectEqualStrings("Inner Width", model.Registry.get(.InnerWidth).name);
    try testing.expect(std.mem.indexOf(u8, actual.slice(), "\"Inner Width\": 600") != null);
    try testing.expect(std.mem.indexOf(u8, actual.slice(), "InnerWidth") == null);
}

test "collection_event: encoding is byte-identical across runs" {
    const first = try encode(&fixture());
    const second = try encode(&fixture());
    try testing.expectEqualSlices(u8, first.slice(), second.slice());
}

test "collection_event: output is valid JSON and round-trips field values" {
    const actual = try encode(&fixture());

    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, actual.slice(), .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try testing.expectEqual(@as(i64, 2), root.get("schema_version").?.integer);
    try testing.expectEqualStrings("sess-1", root.get("session_id").?.string);
    try testing.expectEqual(@as(i64, 1), root.get("core_version").?.integer);
    try testing.expectEqual(@as(i64, 3), root.get("feature_count").?.integer);
    try testing.expectEqual(@as(i64, 1), root.get("core_feature_count").?.integer);
    try testing.expectEqual(@as(i64, 0), root.get("status").?.integer);
    try testing.expectEqual(@as(f64, 4.5), root.get("entropy").?.float);
    try testing.expectEqual(@as(f64, 0.15), root.get("risk").?.object.get("score").?.float);
    try testing.expectEqualStrings("low", root.get("risk").?.object.get("label").?.string);
    try testing.expectEqual(@as(usize, 0), root.get("risk").?.object.get("flags").?.array.items.len);
    try testing.expectEqual(@as(i64, 1757312345), root.get("collected_at").?.integer);
    try testing.expectEqual(@as(i64, 1757312346), root.get("ingress_received_at").?.integer);
    try testing.expectEqualStrings(
        "en-US",
        root.get("signals").?.object.get("Language").?.string,
    );
    try testing.expectEqual(
        @as(i64, 600),
        root.get("signals").?.object.get("Inner Width").?.integer,
    );
}

test "collection_event: risk flags encode as tag names" {
    var event = fixture();
    event.risk.score = 0.8;
    event.risk.label = "high";
    event.risk.flags = &.{ .missing_required_feature, .low_feature_coverage };

    const actual = try encode(&event);
    try testing.expect(std.mem.indexOf(
        u8,
        actual.slice(),
        "\"flags\": [\"missing_required_feature\", \"low_feature_coverage\"]",
    ) != null);
}

test "collection_event: empty signals encode as an empty object" {
    var event = fixture();
    event.signals = &.{};

    const actual = try encode(&event);
    try testing.expect(std.mem.endsWith(u8, actual.slice(), "\"signals\": {\n  }\n}"));
}

fn fixture() CollectionEvent {
    return .{
        .schema_version = 2,
        .package_id = sequential(16, 0),
        .session_id = "sess-1",
        .fingerprint_digest = sequential(32, 0),
        .core_digest = sequential(32, 32),
        .core_version = 1,
        .feature_count = 3,
        .core_feature_count = 1,
        .status = 0,
        .entropy = 4.5,
        .risk = .{ .score = 0.15, .label = "low", .flags = &.{} },
        .collected_at = 1757312345,
        .ingress_received_at = 1757312346,
        .sdk_version = "0.4.1",
        .signals = &.{
            .{ .id = .Language, .value = .{ .String = "en-US" } },
            .{ .id = .InnerWidth, .value = .{ .Integer = 600 } },
        },
    };
}

/// Encoded bytes plus their length. Stack-owned so the tests stay leak-free;
/// the envelope is far smaller than the 1 KiB bound.
const Encoded = struct {
    buf: [1024]u8 = undefined,
    len: usize = 0,

    fn slice(self: *const Encoded) []const u8 {
        return self.buf[0..self.len];
    }
};

fn encode(event: *const CollectionEvent) !Encoded {
    var out: Encoded = .{};
    var fbs = std.io.fixedBufferStream(&out.buf);
    try serialization.encodeCollectionEvent(fbs.writer(), event.*);
    out.len = fbs.pos;
    return out;
}

fn sequential(comptime n: usize, start: u8) [n]u8 {
    var out: [n]u8 = undefined;
    for (&out, 0..) |*byte, i| byte.* = start +% @as(u8, @intCast(i));
    return out;
}
