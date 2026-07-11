const model = @import("model.zig");

pub const definitions = [_]model.FeatureDefinition{
    // ── Navigator (0-16) ──────────────────────────────────────────────
    .{ .id = .UserAgent, .category = .Navigator, .value_type = .String, .weight = 90, .flags = .critical, .name = "User Agent", .description = "Browser user agent string." },
    .{ .id = .Language, .category = .Navigator, .value_type = .String, .weight = 40, .flags = .stable_required, .name = "Language", .description = "Primary browser language." },
    .{ .id = .Languages, .category = .Navigator, .value_type = .StringArray, .weight = 50, .flags = .stable_required, .name = "Languages", .description = "Preferred browser languages." },
    .{ .id = .Platform, .category = .Platform, .value_type = .String, .weight = 70, .flags = .stable_required, .name = "Platform", .description = "Browser platform identifier." },
    .{ .id = .Vendor, .category = .Navigator, .value_type = .String, .weight = 30, .flags = .stable_required, .name = "Vendor", .description = "Browser vendor string." },
    .{ .id = .Product, .category = .Navigator, .value_type = .String, .weight = 25, .flags = .stable_required, .name = "Product", .description = "Browser product string." },
    .{ .id = .ProductSub, .category = .Navigator, .value_type = .String, .weight = 20, .flags = .stable_required, .name = "Product Sub", .description = "Browser product sub-version." },
    .{ .id = .AppName, .category = .Navigator, .value_type = .String, .weight = 25, .flags = .stable_required, .name = "App Name", .description = "Browser application name." },
    .{ .id = .AppVersion, .category = .Navigator, .value_type = .String, .weight = 30, .flags = .stable_required, .name = "App Version", .description = "Browser application version." },
    .{ .id = .CookieEnabled, .category = .Navigator, .value_type = .Boolean, .weight = 20, .flags = .stable_required, .name = "Cookie Enabled", .description = "Whether cookies are enabled." },
    .{ .id = .DoNotTrack, .category = .Navigator, .value_type = .String, .weight = 15, .flags = .stable_required, .name = "Do Not Track", .description = "Do Not Track setting." },
    .{ .id = .HardwareConcurrency, .category = .Hardware, .value_type = .Integer, .weight = 50, .flags = .stable_entropy, .name = "Hardware Concurrency", .description = "Number of logical CPU cores." },
    .{ .id = .MaxTouchPoints, .category = .Hardware, .value_type = .Integer, .weight = 40, .flags = .stable_entropy, .name = "Max Touch Points", .description = "Maximum touch points supported." },
    .{ .id = .DeviceMemory, .category = .Hardware, .value_type = .Float, .weight = 40, .flags = .stable_entropy, .name = "Device Memory", .description = "Approximate device RAM in GB." },
    .{ .id = .PdfViewerEnabled, .category = .Navigator, .value_type = .Boolean, .weight = 15, .flags = .stable_required, .name = "PDF Viewer Enabled", .description = "Whether PDF viewer is enabled." },
    .{ .id = .VendorSub, .category = .Navigator, .value_type = .String, .weight = 20, .flags = .stable_required, .name = "Vendor Sub", .description = "Browser vendor sub-string." },
    .{ .id = .DeviceRam, .category = .Hardware, .value_type = .Integer, .weight = 35, .flags = .stable_entropy, .name = "Device RAM", .description = "Device RAM in GB (navigator.deviceMemory)." },

    // ── Screen (17-28) ────────────────────────────────────────────────
    .{ .id = .ScreenWidth, .category = .Screen, .value_type = .Integer, .weight = 60, .flags = .stable_required, .name = "Screen Width", .description = "Primary screen width." },
    .{ .id = .ScreenHeight, .category = .Screen, .value_type = .Integer, .weight = 60, .flags = .stable_required, .name = "Screen Height", .description = "Primary screen height." },
    .{ .id = .AvailableWidth, .category = .Screen, .value_type = .Integer, .weight = 50, .flags = .stable_required, .name = "Available Width", .description = "Available screen width." },
    .{ .id = .AvailableHeight, .category = .Screen, .value_type = .Integer, .weight = 50, .flags = .stable_required, .name = "Available Height", .description = "Available screen height." },
    .{ .id = .ColorDepth, .category = .Screen, .value_type = .Integer, .weight = 35, .flags = .stable_required, .name = "Color Depth", .description = "Screen color depth in bits." },
    .{ .id = .PixelDepth, .category = .Screen, .value_type = .Integer, .weight = 35, .flags = .stable_required, .name = "Pixel Depth", .description = "Screen pixel depth in bits." },
    .{ .id = .DevicePixelRatio, .category = .Screen, .value_type = .Float, .weight = 45, .flags = .stable_required, .name = "Device Pixel Ratio", .description = "Browser device pixel ratio." },
    .{ .id = .InnerWidth, .category = .Screen, .value_type = .Integer, .weight = 45, .flags = .stable_required, .name = "Inner Width", .description = "Browser viewport inner width." },
    .{ .id = .InnerHeight, .category = .Screen, .value_type = .Integer, .weight = 45, .flags = .stable_required, .name = "Inner Height", .description = "Browser viewport inner height." },
    .{ .id = .OuterWidth, .category = .Screen, .value_type = .Integer, .weight = 40, .flags = .stable_required, .name = "Outer Width", .description = "Browser window outer width." },
    .{ .id = .OuterHeight, .category = .Screen, .value_type = .Integer, .weight = 40, .flags = .stable_required, .name = "Outer Height", .description = "Browser window outer height." },
    .{ .id = .ScreenOrientation, .category = .Screen, .value_type = .String, .weight = 30, .flags = .stable_required, .name = "Screen Orientation", .description = "Screen orientation type." },

    // ── Hardware (29-34) ───────────────────────────────────────────────
    .{ .id = .CpuClass, .category = .Hardware, .value_type = .String, .weight = 40, .flags = .stable_entropy, .name = "CPU Class", .description = "Browser CPU architecture class." },
    .{ .id = .CpuCores, .category = .Hardware, .value_type = .Integer, .weight = 45, .flags = .stable_entropy, .name = "CPU Cores", .description = "Physical CPU cores (if available)." },
    .{ .id = .CpuArchitecture, .category = .Hardware, .value_type = .String, .weight = 40, .flags = .stable_entropy, .name = "CPU Architecture", .description = "CPU architecture identifier." },
    .{ .id = .PlatformArchitecture, .category = .Hardware, .value_type = .String, .weight = 35, .flags = .stable_entropy, .name = "Platform Architecture", .description = "Platform architecture (32/64-bit)." },
    .{ .id = .HardwareAcceleration, .category = .Hardware, .value_type = .Boolean, .weight = 30, .flags = .stable_entropy, .name = "Hardware Acceleration", .description = "Whether hardware acceleration is enabled." },
    .{ .id = .TouchSupport, .category = .Hardware, .value_type = .Boolean, .weight = 35, .flags = .stable_entropy, .name = "Touch Support", .description = "Whether touch is supported." },

    // ── Canvas (35) ────────────────────────────────────────────────────
    .{ .id = .CanvasHash, .category = .Canvas, .value_type = .Bytes, .weight = 100, .flags = .critical, .name = "Canvas Hash", .description = "SHA-256 hash of rendered canvas." },

    // ── WebGL (36-42) ──────────────────────────────────────────────────
    .{ .id = .WebGLVendor, .category = .WebGL, .value_type = .String, .weight = 80, .flags = .stable_entropy, .name = "WebGL Vendor", .description = "WebGL vendor string." },
    .{ .id = .WebGLRenderer, .category = .WebGL, .value_type = .String, .weight = 90, .flags = .critical, .name = "WebGL Renderer", .description = "GPU renderer string." },
    .{ .id = .WebGLVersion, .category = .WebGL, .value_type = .String, .weight = 60, .flags = .stable_entropy, .name = "WebGL Version", .description = "WebGL version string." },
    .{ .id = .WebGLHash, .category = .WebGL, .value_type = .Bytes, .weight = 100, .flags = .critical, .name = "WebGL Hash", .description = "Hashed WebGL fingerprint." },
    .{ .id = .WebGLExtensions, .category = .WebGL, .value_type = .StringArray, .weight = 70, .flags = .stable_entropy, .name = "WebGL Extensions", .description = "Supported WebGL extensions." },
    .{ .id = .WebGLParameters, .category = .WebGL, .value_type = .String, .weight = 65, .flags = .stable_entropy, .name = "WebGL Parameters", .description = "Key WebGL parameters (JSON)." },
    .{ .id = .WebGLShaderPrecision, .category = .WebGL, .value_type = .String, .weight = 60, .flags = .stable_entropy, .name = "WebGL Shader Precision", .description = "Shader precision formats." },

    // ── Audio (43) ─────────────────────────────────────────────────────
    .{ .id = .AudioHash, .category = .Audio, .value_type = .Bytes, .weight = 95, .flags = .critical, .name = "Audio Hash", .description = "Hash of rendered audio fingerprint." },

    // ── Fonts (44) ─────────────────────────────────────────────────────
    .{ .id = .FontsHash, .category = .Fonts, .value_type = .Bytes, .weight = 95, .flags = .critical, .name = "Fonts Hash", .description = "Hash of installed fonts fingerprint." },

    // ── Platform (45-46) ──────────────────────────────────────────────
    .{ .id = .OperatingSystem, .category = .Platform, .value_type = .String, .weight = 75, .flags = .stable_required, .name = "Operating System", .description = "Operating system identifier." },
    .{ .id = .OSVersion, .category = .Platform, .value_type = .String, .weight = 55, .flags = .stable_entropy, .name = "OS Version", .description = "Operating system version." },

    // ── Storage (47-51) ──────────────────────────────────────────────
    .{ .id = .LocalStorage, .category = .Storage, .value_type = .Boolean, .weight = 30, .flags = .stable_required, .name = "Local Storage", .description = "Whether localStorage is available." },
    .{ .id = .SessionStorage, .category = .Storage, .value_type = .Boolean, .weight = 25, .flags = .stable_required, .name = "Session Storage", .description = "Whether sessionStorage is available." },
    .{ .id = .IndexedDB, .category = .Storage, .value_type = .Boolean, .weight = 25, .flags = .stable_required, .name = "IndexedDB", .description = "Whether IndexedDB is available." },
    .{ .id = .CacheStorage, .category = .Storage, .value_type = .Boolean, .weight = 20, .flags = .stable_required, .name = "Cache Storage", .description = "Whether Cache API is available." },
    .{ .id = .CookiesEnabled, .category = .Storage, .value_type = .Boolean, .weight = 20, .flags = .stable_required, .name = "Cookies Enabled", .description = "Whether cookies are enabled (redundant check)." },

    // ── Permissions (52-55) ──────────────────────────────────────────
    .{ .id = .NotificationPermission, .category = .Permissions, .value_type = .String, .weight = 20, .flags = .stable_required, .name = "Notification Permission", .description = "Notification permission status." },
    .{ .id = .GeolocationPermission, .category = .Permissions, .value_type = .String, .weight = 15, .flags = .stable_required, .name = "Geolocation Permission", .description = "Geolocation permission status." },
    .{ .id = .CameraPermission, .category = .Permissions, .value_type = .String, .weight = 15, .flags = .stable_required, .name = "Camera Permission", .description = "Camera permission status." },
    .{ .id = .MicrophonePermission, .category = .Permissions, .value_type = .String, .weight = 15, .flags = .stable_required, .name = "Microphone Permission", .description = "Microphone permission status." },

    // ── Media (56-61) ────────────────────────────────────────────────
    .{ .id = .AudioInputDevices, .category = .Media, .value_type = .StringArray, .weight = 30, .flags = .{ .stable = true }, .name = "Audio Input Devices", .description = "Available audio input devices." },
    .{ .id = .AudioOutputDevices, .category = .Media, .value_type = .StringArray, .weight = 25, .flags = .{ .stable = true }, .name = "Audio Output Devices", .description = "Available audio output devices." },
    .{ .id = .VideoInputDevices, .category = .Media, .value_type = .StringArray, .weight = 30, .flags = .{ .stable = true }, .name = "Video Input Devices", .description = "Available video input devices." },
    .{ .id = .SupportedCodecs, .category = .Media, .value_type = .StringArray, .weight = 50, .flags = .stable_entropy, .name = "Supported Codecs", .description = "Supported media codecs." },
    .{ .id = .MediaFormats, .category = .Media, .value_type = .StringArray, .weight = 45, .flags = .stable_entropy, .name = "Media Formats", .description = "Supported media formats." },
    .{ .id = .AudioFormats, .category = .Media, .value_type = .StringArray, .weight = 45, .flags = .stable_entropy, .name = "Audio Formats", .description = "Supported audio formats." },

    // ── Network (62-66) ──────────────────────────────────────────────
    .{ .id = .ConnectionType, .category = .Network, .value_type = .String, .weight = 45, .flags = .{ .stable = true }, .name = "Connection Type", .description = "Network connection type." },
    .{ .id = .ConnectionDownlink, .category = .Network, .value_type = .Float, .weight = 40, .flags = .{ .stable = true }, .name = "Connection Downlink", .description = "Effective bandwidth in Mbps." },
    .{ .id = .ConnectionEffectiveType, .category = .Network, .value_type = .String, .weight = 40, .flags = .{ .stable = true }, .name = "Connection Effective Type", .description = "Effective connection type (slow-2g/2g/3g/4g)." },
    .{ .id = .ConnectionRtt, .category = .Network, .value_type = .Integer, .weight = 35, .flags = .{ .stable = true }, .name = "Connection RTT", .description = "Round-trip time estimate." },
    .{ .id = .ConnectionSaveData, .category = .Network, .value_type = .Boolean, .weight = 20, .flags = .{ .stable = true }, .name = "Connection Save Data", .description = "Data saver mode enabled." },

    // ── Locale & Timezone (67-70) ────────────────────────────────────
    .{ .id = .Locale, .category = .Locale, .value_type = .String, .weight = 35, .flags = .stable_required, .name = "Locale", .description = "Browser locale string." },
    .{ .id = .Timezone, .category = .Timezone, .value_type = .String, .weight = 40, .flags = .stable_required, .name = "Timezone", .description = "IANA timezone identifier." },
    .{ .id = .TimezoneOffset, .category = .Timezone, .value_type = .Integer, .weight = 35, .flags = .stable_required, .name = "Timezone Offset", .description = "UTC offset in minutes." },
    .{ .id = .DateTimeFormat, .category = .Locale, .value_type = .String, .weight = 30, .flags = .stable_required, .name = "Date Time Format", .description = "Default date/time format locale." },

    // ── Battery (71-73) ──────────────────────────────────────────────
    .{ .id = .BatteryLevel, .category = .Battery, .value_type = .Float, .weight = 25, .flags = .{ .stable = true }, .name = "Battery Level", .description = "Battery charge level (0-1)." },
    .{ .id = .BatteryCharging, .category = .Battery, .value_type = .Boolean, .weight = 20, .flags = .{ .stable = true }, .name = "Battery Charging", .description = "Whether battery is charging." },
    .{ .id = .BatteryChargingTime, .category = .Battery, .value_type = .Integer, .weight = 15, .flags = .{ .stable = true }, .name = "Battery Charging Time", .description = "Time until fully charged (seconds)." },

    // ── Media Capabilities (74-76) ──────────────────────────────────
    .{ .id = .DecodeCapability, .category = .MediaCapabilities, .value_type = .String, .weight = 40, .flags = .stable_entropy, .name = "Decode Capability", .description = "Media decode capability (JSON)." },
    .{ .id = .EncodeCapability, .category = .MediaCapabilities, .value_type = .String, .weight = 40, .flags = .stable_entropy, .name = "Encode Capability", .description = "Media encode capability (JSON)." },
    .{ .id = .HDRSupport, .category = .MediaCapabilities, .value_type = .Boolean, .weight = 30, .flags = .stable_entropy, .name = "HDR Support", .description = "Whether HDR is supported." },

    // ── Crypto (77-78) ──────────────────────────────────────────────
    .{ .id = .CryptoSupport, .category = .Crypto, .value_type = .Boolean, .weight = 20, .flags = .stable_required, .name = "Crypto Support", .description = "Whether Web Crypto API is available." },
    .{ .id = .SubtleCrypto, .category = .Crypto, .value_type = .Boolean, .weight = 25, .flags = .stable_required, .name = "Subtle Crypto", .description = "Whether SubtleCrypto is available." },

    // ── Speech (79) ──────────────────────────────────────────────────
    .{ .id = .SpeechSynthesisVoices, .category = .Speech, .value_type = .StringArray, .weight = 35, .flags = .stable_entropy, .name = "Speech Synthesis Voices", .description = "Available speech synthesis voices." },

    // ── GPU (80-82) ──────────────────────────────────────────────────
    .{ .id = .GPUVendor, .category = .GPU, .value_type = .String, .weight = 70, .flags = .stable_entropy, .name = "GPU Vendor", .description = "GPU vendor (from canvas/WebGL)." },
    .{ .id = .GPURenderer, .category = .GPU, .value_type = .String, .weight = 75, .flags = .stable_entropy, .name = "GPU Renderer", .description = "GPU renderer (from canvas/WebGL)." },
    .{ .id = .GPUDriverVersion, .category = .GPU, .value_type = .String, .weight = 60, .flags = .stable_entropy, .name = "GPU Driver Version", .description = "GPU driver version." },

    // ── Performance (83-85) ──────────────────────────────────────────
    .{ .id = .HardwareConcurrencyPerformance, .category = .Performance, .value_type = .Integer, .weight = 40, .flags = .stable_entropy, .name = "HW Concurrency Perf", .description = "Hardware concurrency (performance API)." },
    .{ .id = .DeviceMemoryPerformance, .category = .Performance, .value_type = .Float, .weight = 35, .flags = .stable_entropy, .name = "Device Memory Perf", .description = "Device memory (performance API)." },
    .{ .id = .TimePrecision, .category = .Performance, .value_type = .Float, .weight = 30, .flags = .stable_entropy, .name = "Time Precision", .description = "Timer precision measurement." },

    // ── CSS (86-90) ──────────────────────────────────────────────────
    .{ .id = .CSSCustomProperties, .category = .Platform, .value_type = .Boolean, .weight = 20, .flags = .stable_required, .name = "CSS Custom Properties", .description = "Whether CSS custom properties are supported." },
    .{ .id = .CSSGridSupport, .category = .Platform, .value_type = .Boolean, .weight = 25, .flags = .stable_required, .name = "CSS Grid Support", .description = "Whether CSS Grid is supported." },
    .{ .id = .CSSFlexboxSupport, .category = .Platform, .value_type = .Boolean, .weight = 25, .flags = .stable_required, .name = "CSS Flexbox Support", .description = "Whether CSS Flexbox is supported." },
    .{ .id = .CSSContainerQuery, .category = .Platform, .value_type = .Boolean, .weight = 20, .flags = .stable_entropy, .name = "CSS Container Query", .description = "Whether CSS container queries are supported." },
    .{ .id = .CSSHasSelector, .category = .Platform, .value_type = .Boolean, .weight = 20, .flags = .stable_entropy, .name = "CSS Has Selector", .description = "Whether CSS :has() selector is supported." },

    // ── Browser Features (91-95) ──────────────────────────────────────
    .{ .id = .ServiceWorkerSupport, .category = .Platform, .value_type = .Boolean, .weight = 25, .flags = .stable_required, .name = "Service Worker Support", .description = "Whether Service Workers are supported." },
    .{ .id = .WebWorkerSupport, .category = .Platform, .value_type = .Boolean, .weight = 25, .flags = .stable_required, .name = "Web Worker Support", .description = "Whether Web Workers are supported." },
    .{ .id = .SharedWorkerSupport, .category = .Platform, .value_type = .Boolean, .weight = 20, .flags = .stable_entropy, .name = "Shared Worker Support", .description = "Whether Shared Workers are supported." },
    .{ .id = .WebSocketSupport, .category = .Platform, .value_type = .Boolean, .weight = 20, .flags = .stable_required, .name = "WebSocket Support", .description = "Whether WebSockets are supported." },
    .{ .id = .WebRTCSupport, .category = .Platform, .value_type = .Boolean, .weight = 25, .flags = .stable_entropy, .name = "WebRTC Support", .description = "Whether WebRTC is supported." },

    // ── Input (96-98) ──────────────────────────────────────────────────
    .{ .id = .KeyboardLayout, .category = .Platform, .value_type = .String, .weight = 30, .flags = .stable_entropy, .name = "Keyboard Layout", .description = "Keyboard layout identifier." },
    .{ .id = .PointerEvents, .category = .Platform, .value_type = .Boolean, .weight = 20, .flags = .stable_required, .name = "Pointer Events", .description = "Whether Pointer Events are supported." },
    .{ .id = .GamepadSupport, .category = .Platform, .value_type = .Boolean, .weight = 25, .flags = .stable_entropy, .name = "Gamepad Support", .description = "Whether Gamepad API is supported." },

    // ── Metadata (99-101) ──────────────────────────────────────────────
    .{ .id = .SchemaVersion, .category = .Metadata, .value_type = .Integer, .weight = 0, .flags = .required_entropy, .name = "Schema Version", .description = "Fingerprint schema version." },
    .{ .id = .SDKVersion, .category = .Metadata, .value_type = .String, .weight = 0, .flags = .required_entropy, .name = "SDK Version", .description = "Fingerprint SDK version." },
    .{ .id = .CollectionTimestamp, .category = .Metadata, .value_type = .Integer, .weight = 0, .flags = .required_entropy, .name = "Collection Timestamp", .description = "Unix timestamp of collection." },
};
