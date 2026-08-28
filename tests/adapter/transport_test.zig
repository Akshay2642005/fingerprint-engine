const std = @import("std");
const testing = std.testing;
const io = @import("io");
const adapter = @import("adapter");

test "buildFrame and decodeFrame round-trip a payload" {
    var buffer: [io.frame.header_size + 64]u8 = undefined;
    const frame = try adapter.buildFrame(.signal_package, .binary, "hello", &buffer);

    const decoded = try adapter.decodeFrame(frame);
    try testing.expectEqual(io.frame.MessageType.signal_package, decoded.header.message_type);
    try testing.expectEqual(io.frame.Codec.binary, decoded.header.codec);
    try testing.expectEqualStrings("hello", decoded.payload);
}

test "decodeFrame rejects tampered payloads" {
    var buffer: [io.frame.header_size + 64]u8 = undefined;
    const frame = try adapter.buildFrame(.signal_package, .binary, "payload", &buffer);

    var tampered: [io.frame.header_size + 64]u8 = undefined;
    @memcpy(tampered[0..frame.len], frame);
    tampered[frame.len - 1] ^= 0xff;

    try testing.expectError(
        error.IntegrityViolation,
        adapter.decodeFrame(tampered[0..frame.len]),
    );
}

test "decodeFrame rejects truncated frames" {
    var buffer: [io.frame.header_size + 64]u8 = undefined;
    const frame = try adapter.buildFrame(.signal_package, .binary, "payload", &buffer);

    // Header parses, but the declared payload runs past the input.
    try testing.expectError(error.Truncated, adapter.decodeFrame(frame[0 .. frame.len - 3]));
}

test "decodeFrame rejects input shorter than a header" {
    const short = [_]u8{ 0x46, 0x50, 0x4b, 0x47 };
    try testing.expectError(error.Truncated, adapter.decodeFrame(&short));
}

test "decodeFrame rejects oversized payload lengths" {
    var buffer: [io.frame.header_size + 64]u8 = undefined;
    const frame = try adapter.buildFrame(.signal_package, .binary, "payload", &buffer);

    var tampered: [io.frame.header_size + 64]u8 = undefined;
    @memcpy(tampered[0..frame.len], frame);
    // payload_len sits at byte offset 8 (little-endian u32); set it to
    // 0x01000001 = max_payload + 1.
    tampered[8] = 0x01;
    tampered[9] = 0x00;
    tampered[10] = 0x00;
    tampered[11] = 0x01;

    try testing.expectError(error.PayloadTooLarge, adapter.decodeFrame(tampered[0..frame.len]));
}

test "buildFrame rejects payloads above the 16 MiB cap" {
    const huge = try testing.allocator.alloc(u8, adapter.max_payload + 1);
    defer testing.allocator.free(huge);
    var buffer: [io.frame.header_size]u8 = undefined;
    try testing.expectError(
        error.PayloadTooLarge,
        adapter.buildFrame(.signal_package, .binary, huge, &buffer),
    );
}

test "decodeFrame surfaces header errors through the header decode" {
    var buffer: [io.frame.header_size + 64]u8 = undefined;
    const frame = try adapter.buildFrame(.signal_package, .binary, "payload", &buffer);

    var bad_magic: [io.frame.header_size + 64]u8 = undefined;
    @memcpy(bad_magic[0..frame.len], frame);
    bad_magic[0] = 'X';
    try testing.expectError(error.InvalidMagic, adapter.decodeFrame(bad_magic[0..frame.len]));

    var bad_version: [io.frame.header_size + 64]u8 = undefined;
    @memcpy(bad_version[0..frame.len], frame);
    bad_version[4] = 2; // version = 2, little-endian u16
    bad_version[5] = 0;
    try testing.expectError(error.UnsupportedVersion, adapter.decodeFrame(bad_version[0..frame.len]));
}

test "readFrameFrom reads one frame from a std reader" {
    var buffer: [io.frame.header_size + 64]u8 = undefined;
    const frame = try adapter.buildFrame(.signal_package, .binary, "payload", &buffer);

    var fbs = std.io.fixedBufferStream(frame);
    const read = try adapter.readFrameFrom(fbs.reader(), testing.allocator);
    defer testing.allocator.free(read);
    try testing.expectEqualStrings(frame, read);
}

test "readFrameFrom rejects tampered frames" {
    var buffer: [io.frame.header_size + 64]u8 = undefined;
    const frame = try adapter.buildFrame(.signal_package, .binary, "payload", &buffer);

    var tampered: [io.frame.header_size + 64]u8 = undefined;
    @memcpy(tampered[0..frame.len], frame);
    tampered[frame.len - 1] ^= 0xff;

    var fbs = std.io.fixedBufferStream(tampered[0..frame.len]);
    try testing.expectError(
        error.IntegrityViolation,
        adapter.readFrameFrom(fbs.reader(), testing.allocator),
    );
}

test "resolveHost parses an IPv4 literal directly" {
    const addr = try adapter.transport.resolveHost(testing.allocator, "127.0.0.1", 8080);
    try testing.expectEqual(@as(u16, 8080), addr.getPort());
    try testing.expect(addr.any.family == std.posix.AF.INET);
    // Round-trips identically to parseIp for a literal — the fast path and
    // the getaddrinfo path agree on the address.
    const parsed = std.net.Address.parseIp("127.0.0.1", 8080) catch unreachable;
    try testing.expectEqual(parsed.any.family, addr.any.family);
    switch (addr.any.family) {
        std.posix.AF.INET => try testing.expectEqual(parsed.in.sa.addr, addr.in.sa.addr),
        std.posix.AF.INET6 => try testing.expectEqual(parsed.in6.sa.addr, addr.in6.sa.addr),
        else => unreachable,
    }
}

test "resolveHost resolves a DNS hostname" {
    // `localhost` resolves on every supported dev platform (and in the
    // test container via /etc/hosts), exercising the getaddrinfo path.
    const addr = try adapter.transport.resolveHost(testing.allocator, "localhost", 8080);
    try testing.expectEqual(@as(u16, 8080), addr.getPort());
    const family = addr.any.family;
    try testing.expect(family == std.posix.AF.INET or family == std.posix.AF.INET6);
}
