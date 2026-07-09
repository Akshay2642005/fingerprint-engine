const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const assertions = @import("test_utils").assertions;

// ──────────────────────────────────────────────
// Navigator Features
// ──────────────────────────────────────────────

test "UserAgent definition is critical navigator string with weight 90" {
    const def = features.Registry.get(features.FeatureID.UserAgent);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.UserAgent,
        features.FeatureCategory.Navigator,
        features.FeatureType.String,
        90,
        features.FeatureFlags.critical,
        "User Agent",
        "Browser user agent string.",
    );
}

test "Language definition is stable_required navigator string with weight 40" {
    const def = features.Registry.get(features.FeatureID.Language);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.Language,
        features.FeatureCategory.Navigator,
        features.FeatureType.String,
        40,
        features.FeatureFlags.stable_required,
        "Language",
        "Primary browser language.",
    );
}

test "Languages definition is stable_required string array with weight 50" {
    const def = features.Registry.get(features.FeatureID.Languages);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.Languages,
        features.FeatureCategory.Navigator,
        features.FeatureType.StringArray,
        50,
        features.FeatureFlags.stable_required,
        "Languages",
        "Preferred browser languages.",
    );
}

// ──────────────────────────────────────────────
// Platform Feature
// ──────────────────────────────────────────────

test "Platform definition is stable_required platform string with weight 70" {
    const def = features.Registry.get(features.FeatureID.Platform);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.Platform,
        features.FeatureCategory.Platform,
        features.FeatureType.String,
        70,
        features.FeatureFlags.stable_required,
        "Platform",
        "Browser platform identifier.",
    );
}

// ──────────────────────────────────────────────
// Screen Features
// ──────────────────────────────────────────────

test "ScreenWidth definition is stable_required screen integer with weight 60" {
    const def = features.Registry.get(features.FeatureID.ScreenWidth);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.ScreenWidth,
        features.FeatureCategory.Screen,
        features.FeatureType.Integer,
        60,
        features.FeatureFlags.stable_required,
        "Screen Width",
        "Primary screen width.",
    );
}

test "ScreenHeight definition is stable_required screen integer with weight 60" {
    const def = features.Registry.get(features.FeatureID.ScreenHeight);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.ScreenHeight,
        features.FeatureCategory.Screen,
        features.FeatureType.Integer,
        60,
        features.FeatureFlags.stable_required,
        "Screen Height",
        "Primary screen height.",
    );
}

test "DevicePixelRatio definition is stable_required screen float with weight 45" {
    const def = features.Registry.get(features.FeatureID.DevicePixelRatio);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.DevicePixelRatio,
        features.FeatureCategory.Screen,
        features.FeatureType.Float,
        45,
        features.FeatureFlags.stable_required,
        "Device Pixel Ratio",
        "Browser device pixel ratio.",
    );
}

// ──────────────────────────────────────────────
// Canvas Feature
// ──────────────────────────────────────────────

test "CanvasHash definition is critical canvas bytes with weight 100" {
    const def = features.Registry.get(features.FeatureID.CanvasHash);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.CanvasHash,
        features.FeatureCategory.Canvas,
        features.FeatureType.Bytes,
        100,
        features.FeatureFlags.critical,
        "Canvas Hash",
        "SHA-256 hash of rendered canvas.",
    );
}

// ──────────────────────────────────────────────
// WebGL Features
// ──────────────────────────────────────────────

test "WebGLVendor definition is stable_entropy WebGL string with weight 80" {
    const def = features.Registry.get(features.FeatureID.WebGLVendor);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.WebGLVendor,
        features.FeatureCategory.WebGL,
        features.FeatureType.String,
        80,
        features.FeatureFlags.stable_entropy,
        "WebGL Vendor",
        "WebGL vendor string.",
    );
}

test "WebGLRenderer definition is critical WebGL string with weight 90" {
    const def = features.Registry.get(features.FeatureID.WebGLRenderer);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.WebGLRenderer,
        features.FeatureCategory.WebGL,
        features.FeatureType.String,
        90,
        features.FeatureFlags.critical,
        "WebGL Renderer",
        "GPU renderer string.",
    );
}

test "WebGLHash definition is critical WebGL bytes with weight 100" {
    const def = features.Registry.get(features.FeatureID.WebGLHash);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.WebGLHash,
        features.FeatureCategory.WebGL,
        features.FeatureType.Bytes,
        100,
        features.FeatureFlags.critical,
        "WebGL Hash",
        "Hashed WebGL fingerprint.",
    );
}

// ──────────────────────────────────────────────
// Browser Vendor & Cookie
// ──────────────────────────────────────────────

test "Vendor definition is stable_required navigator string with weight 30" {
    const def = features.Registry.get(features.FeatureID.Vendor);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.Vendor,
        features.FeatureCategory.Navigator,
        features.FeatureType.String,
        30,
        features.FeatureFlags.stable_required,
        "Vendor",
        "Browser vendor string.",
    );
}

test "CookieEnabled definition is stable_required navigator boolean with weight 20" {
    const def = features.Registry.get(features.FeatureID.CookieEnabled);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.CookieEnabled,
        features.FeatureCategory.Navigator,
        features.FeatureType.Boolean,
        20,
        features.FeatureFlags.stable_required,
        "Cookie Enabled",
        "Whether cookies are enabled in the browser.",
    );
}

// ──────────────────────────────────────────────
// Hardware Features
// ──────────────────────────────────────────────

test "HardwareConcurrency definition is stable_entropy hardware integer with weight 50" {
    const def = features.Registry.get(features.FeatureID.HardwareConcurrency);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.HardwareConcurrency,
        features.FeatureCategory.Hardware,
        features.FeatureType.Integer,
        50,
        features.FeatureFlags.stable_entropy,
        "Hardware Concurrency",
        "Number of logical CPU cores available.",
    );
}

test "DeviceMemory definition is stable_entropy hardware float with weight 40" {
    const def = features.Registry.get(features.FeatureID.DeviceMemory);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.DeviceMemory,
        features.FeatureCategory.Hardware,
        features.FeatureType.Float,
        40,
        features.FeatureFlags.stable_entropy,
        "Device Memory",
        "Approximate device RAM in gigabytes.",
    );
}

test "CpuClass definition is stable_entropy hardware string with weight 40" {
    const def = features.Registry.get(features.FeatureID.CpuClass);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.CpuClass,
        features.FeatureCategory.Hardware,
        features.FeatureType.String,
        40,
        features.FeatureFlags.stable_entropy,
        "CPU Class",
        "Browser CPU architecture class.",
    );
}

// ──────────────────────────────────────────────
// Extended Screen Features
// ──────────────────────────────────────────────

test "AvailableWidth definition is stable_required screen integer with weight 50" {
    const def = features.Registry.get(features.FeatureID.AvailableWidth);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.AvailableWidth,
        features.FeatureCategory.Screen,
        features.FeatureType.Integer,
        50,
        features.FeatureFlags.stable_required,
        "Available Width",
        "Available screen width excluding taskbars.",
    );
}

test "AvailableHeight definition is stable_required screen integer with weight 50" {
    const def = features.Registry.get(features.FeatureID.AvailableHeight);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.AvailableHeight,
        features.FeatureCategory.Screen,
        features.FeatureType.Integer,
        50,
        features.FeatureFlags.stable_required,
        "Available Height",
        "Available screen height excluding taskbars.",
    );
}

test "ColorDepth definition is stable_required screen integer with weight 35" {
    const def = features.Registry.get(features.FeatureID.ColorDepth);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.ColorDepth,
        features.FeatureCategory.Screen,
        features.FeatureType.Integer,
        35,
        features.FeatureFlags.stable_required,
        "Color Depth",
        "Screen color depth in bits.",
    );
}

test "PixelDepth definition is stable_required screen integer with weight 35" {
    const def = features.Registry.get(features.FeatureID.PixelDepth);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.PixelDepth,
        features.FeatureCategory.Screen,
        features.FeatureType.Integer,
        35,
        features.FeatureFlags.stable_required,
        "Pixel Depth",
        "Screen pixel depth in bits.",
    );
}

// ──────────────────────────────────────────────
// Extended WebGL & Audio/Fonts
// ──────────────────────────────────────────────

test "WebGLVersion definition is stable_entropy WebGL string with weight 60" {
    const def = features.Registry.get(features.FeatureID.WebGLVersion);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.WebGLVersion,
        features.FeatureCategory.WebGL,
        features.FeatureType.String,
        60,
        features.FeatureFlags.stable_entropy,
        "WebGL Version",
        "WebGL version string.",
    );
}

test "AudioHash definition is critical audio bytes with weight 95" {
    const def = features.Registry.get(features.FeatureID.AudioHash);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.AudioHash,
        features.FeatureCategory.Audio,
        features.FeatureType.Bytes,
        95,
        features.FeatureFlags.critical,
        "Audio Hash",
        "Hash of rendered audio fingerprint.",
    );
}

test "FontsHash definition is critical fonts bytes with weight 95" {
    const def = features.Registry.get(features.FeatureID.FontsHash);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.FontsHash,
        features.FeatureCategory.Fonts,
        features.FeatureType.Bytes,
        95,
        features.FeatureFlags.critical,
        "Fonts Hash",
        "Hash of installed fonts fingerprint.",
    );
}

// ──────────────────────────────────────────────
// Operating System & Storage
// ──────────────────────────────────────────────

test "OperatingSystem definition is stable_required platform string with weight 75" {
    const def = features.Registry.get(features.FeatureID.OperatingSystem);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.OperatingSystem,
        features.FeatureCategory.Platform,
        features.FeatureType.String,
        75,
        features.FeatureFlags.stable_required,
        "Operating System",
        "Operating system identifier.",
    );
}

test "LocalStorage definition is stable_required storage boolean with weight 30" {
    const def = features.Registry.get(features.FeatureID.LocalStorage);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.LocalStorage,
        features.FeatureCategory.Storage,
        features.FeatureType.Boolean,
        30,
        features.FeatureFlags.stable_required,
        "Local Storage",
        "Whether localStorage is available.",
    );
}

test "SessionStorage definition is stable_required storage boolean with weight 25" {
    const def = features.Registry.get(features.FeatureID.SessionStorage);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.SessionStorage,
        features.FeatureCategory.Storage,
        features.FeatureType.Boolean,
        25,
        features.FeatureFlags.stable_required,
        "Session Storage",
        "Whether sessionStorage is available.",
    );
}

test "IndexedDB definition is stable_required storage boolean with weight 25" {
    const def = features.Registry.get(features.FeatureID.IndexedDB);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.IndexedDB,
        features.FeatureCategory.Storage,
        features.FeatureType.Boolean,
        25,
        features.FeatureFlags.stable_required,
        "IndexedDB",
        "Whether IndexedDB is available.",
    );
}

// ──────────────────────────────────────────────
// Permissions & Media
// ──────────────────────────────────────────────

test "NotificationPermission definition is stable_required permission string with weight 20" {
    const def = features.Registry.get(features.FeatureID.NotificationPermission);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.NotificationPermission,
        features.FeatureCategory.Permissions,
        features.FeatureType.String,
        20,
        features.FeatureFlags.stable_required,
        "Notification Permission",
        "Notification permission status.",
    );
}

test "AudioInputDevices definition is stable media string array with weight 30" {
    const def = features.Registry.get(features.FeatureID.AudioInputDevices);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.AudioInputDevices,
        features.FeatureCategory.Media,
        features.FeatureType.StringArray,
        30,
        .{ .stable = true },
        "Audio Input Devices",
        "Available audio input device labels.",
    );
}

test "AudioOutputDevices definition is stable media string array with weight 25" {
    const def = features.Registry.get(features.FeatureID.AudioOutputDevices);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.AudioOutputDevices,
        features.FeatureCategory.Media,
        features.FeatureType.StringArray,
        25,
        .{ .stable = true },
        "Audio Output Devices",
        "Available audio output device labels.",
    );
}

test "VideoInputDevices definition is stable media string array with weight 30" {
    const def = features.Registry.get(features.FeatureID.VideoInputDevices);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.VideoInputDevices,
        features.FeatureCategory.Media,
        features.FeatureType.StringArray,
        30,
        .{ .stable = true },
        "Video Input Devices",
        "Available video input device labels.",
    );
}

// ──────────────────────────────────────────────
// Network, Locale & Timezone
// ──────────────────────────────────────────────

test "ConnectionType definition is stable network string with weight 45" {
    const def = features.Registry.get(features.FeatureID.ConnectionType);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.ConnectionType,
        features.FeatureCategory.Network,
        features.FeatureType.String,
        45,
        .{ .stable = true },
        "Connection Type",
        "Network connection type (e.g. bluetooth, cellular).",
    );
}

test "Locale definition is stable_required locale string with weight 35" {
    const def = features.Registry.get(features.FeatureID.Locale);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.Locale,
        features.FeatureCategory.Locale,
        features.FeatureType.String,
        35,
        features.FeatureFlags.stable_required,
        "Locale",
        "Browser locale string.",
    );
}

test "Timezone definition is stable_required timezone string with weight 40" {
    const def = features.Registry.get(features.FeatureID.Timezone);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.Timezone,
        features.FeatureCategory.Timezone,
        features.FeatureType.String,
        40,
        features.FeatureFlags.stable_required,
        "Timezone",
        "IANA timezone identifier.",
    );
}

// ──────────────────────────────────────────────
// Metadata Features
// ──────────────────────────────────────────────

test "SchemaVersion definition is required_entropy metadata integer with weight 0" {
    const def = features.Registry.get(features.FeatureID.SchemaVersion);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.SchemaVersion,
        features.FeatureCategory.Metadata,
        features.FeatureType.Integer,
        0,
        features.FeatureFlags.required_entropy,
        "Schema Version",
        "Fingerprint schema version number.",
    );
}

test "SDKVersion definition is required_entropy metadata string with weight 0" {
    const def = features.Registry.get(features.FeatureID.SDKVersion);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.SDKVersion,
        features.FeatureCategory.Metadata,
        features.FeatureType.String,
        0,
        features.FeatureFlags.required_entropy,
        "SDK Version",
        "Fingerprint SDK version string.",
    );
}

test "CollectionTimestamp definition is required_entropy metadata integer with weight 0" {
    const def = features.Registry.get(features.FeatureID.CollectionTimestamp);
    try assertions.expectFeatureDefinition(
        def,
        features.FeatureID.CollectionTimestamp,
        features.FeatureCategory.Metadata,
        features.FeatureType.Integer,
        0,
        features.FeatureFlags.required_entropy,
        "Collection Timestamp",
        "Unix timestamp of fingerprint collection.",
    );
}

// ──────────────────────────────────────────────
// Edge Cases
// ──────────────────────────────────────────────

test "All definitions have non-empty names" {
    const all = features.Registry.all();
    for (all) |def| {
        try testing.expect(def.name.len > 0);
    }
}

test "All definitions have non-empty descriptions" {
    const all = features.Registry.all();
    for (all) |def| {
        try testing.expect(def.description.len > 0);
    }
}

test "All definitions have weights between 0 and 100" {
    const all = features.Registry.all();
    for (all) |def| {
        try testing.expect(def.weight >= 0);
        try testing.expect(def.weight <= 100);
    }
}

test "All definitions have at least one flag set" {
    const all = features.Registry.all();
    for (all) |def| {
        const has_any_flag = def.flags.stable or def.flags.high_entropy or def.flags.required or def.flags.sensitive;
        try testing.expect(has_any_flag);
    }
}

test "No definition has sensitive flag" {
    const all = features.Registry.all();
    for (all) |def| {
        try testing.expect(!def.flags.sensitive);
    }
}

test "WebGL features have stable flag" {
    const webgl_defs = [_]features.FeatureID{
        features.FeatureID.WebGLVendor,
        features.FeatureID.WebGLRenderer,
        features.FeatureID.WebGLHash,
    };
    for (webgl_defs) |id| {
        try testing.expect(features.Registry.get(id).isStable());
    }
}

test "Canvas hash has all critical flags" {
    const def = features.Registry.get(features.FeatureID.CanvasHash);
    try testing.expect(def.isStable());
    try testing.expect(def.isRequired());
    try testing.expect(def.isHighEntropy());
}
