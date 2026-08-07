/// Runtime metadata attached to every fingerprint.
///
/// Identifies the schema version, SDK version, and collection timestamp
/// so downstream consumers can validate compatibility and provenance.
pub const FingerprintMetadata = struct {
    schema_version: u16,
    sdk_version: []const u8,
    collected_at: i64,

    /// Returns true when schema_version is non-zero and sdk_version is non-empty.
    /// A zero schema_version indicates an uninitialized or corrupt metadata block.
    pub fn isValid(self: FingerprintMetadata) bool {
        return self.schema_version > 0 and self.sdk_version.len > 0;
    }
};
