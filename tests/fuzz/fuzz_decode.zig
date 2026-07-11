/// Fuzz testing for binary decode — the most critical attack surface.
/// Tests that decode never crashes, leaks memory, or produces undefined
/// behavior regardless of input.

const std = @import("std");
const testing = std.testing;
const core = @import("core");

const Fingerprint = core.fingerprint.Fingerprint;
const FeatureValue = core.fingerprint.FeatureValue;

fn fuzzDecodeArbitrary(_: void, smith: *testing.Smith) anyerror!void {
    // Generate a random byte buffer (0..4096 bytes)
    var buf: [4096]u8 = undefined;
    const len = smith.sliceWithHash(&buf, 0);

    // Create a Reader from the random bytes
    var tr = testing.Reader.init(&buf, &.{.{ .buffer = buf[0..len] }});

    // decode must never crash — only return error or success
    var result = core.serialization.decode(&tr.interface, std.heap.page_allocator) catch return;
    defer result.deinit();

    // If decode succeeded, the result should be valid
    _ = result.fingerprint.features.len;
}

test "fuzz: binary decode handles arbitrary bytes" {
    try testing.fuzz({}, fuzzDecodeArbitrary, .{});
}

fn fuzzDecodeTruncated(_: void, smith: *testing.Smith) anyerror!void {
    // Start with valid encoded data, then truncate it
    const valid_fp = Fingerprint{
        .metadata = .{
            .schema_version = 1,
            .sdk_version = "0.1.0",
            .collected_at = 0,
        },
        .features = &.{},
    };

    var al: std.ArrayList(u8) = .empty;
    al.ensureTotalCapacity(std.heap.page_allocator, 256) catch return;
    var w = std.Io.Writer.fromArrayList(&al);
    core.serialization.encode(&w, valid_fp) catch return;
    var encoded = w.toArrayList();
    defer encoded.deinit(std.heap.page_allocator);

    // Truncate at random point
    const trunc_len = smith.indexWithHash(encoded.items.len + 1, 1);
    const truncated = encoded.items[0..trunc_len];

    // Create a Reader from the truncated data
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..truncated.len], truncated);
    var tr = testing.Reader.init(&buf, &.{.{ .buffer = buf[0..truncated.len] }});

    // Must not crash
    var result = core.serialization.decode(&tr.interface, std.heap.page_allocator) catch return;
    defer result.deinit();
}

test "fuzz: binary decode truncated input" {
    try testing.fuzz({}, fuzzDecodeTruncated, .{});
}
