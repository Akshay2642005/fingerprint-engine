pub const FingerprintMetadata = struct {
    schema_version: u16,
    sdk_version: []const u8,
    collected_at: i64,
};
