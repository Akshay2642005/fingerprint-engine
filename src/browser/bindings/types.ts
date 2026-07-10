/**
 * Fingerprint Engine — TypeScript type definitions.
 *
 * Mirrors the Zig enums from src/core/features/model.zig
 * and src/core/fingerprint/value.zig.
 */

/** FeatureID enum — all 37 browser fingerprint signals. */
export enum FeatureID {
  // Navigator signals
  CookieEnabled = 0,
  UserAgent = 1,
  Language = 2,
  Languages = 3,
  Platform = 4,
  Vendor = 5,
  VendorSub = 6,
  Product = 7,
  ProductSub = 8,
  AppName = 9,
  AppVersion = 10,
  DoNotTrack = 11,
  HardwareConcurrency = 12,
  MaxTouchPoints = 13,
  DeviceMemory = 14,
  Timezone = 15,
  TimezoneOffset = 16,

  // Screen signals
  ScreenWidth = 17,
  ScreenHeight = 18,
  ScreenAvailWidth = 19,
  ScreenAvailHeight = 20,
  ScreenColorDepth = 21,
  ScreenPixelDepth = 22,
  ScreenDevicePixelRatio = 23,

  // Window signals
  WindowInnerWidth = 24,
  WindowInnerHeight = 25,
  WindowOuterWidth = 26,
  WindowOuterHeight = 27,

  // Font & media signals
  Fonts = 28,
  MediaDevices = 29,

  // Canvas & WebGL
  CanvasFingerprint = 30,
  WebGLVendor = 31,
  WebGLRenderer = 32,
  WebGLVersion = 33,

  // Audio & network
  AudioFingerprint = 34,
  ConnectionType = 35,
  ConnectionDownlink = 36,
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
