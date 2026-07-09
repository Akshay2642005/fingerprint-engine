const features = @import("core").features;

/// Returns a sample FeatureDefinition for testing purposes.
pub fn sampleFeatureDefinition() features.FeatureDefinition {
    return features.FeatureDefinition{
        .id = features.FeatureID.UserAgent,
        .category = features.FeatureCategory.Navigator,
        .value_type = features.FeatureType.String,
        .weight = 50,
        .flags = features.FeatureFlags.stable_required,
        .name = "Test Feature",
        .description = "A test feature for unit testing.",
    };
}

/// Returns a critical FeatureDefinition for testing.
pub fn sampleCriticalDefinition() features.FeatureDefinition {
    return features.FeatureDefinition{
        .id = features.FeatureID.CanvasHash,
        .category = features.FeatureCategory.Canvas,
        .value_type = features.FeatureType.Bytes,
        .weight = 100,
        .flags = features.FeatureFlags.critical,
        .name = "Critical Feature",
        .description = "A critical feature for unit testing.",
    };
}
