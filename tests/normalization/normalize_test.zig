const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;
const normalization = @import("core").normalization;

test "normalize returns zero warnings for clean fingerprint" {
    const fp = fingerprint.Fingerprint{
        .metadata = .{
            .schema_version = 1,
            .sdk_version = "0.1.0",
            .collected_at = 0,
        },
        .features = &.{
            fingerprint.Feature{ .id = .CookieEnabled, .value = fingerprint.FeatureValue{ .Boolean = true } },
            fingerprint.Feature{ .id = .UserAgent, .value = fingerprint.FeatureValue{ .String = "Mozilla/5.0" } },
            fingerprint.Feature{ .id = .HardwareConcurrency, .value = fingerprint.FeatureValue{ .Integer = 8 } },
        },
    };

    const warnings = try normalization.normalize(fp, testing.allocator);
    defer testing.allocator.free(warnings);

    try testing.expectEqual(@as(usize, 0), warnings.len);
}

test "normalize catches type mismatch and bound violation" {
    const fp = fingerprint.Fingerprint{
        .metadata = .{
            .schema_version = 1,
            .sdk_version = "0.1.0",
            .collected_at = 0,
        },
        .features = &.{
            // Type mismatch: CookieEnabled should be Boolean
            fingerprint.Feature{ .id = .CookieEnabled, .value = fingerprint.FeatureValue{ .String = "true" } },
            // Bound violation: HardwareConcurrency of 0 is too low
            fingerprint.Feature{ .id = .HardwareConcurrency, .value = fingerprint.FeatureValue{ .Integer = 0 } },
        },
    };

    const warnings = try normalization.normalize(fp, testing.allocator);
    defer testing.allocator.free(warnings);

    try testing.expect(warnings.len >= 2);
}
