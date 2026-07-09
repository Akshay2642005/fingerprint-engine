const std = @import("std");
const testing = std.testing;
const features = @import("core").features;

// ──────────────────────────────────────────────
// FeatureCategory
// ──────────────────────────────────────────────

test "FeatureCategory enum size is u8 (1 byte)" {
    try testing.expectEqual(@sizeOf(features.FeatureCategory), @as(usize, 1));
}

test "FeatureCategory has 15 variants in expected order" {
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
    try testing.expectEqual(@intFromEnum(features.FeatureCategory.Metadata), 14);
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
// FeatureWeight
// ──────────────────────────────────────────────

test "FeatureWeight is u8" {
    try testing.expectEqual(features.FeatureWeight, u8);
}

test "FeatureWeight accepts values 0-255" {
    const zero: features.FeatureWeight = 0;
    const max: features.FeatureWeight = 255;
    try testing.expectEqual(zero, @as(u8, 0));
    try testing.expectEqual(max, @as(u8, 255));
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

test "FeatureFlags bits are mutually independent" {
    var flags = features.FeatureFlags{};
    flags.stable = true;
    try testing.expect(flags.stable);
    try testing.expect(!flags.high_entropy);
    try testing.expect(!flags.required);
    try testing.expect(!flags.sensitive);

    flags = features.FeatureFlags{};
    flags.high_entropy = true;
    try testing.expect(!flags.stable);
    try testing.expect(flags.high_entropy);
    try testing.expect(!flags.required);
    try testing.expect(!flags.sensitive);

    flags = features.FeatureFlags{};
    flags.required = true;
    try testing.expect(!flags.stable);
    try testing.expect(!flags.high_entropy);
    try testing.expect(flags.required);
    try testing.expect(!flags.sensitive);

    flags = features.FeatureFlags{};
    flags.sensitive = true;
    try testing.expect(!flags.stable);
    try testing.expect(!flags.high_entropy);
    try testing.expect(!flags.required);
    try testing.expect(flags.sensitive);
}

test "FeatureFlags bitwise representation matches expected values" {
    // stable=bit0, high_entropy=bit1, required=bit2, sensitive=bit3
    try testing.expectEqual(@as(u8, 0b0000_0001), @as(u8, @bitCast(features.FeatureFlags{ .stable = true })));
    try testing.expectEqual(@as(u8, 0b0000_0010), @as(u8, @bitCast(features.FeatureFlags{ .high_entropy = true })));
    try testing.expectEqual(@as(u8, 0b0000_0100), @as(u8, @bitCast(features.FeatureFlags{ .required = true })));
    try testing.expectEqual(@as(u8, 0b0000_1000), @as(u8, @bitCast(features.FeatureFlags{ .sensitive = true })));
    try testing.expectEqual(@as(u8, 0b0000_0111), @as(u8, @bitCast(features.FeatureFlags.critical)));
}

// ──────────────────────────────────────────────
// FeatureID
// ──────────────────────────────────────────────

test "FeatureID enum size is u16 (2 bytes)" {
    try testing.expectEqual(@sizeOf(features.FeatureID), @as(usize, 2));
}

test "FeatureID.Count equals total number of variants (37)" {
    try testing.expectEqual(@intFromEnum(features.FeatureID.Count), 37);
}

test "FeatureID first variant is UserAgent (index 0)" {
    try testing.expectEqual(@intFromEnum(features.FeatureID.UserAgent), 0);
}

test "FeatureID last data variant is CollectionTimestamp (index 36)" {
    try testing.expectEqual(@intFromEnum(features.FeatureID.CollectionTimestamp), 36);
}

test "FeatureID counts start at 0 and are sequential" {
    // Spot-check a range of values to ensure no gaps
    try testing.expectEqual(@intFromEnum(features.FeatureID.UserAgent), 0);
    try testing.expectEqual(@intFromEnum(features.FeatureID.Language), 1);
    try testing.expectEqual(@intFromEnum(features.FeatureID.Languages), 2);
    try testing.expectEqual(@intFromEnum(features.FeatureID.Platform), 3);
    try testing.expectEqual(@intFromEnum(features.FeatureID.Vendor), 4);
    try testing.expectEqual(@intFromEnum(features.FeatureID.CookieEnabled), 5);
    try testing.expectEqual(@intFromEnum(features.FeatureID.HardwareConcurrency), 6);
    try testing.expectEqual(@intFromEnum(features.FeatureID.DeviceMemory), 7);
    try testing.expectEqual(@intFromEnum(features.FeatureID.ScreenWidth), 8);
    try testing.expectEqual(@intFromEnum(features.FeatureID.ScreenHeight), 9);
    try testing.expectEqual(@intFromEnum(features.FeatureID.AvailableWidth), 10);
    try testing.expectEqual(@intFromEnum(features.FeatureID.AvailableHeight), 11);
    try testing.expectEqual(@intFromEnum(features.FeatureID.ColorDepth), 12);
    try testing.expectEqual(@intFromEnum(features.FeatureID.PixelDepth), 13);
    try testing.expectEqual(@intFromEnum(features.FeatureID.DevicePixelRatio), 14);
    try testing.expectEqual(@intFromEnum(features.FeatureID.CanvasHash), 15);
    try testing.expectEqual(@intFromEnum(features.FeatureID.WebGLVendor), 16);
    try testing.expectEqual(@intFromEnum(features.FeatureID.WebGLRenderer), 17);
    try testing.expectEqual(@intFromEnum(features.FeatureID.WebGLVersion), 18);
    try testing.expectEqual(@intFromEnum(features.FeatureID.WebGLHash), 19);
    try testing.expectEqual(@intFromEnum(features.FeatureID.AudioHash), 20);
    try testing.expectEqual(@intFromEnum(features.FeatureID.FontsHash), 21);
    try testing.expectEqual(@intFromEnum(features.FeatureID.CpuClass), 22);
    try testing.expectEqual(@intFromEnum(features.FeatureID.OperatingSystem), 23);
    try testing.expectEqual(@intFromEnum(features.FeatureID.LocalStorage), 24);
    try testing.expectEqual(@intFromEnum(features.FeatureID.SessionStorage), 25);
    try testing.expectEqual(@intFromEnum(features.FeatureID.IndexedDB), 26);
    try testing.expectEqual(@intFromEnum(features.FeatureID.NotificationPermission), 27);
    try testing.expectEqual(@intFromEnum(features.FeatureID.AudioInputDevices), 28);
    try testing.expectEqual(@intFromEnum(features.FeatureID.AudioOutputDevices), 29);
    try testing.expectEqual(@intFromEnum(features.FeatureID.VideoInputDevices), 30);
    try testing.expectEqual(@intFromEnum(features.FeatureID.ConnectionType), 31);
    try testing.expectEqual(@intFromEnum(features.FeatureID.Locale), 32);
    try testing.expectEqual(@intFromEnum(features.FeatureID.Timezone), 33);
    try testing.expectEqual(@intFromEnum(features.FeatureID.SchemaVersion), 34);
    try testing.expectEqual(@intFromEnum(features.FeatureID.SDKVersion), 35);
    try testing.expectEqual(@intFromEnum(features.FeatureID.CollectionTimestamp), 36);
    try testing.expectEqual(@intFromEnum(features.FeatureID.Count), 37);
}

test "FeatureID metadata variants exist" {
    // These are required to compile — verifies all variants are valid
    _ = features.FeatureID.SchemaVersion;
    _ = features.FeatureID.SDKVersion;
    _ = features.FeatureID.CollectionTimestamp;
}

test "FeatureID navigator variants exist" {
    _ = features.FeatureID.UserAgent;
    _ = features.FeatureID.Language;
    _ = features.FeatureID.Languages;
    _ = features.FeatureID.Platform;
    _ = features.FeatureID.Vendor;
    _ = features.FeatureID.CookieEnabled;
}

test "FeatureID hardware variants exist" {
    _ = features.FeatureID.HardwareConcurrency;
    _ = features.FeatureID.DeviceMemory;
    _ = features.FeatureID.CpuClass;
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

// ──────────────────────────────────────────────
// FeatureDefinition
// ──────────────────────────────────────────────

test "FeatureDefinition struct size is reasonable" {
    // Two u16s, one u8, one FeatureFlags(u8), two slices (~32 bytes on 64-bit)
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

test "FeatureDefinition isRequired returns flags.required" {
    const def = features.FeatureDefinition{
        .id = features.FeatureID.Language,
        .category = features.FeatureCategory.Navigator,
        .value_type = features.FeatureType.String,
        .weight = 40,
        .flags = features.FeatureFlags{ .required = true },
        .name = "Required Test",
        .description = "",
    };
    try testing.expect(def.isRequired());
    try testing.expect(!def.isStable());
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
        .weight = 30,
        .flags = features.FeatureFlags.none,
        .name = name,
        .description = desc,
    };
    try testing.expectEqualStrings(name, def.name);
    try testing.expectEqualStrings(desc, def.description);
}
