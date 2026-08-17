pub const CodecID = @import("codec.zig").CodecID;
pub const schema_version_v1 = @import("codec.zig").schema_version_v1;
pub const schema_version_v2 = @import("codec.zig").schema_version_v2;

pub const encode = @import("binary.zig").encode;
pub const decode = @import("binary.zig").decode;
pub const DecodedFingerprint = @import("binary.zig").DecodedFingerprint;
pub const jsonEncode = @import("json.zig").jsonEncode;

/// SHA-256 integrity helpers for serialized payloads (design §5). Defined in
/// serialization so the layer stays transport-free; io/frame.zig implements
/// the same digest for envelope validation.
pub const integrityOf = @import("integrity.zig").integrityOf;
pub const integrityValid = @import("integrity.zig").integrityValid;
