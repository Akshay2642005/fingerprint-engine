const features = @import("core").features;

/// A mock registry adapter for testing definition queries.
/// Wraps the real Registry for scenarios that need test-specific helpers.
pub const MockRegistry = struct {
    /// Returns the count of definitions in a given category.
    pub fn countByCategory(category: features.FeatureCategory) usize {
        var count: usize = 0;
        for (features.Registry.all()) |def| {
            if (def.category == category) count += 1;
        }
        return count;
    }
};
