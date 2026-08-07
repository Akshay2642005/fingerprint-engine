const std = @import("std");
const testing = std.testing;
const serialization = @import("serialization");

test "integrityOf is deterministic for the same payload" {
    const payload = "0123456789abcdef";
    const a = serialization.integrityOf(payload);
    const b = serialization.integrityOf(payload);
    try testing.expectEqualSlices(u8, &a, &b);
}

test "integrityOf differs across payloads" {
    const a = serialization.integrityOf("payload one");
    const b = serialization.integrityOf("payload two");
    try testing.expect(!std.mem.eql(u8, &a, &b));
}

test "integrityValid detects tampering" {
    const payload = "integrity-protected payload";
    const digest = serialization.integrityOf(payload);
    try testing.expect(serialization.integrityValid(digest, payload));

    var tampered: [payload.len]u8 = undefined;
    @memcpy(&tampered, payload);
    tampered[0] = 'x';
    try testing.expect(!serialization.integrityValid(digest, &tampered));
}
