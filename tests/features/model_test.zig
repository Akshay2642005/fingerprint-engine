const std = @import("std");
const testing = std.testing;
const features = @import("core").features;

// ──────────────────────────────────────────────
// FeatureCategory
// ──────────────────────────────────────────────

test "FeatureCategory enum size is u8 (1 byte)" {
    try testing.expectEqual(@sizeOf(features.FeatureCategory), @as(usize, 1));
}

test "FeatureCategory has 21 variants in expected order" {
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Navigator), 0);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Screen), 1);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Canvas), 2);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.WebGL), 3);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Audio), 4);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Fonts), 5);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Hardware), 6);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Platform), 7);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Storage), 8);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Permissions), 9);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Media), 10);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Network), 11);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Locale), 12);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Timezone), 13);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Battery), 14);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.MediaCapabilities), 15);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Crypto), 16);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Speech), 17);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.GPU), 18);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Performance), 19);
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Metadata), 20);
}

// ──────────────────────────────────────────────
// FeatureType
// ──────────────────────────────────────────────

test "FeatureType enum size is u8 (1 byte)" {
    try testing.expectEqual(@sizeOf(features.FeatureType), @as(usize, 1));
}

test "FeatureType has 9 variants in expected order" {
    try testing.expectEqual(@intFromEnum(features.FeatureType.Boolean), 0);
    try testing.expectEqual(@intFromEnum(features.FeatureType.Integer), 1);
    try testing.expectEqual(@intFromEnum(features.FeatureType.Float), 2);
    try testing.expectEqual(@intFromEnum(features.FeatureType.String), 3);
    try testing.expectEqual(@intFromEnum(features.FeatureType.Bytes), 4);
    try testing.expectEqual(@intFromEnum(features.FeatureType.StringArray), 5);
    try testing.expectEqual(@intFromEnum(features.FeatureType.IntegerArray), 6);
    try testing.expectEqual(@intFromEnum(features.FeatureType.FloatArray), 7);
    try testing.expectEqual(@intFromEnum(features.FeatureType.BytesArray), 8);
}

// ──────────────────────────────────────────────
// FeatureID
// ──────────────────────────────────────────────

test "FeatureID enum size is u16 (2 bytes)" {
    try testing.expectEqual(@sizeOf(features.FeatureID), @as(usize, 2));
}

test "FeatureID.Count equals total number of variants (102)" {
    try testing.expectEqual(@intFromEnum(features.FeatureID.Count), 102);
}

test "FeatureID first variant is UserAgent (index 0)" {
    try testing.expectEqual(@intFromEnum(features.FeatureID.UserAgent), 0);
}

test "FeatureID last data variant is CollectionTimestamp (index 101)" {
    try testing.expectEqual(@intFromEnum(features.FeatureID.CollectionTimestamp), 101);
}

test "FeatureID counts start at 0 and are sequential" {
    // Navigator
    try testing.expectEqual(@intFromEnum(features.FeatureID.UserAgent), 0);
    try testing.expectEqual(@intFromEnum(features.FeatureID.Language), 1);
    try testing.expectEqual(@intFromEnum(features.FeatureID.Languages), 2);
    try testing.expectEqual(@intFromEnum(features.FeatureID.Platform), 3);
    try testing.expectEqual(@intFromEnum(features.FeatureID.Vendor), 4);
    try testing.expectEqual(@intFromEnum(features.FeatureID.Product), 5);
    try testing.expectEqual(@intFromEnum(features.FeatureID.ProductSub), 6);
    try testing.expectEqual(@intFromEnum(features.FeatureID.AppName), 7);
    try testing.expectEqual(@intFromEnum(features.FeatureID.AppVersion), 8);
    try testing.expectEqual(@intFromEnum(features.FeatureID.CookieEnabled), 9);
    try testing.expectEqual(@intFromEnum(features.FeatureID.DoNotTrack), 10);
    try testing.expectEqual(@intFromEnum(features.FeatureID.HardwareConcurrency), 11);
    try testing.expectEqual(@intFromEnum(features.FeatureID.MaxTouchPoints), 12);
    try testing.expectEqual(@intFromEnum(features.FeatureID.DeviceMemory), 13);
    try testing.expectEqual(@intFromEnum(features.FeatureID.PdfViewerEnabled), 14);
    try testing.expectEqual(@intFromEnum(features.FeatureID.VendorSub), 15);
    try testing.expectEqual(@intFromEnum(features.FeatureID.DeviceRam), 16);
    // Screen
    try testing.expectEqual(@intFromEnum(features.FeatureID.ScreenWidth), 17);
    try testing.expectEqual(@intFromEnum(features.FeatureID.ScreenHeight), 18);
    // Hardware
    try testing.expectEqual(@intFromEnum(features.FeatureID.CpuClass), 29);
    // Canvas
    try testing.expectEqual(@intFromEnum(features.FeatureID.CanvasHash), 35);
    // WebGL
    try testing.expectEqual(@intFromEnum(features.FeatureID.WebGLVendor), 36);
    try testing.expectEqual(@intFromEnum(features.FeatureID.WebGLRenderer), 37);
    // Platform
    try testing.expectEqual(@intFromEnum(features.FeatureID.OperatingSystem), 45);
    // Storage
    try testing.expectEqual(@intFromEnum(features.FeatureID.LocalStorage), 47);
    // Metadata
    try testing.expectEqual(@intFromEnum(features.FeatureID.SchemaVersion), 99);
    try testing.expectEqual(@intFromEnum(features.FeatureID.SDKVersion), 100);
    try testing.expectEqual(@intFromEnum(features.FeatureID.CollectionTimestamp), 101);
}

test "FeatureID navigator variants exist" {
    _ = features.FeatureID.UserAgent;
    _ = features.FeatureID.Language;
    _ = features.FeatureID.Languages;
    _ = features.FeatureID.Platform;
    _ = features.FeatureID.Vendor;
    _ = features.FeatureID.CookieEnabled;
    _ = features.FeatureID.HardwareConcurrency;
}

test "FeatureID screen variants exist" {
    _ = features.FeatureID.ScreenWidth;
    _ = features.FeatureID.ScreenHeight;
    _ = features.FeatureID.AvailableWidth;
    _ = features.FeatureID.AvailableHeight;
    _ = features.FeatureID.ColorDepth;
    _ = features.FeatureID.PixelDepth;
    _ = features.FeatureID.DevicePixelRatio;
}

test "FeatureID canvas and webgl variants exist" {
    _ = features.FeatureID.CanvasHash;
    _ = features.FeatureID.WebGLVendor;
    _ = features.FeatureID.WebGLRenderer;
    _ = features.FeatureID.WebGLVersion;
    _ = features.FeatureID.WebGLHash;
}

test "FeatureID audio and fonts variants exist" {
    _ = features.FeatureID.AudioHash;
    _ = features.FeatureID.FontsHash;
}

test "FeatureID storage variants exist" {
    _ = features.FeatureID.LocalStorage;
    _ = features.FeatureID.SessionStorage;
    _ = features.FeatureID.IndexedDB;
}

test "FeatureID permission variants exist" {
    _ = features.FeatureID.NotificationPermission;
}

test "FeatureID media variants exist" {
    _ = features.FeatureID.AudioInputDevices;
    _ = features.FeatureID.AudioOutputDevices;
    _ = features.FeatureID.VideoInputDevices;
}

test "FeatureID network variant exists" {
    _ = features.FeatureID.ConnectionType;
}

test "FeatureID locale and timezone variants exist" {
    _ = features.FeatureID.Locale;
    _ = features.FeatureID.Timezone;
}

test "FeatureID operating system variant exists" {
    _ = features.FeatureID.OperatingSystem;
}

test "FeatureID battery variants exist" {
    _ = features.FeatureID.BatteryLevel;
    _ = features.FeatureID.BatteryCharging;
    _ = features.FeatureID.BatteryChargingTime;
}

test "FeatureID crypto variants exist" {
    _ = features.FeatureID.CryptoSupport;
    _ = features.FeatureID.SubtleCrypto;
}

test "FeatureID GPU variants exist" {
    _ = features.FeatureID.GPUVendor;
    _ = features.FeatureID.GPURenderer;
    _ = features.FeatureID.GPUDriverVersion;
}

test "FeatureID metadata variants exist" {
    _ = features.FeatureID.SchemaVersion;
    _ = features.FeatureID.SDKVersion;
    _ = features.FeatureID.CollectionTimestamp;
}

// ──────────────────────────────────────────────
// FeatureFlags
// ──────────────────────────────────────────────

test "FeatureFlags packed struct size is u8 (1 byte)" {
    try testing.expectEqual(@sizeOf(features.FeatureFlags), @as(usize, 1));
}

test "FeatureFlags default is all false" {
    const flags = features.FeatureFlags{};
    try testing.expect(!flags.stable);
    try testing.expect(!flags.high_entropy);
    try testing.expect(!flags.required);
    try testing.expect(!flags.sensitive);
}

test "FeatureFlags.none has all bits clear" {
    try testing.expectEqual(@as(u8, @bitCast(features.FeatureFlags.none)), @as(u8, 0));
}

test "FeatureFlags.stable_required sets stable and required only" {
    const sr = features.FeatureFlags.stable_required;
    try testing.expect(sr.stable);
    try testing.expect(sr.required);
    try testing.expect(!sr.high_entropy);
    try testing.expect(!sr.sensitive);
}

test "FeatureFlags.stable_entropy sets stable and high_entropy only" {
    const se = features.FeatureFlags.stable_entropy;
    try testing.expect(se.stable);
    try testing.expect(se.high_entropy);
    try testing.expect(!se.required);
    try testing.expect(!se.sensitive);
}

test "FeatureFlags.required_entropy sets required and high_entropy only" {
    const re = features.FeatureFlags.required_entropy;
    try testing.expect(re.required);
    try testing.expect(re.high_entropy);
    try testing.expect(!re.stable);
    try testing.expect(!re.sensitive);
}

test "FeatureFlags.critical sets stable, required, and high_entropy" {
    const c = features.FeatureFlags.critical;
    try testing.expect(c.stable);
    try testing.expect(c.required);
    try testing.expect(c.high_entropy);
    try testing.expect(!c.sensitive);
}

// ──────────────────────────────────────────────
// FeatureDefinition
// ──────────────────────────────────────────────

test "FeatureDefinition struct size is reasonable" {
    const size = @sizeOf(features.FeatureDefinition);
    try testing.expect(size <= 64);
}

test "FeatureDefinition can be constructed and read" {
    const def = features.FeatureDefinition{
        .id = features.FeatureID.UserAgent,
        .category = features.FeatureCategory.Navigator,
        .value_type = features.FeatureType.String,
        .weight = 50,
        .flags = features.FeatureFlags.stable_required,
        .name = "Test Feature",
        .description = "A test feature definition.",
    };
    try testing.expectEqual(def.id, features.FeatureID.UserAgent);
    try testing.expectEqual(def.category, features.FeatureCategory.Navigator);
    try testing.expectEqual(def.value_type, features.FeatureType.String);
    try testing.expectEqual(def.weight, @as(features.FeatureWeight, 50));
}

test "FeatureDefinition isStable returns flags.stable" {
    const def = features.FeatureDefinition{
        .id = features.FeatureID.UserAgent,
        .category = features.FeatureCategory.Navigator,
        .value_type = features.FeatureType.String,
        .weight = 50,
        .flags = features.FeatureFlags{ .stable = true },
        .name = "Stable Test",
        .description = "",
    };
    try testing.expect(def.isStable());
    try testing.expect(!def.isRequired());
    try testing.expect(!def.isHighEntropy());
    try testing.expect(!def.isSensitive());
}

test "FeatureDefinition isHighEntropy returns flags.high_entropy" {
    const def = features.FeatureDefinition{
        .id = features.FeatureID.WebGLVendor,
        .category = features.FeatureCategory.WebGL,
        .value_type = features.FeatureType.String,
        .weight = 80,
        .flags = features.FeatureFlags{ .high_entropy = true },
        .name = "Entropy Test",
        .description = "",
    };
    try testing.expect(def.isHighEntropy());
    try testing.expect(!def.isStable());
    try testing.expect(!def.isRequired());
    try testing.expect(!def.isSensitive());
}

test "FeatureDefinition isSensitive returns flags.sensitive" {
    const def = features.FeatureDefinition{
        .id = features.FeatureID.AudioHash,
        .category = features.FeatureCategory.Audio,
        .value_type = features.FeatureType.Bytes,
        .weight = 90,
        .flags = features.FeatureFlags{ .sensitive = true },
        .name = "Sensitive Test",
        .description = "",
    };
    try testing.expect(def.isSensitive());
    try testing.expect(!def.isStable());
    try testing.expect(!def.isRequired());
    try testing.expect(!def.isHighEntropy());
}

test "FeatureDefinition can use named flag constants" {
    const critical = features.FeatureDefinition{
        .id = features.FeatureID.CanvasHash,
        .category = features.FeatureCategory.Canvas,
        .value_type = features.FeatureType.Bytes,
        .weight = 100,
        .flags = features.FeatureFlags.critical,
        .name = "Critical",
        .description = "",
    };
    try testing.expect(critical.isStable());
    try testing.expect(critical.isRequired());
    try testing.expect(critical.isHighEntropy());
    try testing.expect(!critical.isSensitive());
}

test "FeatureDefinition zero weight is valid" {
    const def = features.FeatureDefinition{
        .id = features.FeatureID.SchemaVersion,
        .category = features.FeatureCategory.Metadata,
        .value_type = features.FeatureType.Integer,
        .weight = 0,
        .flags = features.FeatureFlags{ .required = true },
        .name = "Zero Weight",
        .description = "Feature with zero weight.",
    };
    try testing.expectEqual(def.weight, 0);
}

test "FeatureDefinition max weight is valid" {
    const def = features.FeatureDefinition{
        .id = features.FeatureID.SDKVersion,
        .category = features.FeatureCategory.Metadata,
        .value_type = features.FeatureType.String,
        .weight = 255,
        .flags = features.FeatureFlags.none,
        .name = "Max Weight",
        .description = "Feature with maximum weight.",
    };
    try testing.expectEqual(def.weight, 255);
}

test "FeatureDefinition name and description are stored verbatim" {
    const name = "Custom Feature Name";
    const desc = "A feature with a custom name and longer description for testing.";
    const def = features.FeatureDefinition{
        .id = features.FeatureID.ConnectionType,
        .category = features.FeatureCategory.Network,
        .value_type = features.FeatureType.String,
        .weight = 45,
        .flags = features.FeatureFlags{ .stable = true },
        .name = name,
        .description = desc,
    };
    try testing.expectEqualStrings(name, def.name);
    try testing.expectEqualStrings(desc, def.description);
}
