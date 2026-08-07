const model = @import("feature.zig");
const registry = @import("registry.zig");

// ── Feature definition surface (formerly core/features) ──

pub const FeatureCategory = model.FeatureCategory;
pub const FeatureType = model.FeatureType;
pub const FeatureWeight = model.FeatureWeight;
pub const FeatureFlags = model.FeatureFlags;
pub const FeatureID = model.FeatureID;
pub const FeatureDefinition = model.FeatureDefinition;

pub const Registry = registry.Registry;

// ── Runtime fingerprint surface (formerly core/fingerprint) ──

pub const Feature = @import("feature_binding.zig").Feature;
pub const FeatureValue = @import("value.zig").FeatureValue;
pub const Fingerprint = @import("fingerprint.zig").Fingerprint;
pub const FingerprintMetadata = @import("metadata.zig").FingerprintMetadata;

/// An ordered slice of Feature values, typically indexed by FeatureID.
/// This is a type alias rather than a newtype to let consumers control
/// allocation strategy (stack buffer, arena, or heap).
pub const FeatureCollection = []const Feature;
