const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;
const validation = @import("core").validation;

test "checkRequired finds all required features present" {
    // Build a fingerprint with ALL required features present
    const Registry = features.Registry;
    var all_features: [Registry.count()]fingerprint.Feature = undefined;
    var count: usize = 0;
    for (Registry.all()) |def| {
        // Only add features that are flagged as required
        if (def.flags.required) {
            // Use a dummy value of the correct type
            const val = switch (def.value_type) {
                .Boolean => fingerprint.FeatureValue{ .Boolean = true },
                .Integer => fingerprint.FeatureValue{ .Integer = 1 },
                .Float => fingerprint.FeatureValue{ .Float = 1.0 },
                .String => fingerprint.FeatureValue{ .String = "test" },
                .Bytes => fingerprint.FeatureValue{ .Bytes = &[_]u8{0} },
                .StringArray => fingerprint.FeatureValue{ .StringArray = &[_][]const u8{"test"} },
                .IntegerArray => fingerprint.FeatureValue{ .IntegerArray = &[_]i64{1} },
                .FloatArray => fingerprint.FeatureValue{ .FloatArray = &[_]f64{1.0} },
                .BytesArray => fingerprint.FeatureValue{ .BytesArray = &[_][]const u8{&[_]u8{0}} },
            };
            all_features[count] = fingerprint.Feature{ .id = def.id, .value = val };
            count += 1;
        }
    }

    const fp = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = all_features[0..count],
    };

    const warnings = try validation.checkRequired(fp, testing.allocator);
    defer testing.allocator.free(warnings);
    try testing.expectEqual(@as(usize, 0), warnings.len);
}

test "checkRequired detects single missing required feature" {
    const fp = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fingerprint.FeatureValue{ .Boolean = true } },
        },
    };

    const warnings = try validation.checkRequired(fp, testing.allocator);
    defer testing.allocator.free(warnings);
    // CookieEnabled is required but there are many other required features missing
    try testing.expect(warnings.len > 1);
}

test "checkRequired empty fingerprint has many warnings" {
    const fp = fingerprint.Fingerprint{
        .metadata = .{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 0 },
        .features = &.{},
    };

    const warnings = try validation.checkRequired(fp, testing.allocator);
    defer testing.allocator.free(warnings);
    try testing.expect(warnings.len > 0);
}
