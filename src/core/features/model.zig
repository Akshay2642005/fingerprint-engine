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
    Battery,
    MediaCapabilities,
    Crypto,
    Speech,
    GPU,
    Performance,
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
    // ── Navigator (0-16) ──────────────────────────────────────────────
    UserAgent = 0,
    Language = 1,
    Languages = 2,
    Platform = 3,
    Vendor = 4,
    Product = 5,
    ProductSub = 6,
    AppName = 7,
    AppVersion = 8,
    CookieEnabled = 9,
    DoNotTrack = 10,
    HardwareConcurrency = 11,
    MaxTouchPoints = 12,
    DeviceMemory = 13,
    PdfViewerEnabled = 14,
    VendorSub = 15,
    DeviceRam = 16,

    // ── Screen (17-28) ────────────────────────────────────────────────
    ScreenWidth = 17,
    ScreenHeight = 18,
    AvailableWidth = 19,
    AvailableHeight = 20,
    ColorDepth = 21,
    PixelDepth = 22,
    DevicePixelRatio = 23,
    InnerWidth = 24,
    InnerHeight = 25,
    OuterWidth = 26,
    OuterHeight = 27,
    ScreenOrientation = 28,

    // ── Hardware (29-34) ───────────────────────────────────────────────
    CpuClass = 29,
    CpuCores = 30,
    CpuArchitecture = 31,
    PlatformArchitecture = 32,
    HardwareAcceleration = 33,
    TouchSupport = 34,

    // ── Canvas (35) ────────────────────────────────────────────────────
    CanvasHash = 35,

    // ── WebGL (36-42) ──────────────────────────────────────────────────
    WebGLVendor = 36,
    WebGLRenderer = 37,
    WebGLVersion = 38,
    WebGLHash = 39,
    WebGLExtensions = 40,
    WebGLParameters = 41,
    WebGLShaderPrecision = 42,

    // ── Audio (43) ─────────────────────────────────────────────────────
    AudioHash = 43,

    // ── Fonts (44) ─────────────────────────────────────────────────────
    FontsHash = 44,

    // ── Platform (45-46) ──────────────────────────────────────────────
    OperatingSystem = 45,
    OSVersion = 46,

    // ── Storage (47-51) ──────────────────────────────────────────────
    LocalStorage = 47,
    SessionStorage = 48,
    IndexedDB = 49,
    CacheStorage = 50,
    CookiesEnabled = 51,

    // ── Permissions (52-55) ──────────────────────────────────────────
    NotificationPermission = 52,
    GeolocationPermission = 53,
    CameraPermission = 54,
    MicrophonePermission = 55,

    // ── Media (56-61) ────────────────────────────────────────────────
    AudioInputDevices = 56,
    AudioOutputDevices = 57,
    VideoInputDevices = 58,
    SupportedCodecs = 59,
    MediaFormats = 60,
    AudioFormats = 61,

    // ── Network (62-66) ──────────────────────────────────────────────
    ConnectionType = 62,
    ConnectionDownlink = 63,
    ConnectionEffectiveType = 64,
    ConnectionRtt = 65,
    ConnectionSaveData = 66,

    // ── Locale & Timezone (67-70) ────────────────────────────────────
    Locale = 67,
    Timezone = 68,
    TimezoneOffset = 69,
    DateTimeFormat = 70,

    // ── Battery (71-73) ──────────────────────────────────────────────
    BatteryLevel = 71,
    BatteryCharging = 72,
    BatteryChargingTime = 73,

    // ── Media Capabilities (74-76) ──────────────────────────────────
    DecodeCapability = 74,
    EncodeCapability = 75,
    HDRSupport = 76,

    // ── Crypto (77-78) ──────────────────────────────────────────────
    CryptoSupport = 77,
    SubtleCrypto = 78,

    // ── Speech (79) ──────────────────────────────────────────────────
    SpeechSynthesisVoices = 79,

    // ── GPU (80-82) ──────────────────────────────────────────────────
    GPUVendor = 80,
    GPURenderer = 81,
    GPUDriverVersion = 82,

    // ── Performance (83-85) ──────────────────────────────────────────
    HardwareConcurrencyPerformance = 83,
    DeviceMemoryPerformance = 84,
    TimePrecision = 85,

    // ── CSS Features (86-90) ──────────────────────────────────────────
    CSSCustomProperties = 86,
    CSSGridSupport = 87,
    CSSFlexboxSupport = 88,
    CSSContainerQuery = 89,
    CSSHasSelector = 90,

    // ── Browser Features (91-95) ──────────────────────────────────────
    ServiceWorkerSupport = 91,
    WebWorkerSupport = 92,
    SharedWorkerSupport = 93,
    WebSocketSupport = 94,
    WebRTCSupport = 95,

    // ── Input (96-98) ──────────────────────────────────────────────────
    KeyboardLayout = 96,
    PointerEvents = 97,
    GamepadSupport = 98,

    // ── Metadata (99-101) ──────────────────────────────────────────────
    SchemaVersion = 99,
    SDKVersion = 100,
    CollectionTimestamp = 101,

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
