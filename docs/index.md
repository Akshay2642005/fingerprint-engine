# Fingerprint Engine

High-performance, enterprise-grade browser fingerprinting SDK written in **Zig 0.16.0**.

> **102 browser signals** · **SHA-256 hashing** · **Similarity scoring** · **Risk analysis** · **Entropy measurement**

## Quick Links

- [API Reference](api.md)
- [Architecture Overview](architecture.md)
- [GitHub Repository](https://github.com/Akshay2642005/fingerprint-engine)

## What is Fingerprint Engine?

Fingerprint Engine is a cross-platform library for collecting, hashing, and analyzing browser fingerprints. It powers fraud detection by generating deterministic, verifiable device identifiers from browser signals — without collecting any personally identifiable information (PII).

### Browser SDK (`@fingerprint/sdk`)

Drop a script tag into any HTML page to start collecting 102 browser signals and computing SHA-256 fingerprints:

```html
<script src="https://cdn.jsdelivr.net/npm/@fingerprint/sdk@0.1.1"></script>
<script>
  const fp = await Fingerprint.collect();
  console.log(fp.hex);   // "2e834b51c1db..."
  console.log(fp.risk);  // 0.61
</script>
```

### Server SDK (C ABI)

Link `libfingerprint.a` into your Go (cgo), Rust, or C application:

```c
#include "fingerprint.h"

FingerprintEngine* engine = fingerprint_engine_create();
fingerprint_engine_add_string(engine, FINGERPRINT_FEATURE_USER_AGENT, "Mozilla/5.0...", 14);

uint8_t digest[32];
fingerprint_engine_compute(engine, digest);

int risk = fingerprint_engine_risk(engine);
int entropy = fingerprint_engine_entropy(engine);
fingerprint_engine_destroy(engine);
```

---

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  Browser    │──▶  │   Core       │──▶  │  Backend     │
│  JS/TS      │     │   WASM/Zig   │     │  Go + C FFI  │
│  Collectors │     │   Compute    │     │  Matching    │
│  102 sigs   │     │   SHA-256    │     │  Risk/Entropy│
└─────────────┘     └──────────────┘     └──────────────┘
```

## Stats

| Metric | Value |
| -------- | ------- |
| Browser signals | **102** across 21 categories |
| Tests | **290** (all passing) |
| WASM binary size | **37 KB** (ReleaseSmall) |
| Fuzz targets | **8** |
| Benchmarks | **12** |
| Zig version | **0.16.0** |
| License | MIT |

## Key Design Principles

- **No PII collection** — IP, GPS, camera/microphone, browsing history, cookies content are OFF-LIMITS
- **Deterministic** — same input always produces the same SHA-256 digest
- **Zero heap allocation** in core algorithms (hashing, normalization, risk)
- **Platform-independent** — WASM binary works identically on all platforms
- **Cross-platform** — browser (WASM), server (C ABI), any language via FFI

## Categories

| # | Category | Signals |
| --- | ---------- | --------- |
| 1 | Navigator | UserAgent, Language, Platform, Vendor, Product, AppName, AppVersion, CookieEnabled, DoNotTrack, PDF Viewer, etc. |
| 2 | Screen | Width, Height, ColorDepth, PixelDepth, DevicePixelRatio, Orientation, etc. |
| 3 | Hardware | DeviceMemory, CPU cores, architecture, acceleration, touch support |
| 4 | Canvas | Text, gradient, shape rendering → hash |
| 5 | WebGL | Vendor, Renderer, Version, Extensions, Parameters, Shader Precision |
| 6 | Audio | AudioContext processing → hash |
| 7 | Fonts | 80+ font detection via canvas |
| 8 | Storage | localStorage, sessionStorage, IndexedDB, CacheStorage, Cookies |
| 9 | Network | Connection type, downlink, RTT, save-data, effective type |
| 10 | Battery | Level, charging status, charging time |
| 11 | Media | H.264/VP9/AV1/AAC/Opus/FLAC codec support, HDR |
| 12 | Permissions | Notification, geolocation, camera, microphone |
| 13 | Speech | TTS voice enumeration |
| 14 | Input | Keyboard layout, pointer events, gamepad support |
| 15 | Browser Features | Service Worker, Web Worker, Shared Worker, WebSocket, WebRTC |
| 16 | CSS | Custom Properties, Grid, Flexbox, Container Queries, :has() |
| 17 | Crypto | Crypto API, SubtleCrypto availability |
| 18 | GPU | Vendor, renderer, driver version |
| 19 | Performance | Hardware concurrency, device memory, time precision |
| 20 | OS | Platform, architecture, OS version |
| 21 | Metadata | Schema version, SDK version, collection timestamp |

## Repository

- **GitHub**: [Akshay2642005/fingerprint-engine](https://github.com/Akshay2642005/fingerprint-engine)
- **npm**: [`@fingerprint/sdk`](https://www.npmjs.com/package/@fingerprint/sdk)
- **License**: MIT
