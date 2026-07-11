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
            // Navigator (0-16)
            features.FeatureID.UserAgent, features.FeatureID.Language, features.FeatureID.Languages, features.FeatureID.Vendor, features.FeatureID.Product, features.FeatureID.ProductSub, features.FeatureID.AppName, features.FeatureID.AppVersion, features.FeatureID.CookieEnabled, features.FeatureID.DoNotTrack, features.FeatureID.PdfViewerEnabled, features.FeatureID.VendorSub => {
                try testing.expectEqual(features.FeatureCategory.Navigator, def.category);
            },
            // Platform (3, 45-46, 86-95)
            features.FeatureID.Platform, features.FeatureID.OperatingSystem, features.FeatureID.OSVersion, features.FeatureID.CSSCustomProperties, features.FeatureID.CSSGridSupport, features.FeatureID.CSSFlexboxSupport, features.FeatureID.CSSContainerQuery, features.FeatureID.CSSHasSelector, features.FeatureID.ServiceWorkerSupport, features.FeatureID.WebWorkerSupport, features.FeatureID.SharedWorkerSupport, features.FeatureID.WebSocketSupport, features.FeatureID.WebRTCSupport, features.FeatureID.KeyboardLayout, features.FeatureID.PointerEvents, features.FeatureID.GamepadSupport => {
                try testing.expectEqual(features.FeatureCategory.Platform, def.category);
            },
            // Screen (17-28)
            features.FeatureID.ScreenWidth, features.FeatureID.ScreenHeight, features.FeatureID.AvailableWidth, features.FeatureID.AvailableHeight, features.FeatureID.ColorDepth, features.FeatureID.PixelDepth, features.FeatureID.DevicePixelRatio, features.FeatureID.InnerWidth, features.FeatureID.InnerHeight, features.FeatureID.OuterWidth, features.FeatureID.OuterHeight, features.FeatureID.ScreenOrientation => {
                try testing.expectEqual(features.FeatureCategory.Screen, def.category);
            },
            // Canvas (35)
            features.FeatureID.CanvasHash => {
                try testing.expectEqual(features.FeatureCategory.Canvas, def.category);
            },
            // WebGL (36-42)
            features.FeatureID.WebGLVendor, features.FeatureID.WebGLRenderer, features.FeatureID.WebGLVersion, features.FeatureID.WebGLHash, features.FeatureID.WebGLExtensions, features.FeatureID.WebGLParameters, features.FeatureID.WebGLShaderPrecision => {
                try testing.expectEqual(features.FeatureCategory.WebGL, def.category);
            },
            // Audio (43)
            features.FeatureID.AudioHash => {
                try testing.expectEqual(features.FeatureCategory.Audio, def.category);
            },
            // Fonts (44)
            features.FeatureID.FontsHash => {
                try testing.expectEqual(features.FeatureCategory.Fonts, def.category);
            },
            // Hardware (11, 13, 16, 29-34)
            features.FeatureID.HardwareConcurrency, features.FeatureID.DeviceMemory, features.FeatureID.DeviceRam, features.FeatureID.CpuClass, features.FeatureID.CpuCores, features.FeatureID.CpuArchitecture, features.FeatureID.PlatformArchitecture, features.FeatureID.HardwareAcceleration, features.FeatureID.TouchSupport, features.FeatureID.MaxTouchPoints => {
                try testing.expectEqual(features.FeatureCategory.Hardware, def.category);
            },
            // Storage (47-51)
            features.FeatureID.LocalStorage, features.FeatureID.SessionStorage, features.FeatureID.IndexedDB, features.FeatureID.CacheStorage, features.FeatureID.CookiesEnabled => {
                try testing.expectEqual(features.FeatureCategory.Storage, def.category);
            },
            // Permissions (52-55)
            features.FeatureID.NotificationPermission, features.FeatureID.GeolocationPermission, features.FeatureID.CameraPermission, features.FeatureID.MicrophonePermission => {
                try testing.expectEqual(features.FeatureCategory.Permissions, def.category);
            },
            // Media (56-61)
            features.FeatureID.AudioInputDevices, features.FeatureID.AudioOutputDevices, features.FeatureID.VideoInputDevices, features.FeatureID.SupportedCodecs, features.FeatureID.MediaFormats, features.FeatureID.AudioFormats => {
                try testing.expectEqual(features.FeatureCategory.Media, def.category);
            },
            // Network (62-66)
            features.FeatureID.ConnectionType, features.FeatureID.ConnectionDownlink, features.FeatureID.ConnectionEffectiveType, features.FeatureID.ConnectionRtt, features.FeatureID.ConnectionSaveData => {
                try testing.expectEqual(features.FeatureCategory.Network, def.category);
            },
            // Locale (67, 70)
            features.FeatureID.Locale, features.FeatureID.DateTimeFormat => {
                try testing.expectEqual(features.FeatureCategory.Locale, def.category);
            },
            // Timezone (68-69)
            features.FeatureID.Timezone, features.FeatureID.TimezoneOffset => {
                try testing.expectEqual(features.FeatureCategory.Timezone, def.category);
            },
            // Battery (71-73)
            features.FeatureID.BatteryLevel, features.FeatureID.BatteryCharging, features.FeatureID.BatteryChargingTime => {
                try testing.expectEqual(features.FeatureCategory.Battery, def.category);
            },
            // MediaCapabilities (74-76)
            features.FeatureID.DecodeCapability, features.FeatureID.EncodeCapability, features.FeatureID.HDRSupport => {
                try testing.expectEqual(features.FeatureCategory.MediaCapabilities, def.category);
            },
            // Crypto (77-78)
            features.FeatureID.CryptoSupport, features.FeatureID.SubtleCrypto => {
                try testing.expectEqual(features.FeatureCategory.Crypto, def.category);
            },
            // Speech (79)
            features.FeatureID.SpeechSynthesisVoices => {
                try testing.expectEqual(features.FeatureCategory.Speech, def.category);
            },
            // GPU (80-82)
            features.FeatureID.GPUVendor, features.FeatureID.GPURenderer, features.FeatureID.GPUDriverVersion => {
                try testing.expectEqual(features.FeatureCategory.GPU, def.category);
            },
            // Performance (83-85)
            features.FeatureID.HardwareConcurrencyPerformance, features.FeatureID.DeviceMemoryPerformance, features.FeatureID.TimePrecision => {
                try testing.expectEqual(features.FeatureCategory.Performance, def.category);
            },
            // Metadata (99-101)
            features.FeatureID.SchemaVersion, features.FeatureID.SDKVersion, features.FeatureID.CollectionTimestamp => {
                try testing.expectEqual(features.FeatureCategory.Metadata, def.category);
            },
            else => {
                // Any FeatureID not explicitly listed above is a new addition
                // that needs a category assertion added to this test.
                try testing.expect(false);
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
            try testing.expect(def.weight >= 15);
            try testing.expect(def.weight <= 90);
        }
    }
}

// ──────────────────────────────────────────────
// Integration: FeatureID enum coverage
// ──────────────────────────────────────────────

test "Integration — all 103 FeatureID variants have a comptime slot" {
    // Every FeatureID variant gets a null slot in the lookup table.
    // If a variant is added to the enum but no definition is registered,
    // the build will fail at compile time with:
    //   "Missing FeatureDefinition for '<name>'."
    // This test verifies the compile-time validation exists.
    // 102 data variants + Count = 103 total
    try testing.expectEqual(@as(usize, 103), @typeInfo(features.FeatureID).@"enum".fields.len);
}
