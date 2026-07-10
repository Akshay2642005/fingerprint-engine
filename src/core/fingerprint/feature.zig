const FeatureID = @import("../features/model.zig").FeatureID;
const FeatureValue = @import("value.zig").FeatureValue;

/// A runtime feature binding: a FeatureID with its collected value.
/// This is the unit of data in a FeatureCollection.
pub const Feature = struct {
    id: FeatureID,
    value: FeatureValue,
};
