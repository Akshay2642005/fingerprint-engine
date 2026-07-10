const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;
const serialization = @import("core").serialization;

// ──────────────────────────────────────────────
// Binary Serialization — Encode
// ──────────────────────────────────────────────

test "encode empty fingerprint produces correct magic header" {
    const meta = fingerprint.FingerprintMetadata{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
    const fp = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{},
    };

    var buf: [128]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try serialization.encode(&w, fp);

    const bytes = buf[0..w.end];
    // Magic "FNGR" at offset 0
    try testing.expectEqual(@as(u8, 'F'), bytes[0]);
    try testing.expectEqual(@as(u8, 'N'), bytes[1]);
    try testing.expectEqual(@as(u8, 'G'), bytes[2]);
    try testing.expectEqual(@as(u8, 'R'), bytes[3]);
    // Schema version 1 at offset 4 (u16 LE)
    try testing.expectEqual(@as(u8, 1), bytes[4]);
    try testing.expectEqual(@as(u8, 0), bytes[5]);
    // Feature count 0 at offset 6 (u16 LE)
    try testing.expectEqual(@as(u8, 0), bytes[6]);
    try testing.expectEqual(@as(u8, 0), bytes[7]);
    // Total header is 8 bytes
    try testing.expectEqual(@as(usize, 8), bytes.len);
}
