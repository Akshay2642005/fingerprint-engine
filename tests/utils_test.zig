const std = @import("std");
const testing = std.testing;
const test_utils = @import("test_utils");
const builders = test_utils.builders;
const generators = test_utils.generators;
const assertions = test_utils.assertions;
const mocks = test_utils.mocks;
const features = @import("core").features;
const fingerprint = @import("core").fingerprint;

test "builders: boolFeature creates correct feature" {
    const f = builders.boolFeature(.CookieEnabled, true);
    try testing.expectEqual(features.FeatureID.CookieEnabled, f.id);
    try testing.expectEqual(fingerprint.FeatureValue{ .Boolean = true }, f.value);
}

test "builders: intFeature creates correct feature" {
    const f = builders.intFeature(.HardwareConcurrency, 8);
    try testing.expectEqual(features.FeatureID.HardwareConcurrency, f.id);
    try testing.expectEqual(fingerprint.FeatureValue{ .Integer = 8 }, f.value);
}

test "builders: stringFeature creates correct feature" {
    const f = builders.stringFeature(.UserAgent, "Mozilla/5.0");
    try testing.expectEqual(features.FeatureID.UserAgent, f.id);
    try testing.expectEqualStrings("Mozilla/5.0", f.value.String);
}

test "builders: bytesFeature creates correct feature" {
    const data = [_]u8{ 0x01, 0x02, 0x03 };
    const f = builders.bytesFeature(.CanvasHash, &data);
    try testing.expectEqual(features.FeatureID.CanvasHash, f.id);
    try testing.expectEqualSlices(u8, &data, f.value.Bytes);
}

test "builders: stringArrayFeature creates correct feature" {
    const langs = [_][]const u8{ "en-US", "zh-CN" };
    const f = builders.stringArrayFeature(.Languages, &langs);
    try testing.expectEqual(features.FeatureID.Languages, f.id);
    try testing.expectEqual(@as(usize, 2), f.value.StringArray.len);
    try testing.expectEqualStrings("en-US", f.value.StringArray[0]);
}

test "builders: makeFingerprint creates valid fingerprint" {
    const f = builders.makeFingerprint(&.{
        builders.boolFeature(.CookieEnabled, true),
        builders.stringFeature(.UserAgent, "test"),
    });
    try testing.expectEqual(@as(usize, 2), f.features.len);
    try testing.expectEqual(@as(u16, 1), f.metadata.schema_version);
}

test "builders: singleBoolFingerprint" {
    const feats = [_]fingerprint.Feature{
        builders.boolFeature(.CookieEnabled, true),
    };
    const fp = builders.makeFingerprint(&feats);
    try testing.expectEqual(@as(usize, 1), fp.features.len);
    try testing.expectEqual(@as(u16, @intFromEnum(features.FeatureID.CookieEnabled)), @intFromEnum(fp.features[0].id));
}

test "builders: emptyFingerprint" {
    const fp = builders.emptyFingerprint();
    try testing.expectEqual(@as(usize, 0), fp.features.len);
}

test "generators: sampleFeatureDefinition" {
    const def = generators.sampleFeatureDefinition();
    try testing.expectEqual(features.FeatureID.UserAgent, def.id);
    try testing.expectEqual(features.FeatureCategory.Navigator, def.category);
}

test "generators: sampleCriticalDefinition" {
    const def = generators.sampleCriticalDefinition();
    try testing.expectEqual(features.FeatureID.CanvasHash, def.id);
    try testing.expectEqual(features.FeatureCategory.Canvas, def.category);
    try testing.expectEqual(@as(u8, 100), def.weight);
}

test "assertions: expectFlags" {
    try assertions.expectFlags(
        features.FeatureFlags.stable_required,
        true,
        false,
        true,
        false,
    );
}

test "mocks: MockRegistry countByCategory" {
    const nav_count = mocks.MockRegistry.countByCategory(features.FeatureCategory.Navigator);
    try testing.expect(nav_count > 0);
}

test "builders: cookieAndUaFingerprint" {
    const feats = [_]fingerprint.Feature{
        builders.boolFeature(.CookieEnabled, true),
        builders.stringFeature(.UserAgent, "test-ua"),
    };
    const fp = builders.makeFingerprint(&feats);
    try testing.expectEqual(@as(usize, 2), fp.features.len);
    try testing.expectEqual(@as(u16, @intFromEnum(features.FeatureID.CookieEnabled)), @intFromEnum(fp.features[0].id));
    try testing.expectEqual(@as(u16, @intFromEnum(features.FeatureID.UserAgent)), @intFromEnum(fp.features[1].id));
}

test "builders: navigatorFingerprint builds 6 features" {
    const langs = [_][]const u8{"en"};
    const feats = [_]fingerprint.Feature{
        builders.boolFeature(.CookieEnabled, true),
        builders.stringFeature(.UserAgent, "ua"),
        builders.stringFeature(.Language, "en"),
        builders.stringArrayFeature(.Languages, &langs),
        builders.stringFeature(.Platform, "Win32"),
        builders.intFeature(.HardwareConcurrency, 8),
    };
    const fp = builders.makeFingerprint(&feats);
    try testing.expectEqual(@as(usize, 6), fp.features.len);
}
