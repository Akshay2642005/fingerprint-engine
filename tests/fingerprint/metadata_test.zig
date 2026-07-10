const std = @import("std");
const testing = std.testing;
const fingerprint = @import("core").fingerprint;

// ──────────────────────────────────────────────
// FingerprintMetadata — Construction and access
// ──────────────────────────────────────────────

test "FingerprintMetadata can be constructed with default values" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
    try testing.expectEqual(@as(u16, 1), meta.schema_version);
    try testing.expectEqualStrings("0.1.0", meta.sdk_version);
    try testing.expectEqual(@as(i64, 0), meta.collected_at);
}

test "FingerprintMetadata struct size is reasonable" {
    // u16 (2) + []const u8 (16) + i64 (8) = 26 bytes + alignment padding
    try testing.expect(@sizeOf(fingerprint.FingerprintMetadata) <= 32);
}

test "FingerprintMetadata sdk_version stores and retrieves correctly" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 2,
        .sdk_version = "1.0.0-beta",
        .collected_at = 1_700_000_000,
    };
    try testing.expectEqualStrings("1.0.0-beta", meta.sdk_version);
    try testing.expectEqual(@as(u16, 2), meta.schema_version);
    try testing.expectEqual(@as(i64, 1_700_000_000), meta.collected_at);
}
