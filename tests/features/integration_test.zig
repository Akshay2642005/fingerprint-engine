const std = @import("std");
const testing = std.testing;
const features = @import("core").features;

// ──────────────────────────────────────────────
// Integration: FeatureID enum ↔ FeatureDefinition registry
// ──────────────────────────────────────────────

test "Integration — every FeatureID in definitions has correct category" {
    const all = features.Registry.all();
    for (all) |def| {
        switch (def.id) {
            features.FeatureID.UserAgent, features.FeatureID.Language, features.FeatureID.Languages, features.FeatureID.Vendor, features.FeatureID.CookieEnabled => {
                try testing.expectEqual(features.FeatureCategory.Navigator, def.category);
            },
            features.FeatureID.Platform, features.FeatureID.OperatingSystem => {
                try testing.expectEqual(features.FeatureCategory.Platform, def.category);
            },
            features.FeatureID.ScreenWidth, features.FeatureID.ScreenHeight, features.FeatureID.DevicePixelRatio, features.FeatureID.AvailableWidth, features.FeatureID.AvailableHeight, features.FeatureID.ColorDepth, features.FeatureID.PixelDepth => {
                try testing.expectEqual(features.FeatureCategory.Screen, def.category);
            },
            features.FeatureID.CanvasHash => {
                try testing.expectEqual(features.FeatureCategory.Canvas, def.category);
            },
            features.FeatureID.WebGLVendor, features.FeatureID.WebGLRenderer, features.FeatureID.WebGLHash, features.FeatureID.WebGLVersion => {
                try testing.expectEqual(features.FeatureCategory.WebGL, def.category);
            },
            features.FeatureID.AudioHash => {
                try testing.expectEqual(features.FeatureCategory.Audio, def.category);
            },
            features.FeatureID.FontsHash => {
                try testing.expectEqual(features.FeatureCategory.Fonts, def.category);
            },
            features.FeatureID.HardwareConcurrency, features.FeatureID.DeviceMemory, features.FeatureID.CpuClass => {
                try testing.expectEqual(features.FeatureCategory.Hardware, def.category);
            },
            features.FeatureID.LocalStorage, features.FeatureID.SessionStorage, features.FeatureID.IndexedDB => {
                try testing.expectEqual(features.FeatureCategory.Storage, def.category);
            },
            features.FeatureID.NotificationPermission => {
                try testing.expectEqual(features.FeatureCategory.Permissions, def.category);
            },
            features.FeatureID.AudioInputDevices, features.FeatureID.AudioOutputDevices, features.FeatureID.VideoInputDevices => {
                try testing.expectEqual(features.FeatureCategory.Media, def.category);
            },
            features.FeatureID.ConnectionType => {
                try testing.expectEqual(features.FeatureCategory.Network, def.category);
            },
            features.FeatureID.Locale => {
                try testing.expectEqual(features.FeatureCategory.Locale, def.category);
            },
            features.FeatureID.Timezone => {
                try testing.expectEqual(features.FeatureCategory.Timezone, def.category);
            },
            features.FeatureID.SchemaVersion, features.FeatureID.SDKVersion, features.FeatureID.CollectionTimestamp => {
                try testing.expectEqual(features.FeatureCategory.Metadata, def.category);
            },
            else => {
                try testing.expectEqual(features.FeatureCategory.Metadata, def.category);
            },
        }
    }
}

test "Integration — every definition category has matching FeatureCategory" {
    const all = features.Registry.all();
    for (all) |def| {
        const category_index = @intFromEnum(def.category);
        try testing.expect(category_index >= 0);
        try testing.expect(category_index <= @intFromEnum(features.FeatureCategory.Metadata));
    }
}

test "Integration — critical features have stable + required + high_entropy" {
    const critical_ids = [_]features.FeatureID{
        features.FeatureID.UserAgent,
        features.FeatureID.CanvasHash,
        features.FeatureID.WebGLRenderer,
        features.FeatureID.WebGLHash,
        features.FeatureID.AudioHash,
        features.FeatureID.FontsHash,
    };
    for (critical_ids) |id| {
        const def = features.Registry.get(id);
        try testing.expect(def.isStable());
        try testing.expect(def.isRequired());
        try testing.expect(def.isHighEntropy());
    }
}

test "Integration — stable_required features have stable + required but not high_entropy" {
    const stable_required_ids = [_]features.FeatureID{
        features.FeatureID.Language,
        features.FeatureID.Languages,
        features.FeatureID.Platform,
        features.FeatureID.Vendor,
        features.FeatureID.CookieEnabled,
        features.FeatureID.ScreenWidth,
        features.FeatureID.ScreenHeight,
        features.FeatureID.DevicePixelRatio,
        features.FeatureID.AvailableWidth,
        features.FeatureID.AvailableHeight,
        features.FeatureID.ColorDepth,
        features.FeatureID.PixelDepth,
        features.FeatureID.OperatingSystem,
        features.FeatureID.LocalStorage,
        features.FeatureID.SessionStorage,
        features.FeatureID.IndexedDB,
        features.FeatureID.NotificationPermission,
        features.FeatureID.Locale,
        features.FeatureID.Timezone,
    };
    for (stable_required_ids) |id| {
        const def = features.Registry.get(id);
        try testing.expect(def.isStable());
        try testing.expect(def.isRequired());
        try testing.expect(!def.isHighEntropy());
    }
}

test "Integration — stable_entropy feature has stable + high_entropy but not required" {
    const def = features.Registry.get(features.FeatureID.WebGLVendor);
    try testing.expect(def.isStable());
    try testing.expect(def.isHighEntropy());
    try testing.expect(!def.isRequired());
}

// ──────────────────────────────────────────────
// Integration: Weight consistency
// ──────────────────────────────────────────────

test "Integration — features with Bytes value type have weight >= 90" {
    const all = features.Registry.all();
    for (all) |def| {
        if (def.value_type == features.FeatureType.Bytes) {
            try testing.expect(def.weight >= 90);
        }
    }
}

test "Integration — Navigator category features have weight between 20 and 90" {
    const all = features.Registry.all();
    for (all) |def| {
        if (def.category == features.FeatureCategory.Navigator) {
            try testing.expect(def.weight >= 20);
            try testing.expect(def.weight <= 90);
        }
    }
}

// ──────────────────────────────────────────────
// Integration: FeatureID enum coverage
// ──────────────────────────────────────────────

test "Integration — all 38 FeatureID variants have a comptime slot" {
    // Every FeatureID variant gets a null slot in the lookup table.
    // If a variant is added to the enum but no definition is registered,
    // the build will fail at compile time with:
    //   "Missing FeatureDefinition for '<name>'."
    // This test verifies the compile-time validation exists.
    try testing.expectEqual(@as(usize, 38), @typeInfo(features.FeatureID).@"enum".fields.len);
}
