# 🧬 Fingerprint Engine

**High-performance browser fingerprinting SDK** — 102 signals · SHA-256 · similarity scoring · risk & entropy analysis

Written in [Zig 0.14.1](https://ziglang.org) with zero external dependencies.
A deterministic computation engine — the browser WASM module is the only
shipped artifact; fingerprint workers run as Docker containers.

---

## ✨ Features

| Capability | Details |
| ----------- | --------- |
| **Signals** | **102** browser features across 21 categories |
| **Hashing** | Deterministic SHA-256 — same input, same digest |
| **Binary** | Compact TLV format (`"FNGR"` magic) |
| **JSON** | Pretty-printed with registry name keys |
| **Normalization** | Type validation + bounds checking + warnings |
| **Similarity** | Feature-level (0–1) and fingerprint-level weighted scoring |
| **Entropy** | Shannon entropy — per-signal and aggregate bits |
| **Risk** | Multi-factor risk assessment (low/medium/high/critical) |
| **WASM** | `ReleaseSmall` — zero-setup browser SDK, built entirely by Zig |
| **Tests** | **274 passing** · 3 fuzz targets · 12 benchmarks |

---

## 🚀 Quick Start

### Browser (npm — WASM)

```html
<script src="https://cdn.jsdelivr.net/npm/@akshay2642005/fingerprint-sdk"></script>
<script>
  const result = await Fingerprint.collect();
  console.log('Digest:',  result.hex);      // "2e834b51c1db..."
  console.log('Signals:', result.signals);  // ~102
  console.log('Risk:',    result.risk);     // 0.0 – 1.0
  console.log('Entropy:', result.entropy);  // bits/signal
</script>
```

Or from TypeScript:

```typescript
import { FingerprintEngine, FeatureID } from '@akshay2642005/fingerprint-sdk';

const engine = await FingerprintEngine.create('/fingerprint.wasm');
engine.addString(FeatureID.UserAgent, navigator.userAgent);
const result = engine.compute();
console.log('Fingerprint:', result.digest);
```

---

## 📐 Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     Fingerprint Engine (Zig)                     │
│                                                                  │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│   │    model     │  │     core     │  │    serialization     │  │
│   │  FeatureID   │─▶│  hashing     │  │  binary TLV + JSON   │  │
│   │  registry    │  │  normalize   │  │  (codecs, no I/O)    │  │
│   │  fingerprint │  │  validate    │  └──────────────────────┘  │
│   └──────────────┘  │  similarity  │                            │
│                     │  entropy     │                            │
│                     │  risk        │                            │
│                     └──────┬───────┘                            │
│                            │                                    │
│                  ┌─────────▼─────────┐                          │
│                  │   browser (WASM)  │                          │
│                  │   validate ·      │                          │
│                  │   package         │                          │
│                  └───────────────────┘                          │
└──────────────────────────────────────────────────────────────────┘
        │
        ▼
SignalPackage (browser never produces the canonical digest)
        │
        ▼
Ingress → queue → workers → canonical fingerprint → fraud platform
```

**Everything depends inward.** `model` depends on nothing; `core` and
`serialization` depend on `model`; `browser` depends on `core`. The core is a
pure computation library — no HTTP, no queues, no databases, no business
logic. Workers run the same deterministic engine as containers.

---

## 📊 Stats

| Metric | Value |
| -------- | ------- |
| Browser signals | **102** across 21 categories |
| Tests | **274** (all passing) |
| Fuzz targets | **3** |
| Benchmarks | **12** |
| Zig version | **0.14.1** |
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

- [API Reference](api.md) — Zig engine modules, WASM exports, TypeScript SDK
- [Architecture Overview](architecture.md) — layers, dependency rule, event flows
- [`@akshay2642005/fingerprint-sdk`](https://www.npmjs.com/package/@akshay2642005/fingerprint-sdk) — npm package
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
