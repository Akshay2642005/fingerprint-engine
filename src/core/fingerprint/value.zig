const FeatureType = @import("../features/model.zig").FeatureType;

/// A tagged union representing the value of a single browser feature.
///
/// Each variant corresponds to one of the `FeatureType` enum variants.
/// The field names MUST match the FeatureType variant names exactly
/// because the union is indexed by the enum.
///
/// This type is central to the runtime model — it's the payload carried
/// by every `Feature` in a `Fingerprint`. The tagged union design ensures
/// that the value's type tag is always correct at compile time and that
/// no heap allocation is required for construction.
pub const FeatureValue = union(FeatureType) {
    Boolean: bool,
    Integer: i64,
    Float: f64,
    String: []const u8,
    Bytes: []const u8,
    StringArray: []const []const u8,
    IntegerArray: []const i64,
    FloatArray: []const f64,
    BytesArray: []const []const u8,

    /// Returns the `FeatureType` tag corresponding to the active variant.
    /// This is a zero-cost cast since the union is already tagged.
    pub fn valueType(self: FeatureValue) FeatureType {
        return @as(FeatureType, self);
    }
};
