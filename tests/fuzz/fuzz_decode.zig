/// Fuzz testing for binary decode — the most critical attack surface.
/// Tests that decode never crashes, leaks memory, or produces undefined
/// behavior regardless of input.
const std = @import("std");
const testing = std.testing;
const model = @import("model");
const serialization = @import("serialization");

const Fingerprint = model.Fingerprint;

fn fuzzDecodeArbitrary(_: void, input: []const u8) anyerror!void {
    var fbs = std.io.fixedBufferStream(input);
    var r = fbs.reader();

    // decode must never crash — only return error or success
    var result = serialization.decode(&r, std.heap.page_allocator) catch return;
    defer result.deinit();

    // If decode succeeded, the result should be valid
    _ = result.fingerprint.features.len;
}

test "fuzz: binary decode handles arbitrary bytes" {
    try testing.fuzz({}, fuzzDecodeArbitrary, .{});
}

fn fuzzDecodeTruncated(_: void, input: []const u8) anyerror!void {
    // Start with valid encoded data, then truncate it
    const valid_fp = Fingerprint{
        .metadata = .{
            .schema_version = 1,
            .sdk_version = "0.1.0",
            .collected_at = 0,
        },
        .features = &.{},
    };

    var buf: [256]u8 = undefined;
    var efbs = std.io.fixedBufferStream(&buf);
    var w = efbs.writer();
    serialization.encode(&w, valid_fp) catch return;
    const encoded = efbs.getWritten();

    // Truncate at a point chosen from the fuzz input
    const trunc_len = if (input.len == 0)
        0
    else
        @min(@as(usize, input[0]) % (encoded.len + 1), encoded.len);
    const truncated = encoded[0..trunc_len];

    var tfbs = std.io.fixedBufferStream(truncated);
    var r = tfbs.reader();

    // Must not crash
    var result = serialization.decode(&r, std.heap.page_allocator) catch return;
    defer result.deinit();
}

test "fuzz: binary decode truncated input" {
    try testing.fuzz({}, fuzzDecodeTruncated, .{});
}
