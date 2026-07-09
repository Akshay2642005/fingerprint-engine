const Feature = @import("feature.zig").Feature;
const FingerprintMetadata = @import("metadata.zig").FingerprintMetadata;

/// Complete runtime fingerprint collected from a browser.
///
/// A Fingerprint consists of runtime metadata and the set of collected
/// browser features.
pub const Fingerprint = struct {
    metadata: FingerprintMetadata,
    features: []const Feature,
};
