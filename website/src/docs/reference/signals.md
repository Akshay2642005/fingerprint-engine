---
title: "Signals"
description: "The 102-signal registry across 21 categories: FeatureID, value type, weight, and flags for every observable the engine hashes."
category: "reference"
order: 2
crumbs: ["reference", "signals"]
---

# Signals

A **signal** is a single observed browser property — one feature id plus one
value, e.g. `UserAgent`, the canvas hash, or the WebGL renderer string. The
engine collects **102 signals across 21 categories**. The complete registry
is the comptime-ordered `definitions` array in `src/model/definitions.zig`,
keyed by the `FeatureID` enum in `src/model/feature.zig`.

Every definition carries five fields:

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `id` | `FeatureID` | Stable `u16` tag, 0–101. |
| `category` | `FeatureCategory` | One of the 21 categories below. |
| `value_type` | `FeatureType` | `Boolean`, `Integer`, `Float`, `String`, `Bytes`, `StringArray`, `IntegerArray`, `FloatArray`, `BytesArray`. |
| `weight` | `u8` | Relative contribution (0–100) used by similarity scoring. |
| `flags` | `FeatureFlags` | `stable`, `required`, `high_entropy`, `sensitive`. |

The `FeatureID` tags are part of the ABI: they appear verbatim on the wire in
the TLV encoding and are sorted before hashing. Renumbering a tag is a
breaking contract change. The `FeatureID` enum's `Count` sentinel and the
`feature_count = 102` come from the enum itself, so the registry cannot drift
from the model.

## The 21 categories

| Category | Example signals | Value type(s) |
| -------- | --------------- | ------------- |
| Navigator | `UserAgent`, `Language`, `Languages`, `Vendor`, `AppVersion`, `CookieEnabled`, `Timezone` | String, StringArray, Boolean |
| Screen | `ScreenWidth`, `ScreenHeight`, `ColorDepth`, `DevicePixelRatio`, `ScreenOrientation` | Integer, Float, String |
| Hardware | `HardwareConcurrency`, `DeviceMemory`, `MaxTouchPoints`, `CpuCores`, `TouchSupport` | Integer, Float, Boolean, String |
| Canvas | `CanvasHash` | Bytes |
| WebGL | `WebGLRenderer`, `WebGLVendor`, `WebGLHash`, `WebGLExtensions` | String, Bytes, StringArray |
| Audio | `AudioHash` | Bytes |
| Fonts | `FontsHash` | Bytes |
| Storage | `LocalStorage`, `SessionStorage`, `IndexedDB`, `CacheStorage`, `CookiesEnabled` | Boolean |
| Network | `ConnectionType`, `ConnectionDownlink`, `ConnectionRtt`, `ConnectionSaveData` | String, Float, Integer, Boolean |
| Battery | `BatteryLevel`, `BatteryCharging`, `BatteryChargingTime` | Float, Boolean, Integer |
| Media | `SupportedCodecs`, `AudioInputDevices`, `DecodeCapability`, `HDRSupport` | StringArray, String, Boolean |
| Permissions | `NotificationPermission`, `GeolocationPermission`, `CameraPermission` | String |
| Speech | `SpeechSynthesisVoices` | StringArray |
| Input | `KeyboardLayout`, `PointerEvents`, `GamepadSupport` | String, Boolean |
| Browser APIs | `ServiceWorkerSupport`, `WebSocketSupport`, `WebRTCSupport` | Boolean |
| CSS | `CSSGridSupport`, `CSSContainerQuery`, `CSSHasSelector` | Boolean |
| Crypto | `CryptoSupport`, `SubtleCrypto` | Boolean |
| GPU | `GPUVendor`, `GPURenderer`, `GPUDriverVersion` | String |
| Performance | `TimePrecision`, `HardwareConcurrencyPerformance` | Float, Integer |
| OS | `OperatingSystem`, `OSVersion` | String |
| Metadata | `SchemaVersion`, `SDKVersion`, `CollectionTimestamp` | Integer, String |

## Category references

### Navigator

Identity and environment signals drawn from `navigator.*`. High-weight,
`stable_required` features — `UserAgent` (weight 90, `critical`) alone is
the single most identifying string in the package. Includes the primary
`Language` and preferred `Languages`, `Vendor`/`VendorSub`, `Product`/
`ProductSub`, `AppName`/`AppVersion`, `CookieEnabled`, `DoNotTrack`, and
`PdfViewerEnabled`. The `->Timezone`/`Locale` family (timezone IANA id,
UTC offset, locale, date/time format) is grouped here.

### Screen

Resolution and viewport geometry: `ScreenWidth`/`ScreenHeight`,
`AvailableWidth`/`AvailableHeight`, `ColorDepth`/`PixelDepth`,
`DevicePixelRatio`, the live viewport `InnerWidth`/`InnerHeight`, window
`OuterWidth`/`OuterHeight`, and `ScreenOrientation`. Permutation of these
dimensions is a strong device classifier even when the browser is spoofing.

### Hardware

Physical capability signals: `HardwareConcurrency`, `MaxTouchPoints`,
`DeviceMemory` (fractional GB) and its integer `DeviceRam` twin,
`CpuClass`/`CpuCores`/`CpuArchitecture`/`PlatformArchitecture`,
`HardwareAcceleration`, and `TouchSupport`. All flagged `stable_entropy`.

### Canvas

A single signal: `CanvasHash` — the SHA-256 of a rendered canvas, weight
100 and `critical`. The engine hashes the *digest* the SDK already computed;
it never renders pixels itself.

### WebGL

GPU capability surface: `WebGLVendor`, `WebGLRenderer` (weight 90,
`critical`), `WebGLVersion`, `WebGLHash` (weight 100, `critical`),
`WebGLExtensions` (StringArray), `WebGLParameters`, and
`WebGLShaderPrecision`.

### Audio

A single signal: `AudioHash` — the hash of a rendered audio fingerprint,
weight 95, `critical`.

### Fonts

A single signal: `FontsHash` — the hash of the installed-fonts
fingerprint, weight 95, `critical`.

### Storage

Availability booleans: `LocalStorage`, `SessionStorage`, `IndexedDB`,
`CacheStorage`, and the redundant `CookiesEnabled` check. All
`stable_required`, lower weight.

### Network

From `navigator.connection`: `ConnectionType`, `ConnectionDownlink` (Mbps),
`ConnectionEffectiveType` (`slow-2g`/`2g`/`3g`/`4g`), `ConnectionRtt`, and
`ConnectionSaveData`. Network-attribution features are deliberately *not*
`critical` — they are useful but not stable enough to dominate the digest.

### Battery

`BatteryLevel` (0–1), `BatteryCharging`, `BatteryChargingTime`. Marked
stable but low-weight; battery state is environment-sensitive.

### Media

Enumerate.device- and codec-derived signals: `AudioInputDevices`,
`AudioOutputDevices`, `VideoInputDevices`, `SupportedCodecs`,
`MediaFormats`, `AudioFormats`, plus the MediaCapabilities trio
`DecodeCapability`, `EncodeCapability`, and `HDRSupport`.

### Permissions

Current permission states: `NotificationPermission`,
`GeolocationPermission`, `CameraPermission`, `MicrophonePermission`. Each is
a `stable_required` String (e.g. `granted`, `denied`, `prompt`).

### Speech

A single signal: `SpeechSynthesisVoices` — the available speech-synthesis
voice list as a `StringArray`.

### Input

Input-capability signals: `KeyboardLayout`, `PointerEvents`, `GamepadSupport`.

### Browser APIs

Feature-detection booleans for platform surfaces: `ServiceWorkerSupport`,
`WebWorkerSupport`, `SharedWorkerSupport`, `WebSocketSupport`,
`WebRTCSupport`.

### CSS

CSS feature detection: `CSSCustomProperties`, `CSSGridSupport`,
`CSSFlexboxSupport`, `CSSContainerQuery`, and the `:has()` selector signal
`CSSHasSelector`.

### Crypto

`CryptoSupport` and `SubtleCrypto` — whether the Web Crypto and
`crypto.subtle` surfaces are available.

### GPU

`GPUVendor`, `GPURenderer`, `GPUDriverVersion` — GPU attribution derived
from canvas/WebGL but bucketed separately for higher weight.

### Performance

Measurement-derived signals: `HardwareConcurrencyPerformance`,
`DeviceMemoryPerformance`, and `TimePrecision` (timer resolution as a
fingerprinting surface).

### OS

High-entropy platform identity: `OperatingSystem` (weight 75,
`stable_required`) and `OSVersion` (weight 55, `stable_entropy`).

### Metadata

`SchemaVersion`, `SDKVersion`, and `CollectionTimestamp` — zero-weight
(`required_entropy`) bookkeeping signals that identify the schema, SDK
build, and collection moment. `SchemaVersion` and `SDKVersion` drive the
version gate; `CollectionTimestamp` is hashed like any other value.

## Types and wire sizes

Each `FeatureValue` variant encodes to a fixed, little-endian wire shape:

| Type | Wire content |
| ---- | ------------ |
| `Boolean` | 1 byte (`0`/`1`) |
| `Integer` | `i64` LE |
| `Float` | `u64` LE (bit-cast of the `f64`) |
| `String` / `Bytes` | `u32` length LE + bytes |
| `StringArray` / `BytesArray` | `u32` count LE + per-item `u32` length + bytes |
| `IntegerArray` / `FloatArray` | `u32` count LE + per-item fixed 8-byte LE |

See [Serialization](../internals/serialization.md) and
[Hashing](../internals/hashing.md) for how these values reach the wire and
the digest.
