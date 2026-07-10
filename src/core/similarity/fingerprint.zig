const std = @import("std");
const features = @import("../features/root.zig");
const fingerprint = @import("../fingerprint/root.zig");
const similarity = @import("root.zig");

const Feature = fingerprint.Feature;
const Fingerprint = fingerprint.Fingerprint;
const FeatureID = features.FeatureID;
const Registry = features.Registry;

/// Computes the weighted similarity score between two fingerprints (0.0 — completely different, 1.0 — identical).
///
/// For each feature present in both fingerprints:
///   weighted_score += featureScore(a.value, b.value) × featureWeight
/// Final score = weighted_score / total_weight_of_compared_features
///
/// Features present in only one fingerprint contribute 0 to the score.
/// Features present in neither are ignored.
pub fn fingerprintScore(a: Fingerprint, b: Fingerprint) f64 {
    var weighted_sum: f64 = 0.0;
    var total_weight: f64 = 0.0;

    for (a.features) |feat_a| {
        // Find matching feature in b
        const feat_b = findFeatureById(b.features, feat_a.id) orelse continue;
        const weight = @as(f64, @floatFromInt(Registry.get(feat_a.id).weight));
        weighted_sum += similarity.featureScore(feat_a.value, feat_b.value) * weight;
        total_weight += weight;
    }

    if (total_weight == 0.0) return 0.0;
    return weighted_sum / total_weight;
}

fn findFeatureById(feat_list: []const Feature, id: FeatureID) ?Feature {
    for (feat_list) |feat| {
        if (feat.id == id) return feat;
    }
    return null;
}
