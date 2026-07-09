const FeatureID = @import("../features/id.zig").FeatureID;
const FeatureValue = @import("value.zig").FeatureValue;

pub const Feature = struct {
    id: FeatureID,
    value: FeatureValue,
};
