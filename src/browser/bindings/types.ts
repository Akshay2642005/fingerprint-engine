/**
 * Fingerprint Engine — TypeScript type definitions.
 *
 * IMPORTANT: This file is AUTO-SYNCED from src/core/features/model.zig
 * Do NOT edit manually — values must match the Zig enum exactly.
 */

/** FeatureID enum — all 102 browser fingerprint signals. */
export enum FeatureID {
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
}

/** FeatureType enum — 9 value types a feature can hold. */
export enum FeatureType {
  Boolean = 0,
  Integer = 1,
  Float = 2,
  String = 3,
  Bytes = 4,
  StringArray = 5,
  IntegerArray = 6,
  FloatArray = 7,
  BytesArray = 8,
}

/** Union of all possible feature value types. */
export type FeatureValue =
  | { type: FeatureType.Boolean; value: boolean }
  | { type: FeatureType.Integer; value: number }
  | { type: FeatureType.Float; value: number }
  | { type: FeatureType.String; value: string }
  | { type: FeatureType.Bytes; value: Uint8Array }
  | { type: FeatureType.StringArray; value: string[] }
  | { type: FeatureType.IntegerArray; value: number[] }
  | { type: FeatureType.FloatArray; value: number[] }
  | { type: FeatureType.BytesArray; value: Uint8Array[] };

/** A single feature with its ID and value. */
export interface Feature {
  id: FeatureID;
  value: FeatureValue;
}

/** The 32-byte SHA-256 digest produced by fingerprint computation. */
export type FingerprintDigest = Uint8Array & { readonly __brand: 'FingerprintDigest' };

/** Error codes returned by WASM exports. */
export enum ErrorCode {
  Success = 0,
  BufferFull = 1,
  InvalidFeatureId = 2,
  InvalidValueType = 3,
  NotInitialized = 4,
}

/** Result of a fingerprint operation. */
export interface FingerprintResult {
  /** 0 on success, error code on failure. */
  code: number;
  /** Human-readable error message (empty on success). */
  error: string;
}

/** Serialized digest result with metadata. */
export interface ComputeResult {
  /** The 32-byte SHA-256 digest. */
  digest: FingerprintDigest;
  /** Number of features used in the computation. */
  featureCount: number;
}

/** Raw device information collected by JavaScript. */
export interface RawDeviceInfo {
  // Navigator
  userAgent?: string;
  language?: string;
  languages?: string[];
  platform?: string;
  vendor?: string;
  product?: string;
  appName?: string;
  appVersion?: string;
  cookieEnabled?: boolean;
  doNotTrack?: string;
  hardwareConcurrency?: number;
  maxTouchPoints?: number;
  deviceMemory?: number;

  // Screen
  screenWidth?: number;
  screenHeight?: number;
  availableWidth?: number;
  availableHeight?: number;
  colorDepth?: number;
  pixelDepth?: number;
  devicePixelRatio?: number;
  innerWidth?: number;
  innerHeight?: number;
  outerWidth?: number;
  outerHeight?: number;
  screenOrientation?: string;

  // Hardware
  cpuClass?: string;
  touchSupport?: boolean;

  // Canvas (raw pixels)
  canvasData?: Uint8Array;

  // WebGL
  webglVendor?: string;
  webglRenderer?: string;
  webglVersion?: string;
  webglExtensions?: string[];
  webglParameters?: Record<string, unknown>;
  webglShaderPrecision?: Record<string, number>;

  // Audio (raw samples)
  audioData?: Uint8Array;

  // Platform
  operatingSystem?: string;

  // Storage
  localStorage?: boolean;
  sessionStorage?: boolean;
  indexedDB?: boolean;
  cacheStorage?: boolean;

  // Network
  connectionType?: string;
  connectionDownlink?: number;
  connectionEffectiveType?: string;
  connectionRtt?: number;
  connectionSaveData?: boolean;

  // Locale & Timezone
  locale?: string;
  timezone?: string;
  timezoneOffset?: number;

  // Battery
  batteryLevel?: number;
  batteryCharging?: boolean;
  batteryChargingTime?: number;

  // Crypto
  cryptoSupport?: boolean;
  subtleCrypto?: boolean;

  // GPU
  gpuVendor?: string;
  gpuRenderer?: string;

  // CSS
  cssCustomProperties?: boolean;
  cssGridSupport?: boolean;
  cssFlexboxSupport?: boolean;

  // Browser Features
  serviceWorkerSupport?: boolean;
  webWorkerSupport?: boolean;
  webRTCSupport?: boolean;

  // Input
  pointerEvents?: boolean;
  gamepadSupport?: boolean;
}
