/// Codec registry (design §5.2): wire-stable tags and the comptime codec
/// interface. Nothing here knows about transports — codecs only move model
/// values between memory and bytes.
const std = @import("std");

/// Codec identifiers — explicit wire tags in the FPKG envelope (design §5).
/// Values must never be renumbered; non-exhaustive so unknown tags map to
/// `invalid_request` rather than a misread payload.
pub const CodecID = enum(u8) {
    binary = 1,
    json = 2,
    _,
};

/// FNGR SignalPackage body schema versions (design §5.1). v1 is the legacy
/// layout (schema + feature_count + features); v2 adds sdk metadata,
/// collection time, and replay identity.
pub const schema_version_v1: u16 = 1;
pub const schema_version_v2: u16 = 2;
