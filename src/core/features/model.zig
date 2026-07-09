const std = @import("std");

pub const FeatureCategory = enum(u8) {
    Navigator,
    Screen,
    Canvas,
    WebGL,
    Audio,
    Fonts,
    Hardware,
    Platform,
    Storage,
    Permissions,
    Media,
    Network,
    Locale,
    Timezone,
    Metadata,
};

pub const FeatureType = enum(u8) {
    Boolean,
    Integer,
    Float,
    String,
    Bytes,

    StringArray,
    IntegerArray,
    FloatArray,
    BytesArray,
};

pub const FeatureWeight = u8;

pub const FeatureFlags = packed struct(u8) {
    stable: bool = false,
    high_entropy: bool = false,
    required: bool = false,
    sensitive: bool = false,
    reserved: u4 = 0,

    pub const none = FeatureFlags{};
    pub const stable_required = FeatureFlags{ .stable = true, .required = true };
    pub const stable_entropy = FeatureFlags{ .stable = true, .high_entropy = true };
    pub const required_entropy = FeatureFlags{ .required = true, .high_entropy = true };
    pub const critical = FeatureFlags{ .stable = true, .required = true, .high_entropy = true };
};

pub const FeatureID = enum(u16) {
    UserAgent,
    Language,
    Languages,
    Platform,
    Vendor,
    CookieEnabled,
    HardwareConcurrency,
    DeviceMemory,
    ScreenWidth,
    ScreenHeight,
    AvailableWidth,
    AvailableHeight,
    ColorDepth,
    PixelDepth,
    DevicePixelRatio,
    CanvasHash,
    WebGLVendor,
    WebGLRenderer,
    WebGLVersion,
    WebGLHash,
    AudioHash,
    FontsHash,
    CpuClass,
    OperatingSystem,
    LocalStorage,
    SessionStorage,
    IndexedDB,
    NotificationPermission,
    AudioInputDevices,
    AudioOutputDevices,
    VideoInputDevices,
    ConnectionType,
    Locale,
    Timezone,
    SchemaVersion,
    SDKVersion,
    CollectionTimestamp,
    Count,
};

pub const FeatureDefinition = struct {
    id: FeatureID,
    category: FeatureCategory,
    value_type: FeatureType,
    weight: FeatureWeight,
    flags: FeatureFlags,
    name: []const u8,
    description: []const u8,

    pub inline fn isStable(self: FeatureDefinition) bool {
        return self.flags.stable;
    }
    pub inline fn isRequired(self: FeatureDefinition) bool {
        return self.flags.required;
    }
    pub inline fn isHighEntropy(self: FeatureDefinition) bool {
        return self.flags.high_entropy;
    }
    pub inline fn isSensitive(self: FeatureDefinition) bool {
        return self.flags.sensitive;
    }
};

comptime {
    std.debug.assert(@sizeOf(FeatureCategory) == 1);
    std.debug.assert(@sizeOf(FeatureType) == 1);
    std.debug.assert(@sizeOf(FeatureFlags) == 1);
    std.debug.assert(@sizeOf(FeatureID) == 2);
}
