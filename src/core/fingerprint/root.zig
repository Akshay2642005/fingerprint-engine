pub const Feature = @import("feature.zig").Feature;
pub const FeatureValue = @import("value.zig").FeatureValue;
pub const Fingerprint = @import("fingerprint.zig").Fingerprint;
pub const FingerprintMetadata = @import("metadata.zig").FingerprintMetadata;

/// An ordered slice of Feature values, typically indexed by FeatureID.
/// This is a type alias rather than a newtype to let consumers control
/// allocation strategy (stack buffer, arena, or heap).
pub const FeatureCollection = []const Feature;
