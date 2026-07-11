const std = @import("std");
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;

const FeatureValue = fingerprint.FeatureValue;
const Feature = fingerprint.Feature;
const Fingerprint = fingerprint.Fingerprint;
const FeatureID = features.FeatureID;

/// Helper to quickly build a Feature with a boolean value.
pub fn boolFeature(id: FeatureID, value: bool) Feature {
    return Feature{ .id = id, .value = FeatureValue{ .Boolean = value } };
}

/// Helper to quickly build a Feature with an integer value.
pub fn intFeature(id: FeatureID, value: i64) Feature {
    return Feature{ .id = id, .value = FeatureValue{ .Integer = value } };
}

/// Helper to quickly build a Feature with a float value.
pub fn floatFeature(id: FeatureID, value: f64) Feature {
    return Feature{ .id = id, .value = FeatureValue{ .Float = value } };
}

/// Helper to quickly build a Feature with a string value.
pub fn stringFeature(id: FeatureID, value: []const u8) Feature {
    return Feature{ .id = id, .value = FeatureValue{ .String = value } };
}

/// Helper to quickly build a Feature with a bytes value.
pub fn bytesFeature(id: FeatureID, value: []const u8) Feature {
    return Feature{ .id = id, .value = FeatureValue{ .Bytes = value } };
}

/// Helper to quickly build a Feature with a string array value.
pub fn stringArrayFeature(id: FeatureID, value: []const []const u8) Feature {
    return Feature{ .id = id, .value = FeatureValue{ .StringArray = value } };
}

/// Helper to quickly build a Feature with an integer array value.
pub fn intArrayFeature(id: FeatureID, value: []const i64) Feature {
    return Feature{ .id = id, .value = FeatureValue{ .IntegerArray = value } };
}

/// Helper to quickly build a Feature with a float array value.
pub fn floatArrayFeature(id: FeatureID, value: []const f64) Feature {
    return Feature{ .id = id, .value = FeatureValue{ .FloatArray = value } };
}

/// Creates a default fingerprint metadata for testing.
pub fn defaultMetadata() fingerprint.FingerprintMetadata {
    return .{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    };
}

/// Creates a simple fingerprint from a list of features.
/// WARNING: feats must outlive the returned Fingerprint (the caller is responsible
/// for the backing storage).
pub fn makeFingerprint(feats: []const Feature) Fingerprint {
    return Fingerprint{
        .metadata = defaultMetadata(),
        .features = feats,
    };
}

/// Creates an empty fingerprint (no features).
pub fn emptyFingerprint() Fingerprint {
    return Fingerprint{
        .metadata = defaultMetadata(),
        .features = &.{},
    };
}
