# 🧬 Fingerprint Engine

**High-performance browser fingerprinting SDK** — 102 signals · SHA-256 · similarity scoring · risk & entropy analysis

Written in [Zig 0.16.0](https://ziglang.org) with zero external dependencies.  
Powers agentic fraud detection platforms via WASM (browser) and C ABI (server).

---

## ✨ Features

| Capability | Details |
| ----------- | --------- |
| **Signals** | **102** browser features across 21 categories |
| **Hashing** | Deterministic SHA-256 — same input, same digest |
| **Binary** | Compact TLV format (4+2n bytes per feature) |
| **JSON** | Pretty-printed with registry name keys |
| **Normalization** | Type validation + bounds checking + warnings |
| **Similarity** | Feature-level (0–1) and fingerprint-level weighted scoring |
| **Entropy** | Shannon entropy — per-signal and aggregate bits |
| **Risk** | Multi-factor risk assessment (low/medium/high/critical) |
| **WASM** | **37 KB** with `ReleaseSmall` — zero-setup browser SDK |
| **C ABI** | Static library + header — link from Go (cgo), C, C++, Zig, etc. |
| **Tests** | **290 passing** · 8 fuzz targets · 12 benchmarks |

---

## 🚀 Quick Start

### Browser (npm — 37 KB WASM)

```html
<script src="https://cdn.jsdelivr.net/npm/@fingerprint/sdk@0.1.1"></script>
<script>
  const fp = await Fingerprint.collect();
  console.log('Digest:',  fp.hex);         // "2e834b51c1db..."
  console.log('Signals:', fp.features.length); // ~102
  console.log('Risk:',    fp.risk);         // 0.0 – 1.0
  console.log('Entropy:', fp.entropy);      // bits/signal
</script>
```

### Server (Go via C ABI)

```go
// #cgo LDFLAGS: -L. -lfingerprint
// #include "fingerprint.h"
import "C"

engine := C.fingerprint_engine_create()
defer C.fingerprint_engine_destroy(engine)

C.fingerprint_engine_add_feature(engine,
    C.FINGERPRINT_FEATURE_USER_AGENT,
    C.FINGERPRINT_TYPE_STRING,
    C.CString("Mozilla/5.0..."), 14)

var digest [32]C.uint8_t
C.fingerprint_engine_compute(engine, &digest[0])

risk := int(C.fingerprint_engine_risk(engine))
entropy := int(C.fingerprint_engine_entropy(engine))
```

### C / C++ / Zig (any FFI language)

```c
// Same C ABI — works with any language that supports C FFI
#include "fingerprint.h"

FingerprintEngine* engine = fingerprint_engine_create();
fingerprint_engine_add_feature(engine,
    FINGERPRINT_FEATURE_USER_AGENT,
    FINGERPRINT_TYPE_STRING,
    "Mozilla/5.0...", 14);

uint8_t digest[32];
fingerprint_engine_compute(engine, digest);
fingerprint_engine_destroy(engine);
```

---

## 📐 Architecture

```
┌──────────────┐       ┌──────────────────┐       ┌────────────────┐
│   Browser    │  WASM  │   Core Engine    │  C    │    Backend     │
│  ─────────── │──────▶│  ──────────────  │──────▶│  ───────────── │
│  JS/TS       │       │  Features (102)  │  FFI  │  Go (cgo)      │
│  Collectors  │       │  SHA-256        │       │  Matching      │
│  Canvas      │       │  Normalization  │       │  Risk/Entropy  │
│  WebGL       │       │  Similarity     │       │  Storage       │
│  Audio/Fonts │       │  Serialization  │       │  API Layer     │
│  + 17 more   │       │  [Zig 0.16.0]   │       │  [Fraud Platform]
└──────────────┘       └──────────────────┘       └────────────────┘
```

**Core engine** is a pure computation library — no database, no gRPC, no HTTP.  
**Backend** (your Go application) handles storage, routing, and business logic via C FFI.

---

## 📊 Stats

| Metric | Value |
| -------- | ------- |
| Browser signals | **102** across 21 categories |
| Tests | **290** (all passing) |
| WASM binary | **37 KB** (`ReleaseSmall`) |
| Fuzz targets | **8** |
| Benchmarks | **12** |
| Zig version | **0.16.0** |
| License | MIT |

---

## 🗂️ 21 Signal Categories

| # | Category | Key Signals |
| --- | ---------- | ------------ |
| 1 | Navigator | UserAgent, Language, Platform, Vendor, Product, AppName, AppVersion, CookieEnabled, DoNotTrack, PdfViewerEnabled |
| 2 | Screen | Width, Height, ColorDepth, PixelDepth, DevicePixelRatio, Orientation |
| 3 | Hardware | DeviceMemory, CPU cores, CPU architecture, hardware acceleration, touch support |
| 4 | Canvas | Text/gradient/shape rendering ➜ hash |
| 5 | WebGL | Vendor, Renderer, Version, Extensions, Parameters, Shader Precision |
| 6 | Audio | AudioContext processing ➜ hash |
| 7 | Fonts | 80+ font detection via canvas text metrics |
| 8 | Storage | localStorage, sessionStorage, IndexedDB, CacheStorage, Cookies |
| 9 | Network | Connection type, downlink, RTT, save-data, effective type |
| 10 | Battery | Level, charging status, charging time remaining |
| 11 | Media | H.264/VP9/AV1/AAC/Opus/FLAC codec support, HDR |
| 12 | Permissions | Notification, geolocation, camera, microphone status |
| 13 | Speech | TTS voice enumeration |
| 14 | Input | Keyboard layout, pointer events, gamepad support |
| 15 | Browser | Service Worker, Web Worker, WebSocket, WebRTC, Shared Worker |
| 16 | CSS | Custom Properties, Grid, Flexbox, Container Queries, `:has()` |
| 17 | Crypto | Crypto API, SubtleCrypto availability |
| 18 | GPU | Vendor, renderer, driver version |
| 19 | Performance | Hardware concurrency, device memory, time precision |
| 20 | OS | Platform, architecture, OS version |
| 21 | Metadata | Schema version, SDK version, collection timestamp |

---

## 📖 Documentation

- [API Reference](api.md) — all functions, types, and SDK documentation
- [Architecture Overview](architecture.md) — design decisions and module layout
- [`@fingerprint/sdk`](https://www.npmjs.com/package/@fingerprint/sdk) — npm package
- [GitHub](https://github.com/Akshay2642005/fingerprint-engine) — source code

---

## 🔒 Privacy

**No PII is ever collected.** The engine never accesses:

- IP addresses or geo-location
- Camera or microphone streams
- Browsing history or stored cookies content
- File system or personal documents
- User credentials or form data

All signals are **non-identifying** browser characteristics that can be gathered ephemerally.

---

> **MIT Licensed** · Built with [Zig](https://ziglang.org) · Designed for [Akshay2642005/fingerprint-engine](https://github.com/Akshay2642005/fingerprint-engine)
