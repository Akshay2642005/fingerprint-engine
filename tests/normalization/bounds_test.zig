const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;
const normalization = @import("core").normalization;

test "checkBounds passes valid HardwareConcurrency" {
    const feat = fingerprint.Feature{ .id = .HardwareConcurrency, .value = fingerprint.FeatureValue{ .Integer = 8 } };
    const warnings = try normalization.checkBounds(feat, testing.allocator);
    defer testing.allocator.free(warnings);
    try testing.expectEqual(@as(usize, 0), warnings.len);
}

test "checkBounds flags zero HardwareConcurrency" {
    const feat = fingerprint.Feature{ .id = .HardwareConcurrency, .value = fingerprint.FeatureValue{ .Integer = 0 } };
    const warnings = try normalization.checkBounds(feat, testing.allocator);
    defer testing.allocator.free(warnings);
    try testing.expect(warnings.len > 0);
    try testing.expectEqualStrings("Hardware Concurrency", warnings[0].name);
}

test "checkBounds flags negative screen width" {
    const feat = fingerprint.Feature{ .id = .ScreenWidth, .value = fingerprint.FeatureValue{ .Integer = -1 } };
    const warnings = try normalization.checkBounds(feat, testing.allocator);
    defer testing.allocator.free(warnings);
    try testing.expect(warnings.len > 0);
}

test "checkBounds passes valid DevicePixelRatio" {
    const feat = fingerprint.Feature{ .id = .DevicePixelRatio, .value = fingerprint.FeatureValue{ .Float = 2.0 } };
    const warnings = try normalization.checkBounds(feat, testing.allocator);
    defer testing.allocator.free(warnings);
    try testing.expectEqual(@as(usize, 0), warnings.len);
}

test "checkBounds flags negative DevicePixelRatio" {
    const feat = fingerprint.Feature{ .id = .DevicePixelRatio, .value = fingerprint.FeatureValue{ .Float = -1.0 } };
    const warnings = try normalization.checkBounds(feat, testing.allocator);
    defer testing.allocator.free(warnings);
    try testing.expect(warnings.len > 0);
}

test "checkBounds passes valid UserAgent string" {
    const feat = fingerprint.Feature{ .id = .UserAgent, .value = fingerprint.FeatureValue{ .String = "Mozilla/5.0" } };
    const warnings = try normalization.checkBounds(feat, testing.allocator);
    defer testing.allocator.free(warnings);
    try testing.expectEqual(@as(usize, 0), warnings.len);
}

test "checkBounds flags empty UserAgent" {
    const feat = fingerprint.Feature{ .id = .UserAgent, .value = fingerprint.FeatureValue{ .String = "" } };
    const warnings = try normalization.checkBounds(feat, testing.allocator);
    defer testing.allocator.free(warnings);
    try testing.expect(warnings.len > 0);
}

test "checkBounds passes valid non-empty Bytes" {
    const feat = fingerprint.Feature{ .id = .CanvasHash, .value = fingerprint.FeatureValue{ .Bytes = &[_]u8{ 0x01, 0x02 } } };
    const warnings = try normalization.checkBounds(feat, testing.allocator);
    defer testing.allocator.free(warnings);
    try testing.expectEqual(@as(usize, 0), warnings.len);
}

test "checkBounds flags empty Bytes" {
    const feat = fingerprint.Feature{ .id = .CanvasHash, .value = fingerprint.FeatureValue{ .Bytes = &[_]u8{} } };
    const warnings = try normalization.checkBounds(feat, testing.allocator);
    defer testing.allocator.free(warnings);
    try testing.expect(warnings.len > 0);
}

test "checkBounds flags negative HardwareConcurrency" {
    const feat = fingerprint.Feature{ .id = .HardwareConcurrency, .value = fingerprint.FeatureValue{ .Integer = -4 } };
    const warnings = try normalization.checkBounds(feat, testing.allocator);
    defer testing.allocator.free(warnings);
    try testing.expect(warnings.len > 0);
}

test "checkBounds flags Infinity float" {
    const feat = fingerprint.Feature{ .id = .DevicePixelRatio, .value = fingerprint.FeatureValue{ .Float = std.math.inf(f64) } };
    const warnings = try normalization.checkBounds(feat, testing.allocator);
    defer testing.allocator.free(warnings);
    try testing.expect(warnings.len > 0);
}
