# Fingerprint Engine

[![CI](https://github.com/Akshay2642005/fingerprint-engine/actions/workflows/ci.yml/badge.svg)](https://github.com/Akshay2642005/fingerprint-engine/actions/workflows/ci.yml)
[![Release](https://github.com/Akshay2642005/fingerprint-engine/actions/workflows/release.yml/badge.svg)](https://github.com/Akshay2642005/fingerprint-engine/actions/workflows/release.yml)
![Zig](https://img.shields.io/badge/Zig-0.16.0-%23F7A41D?logo=zig&logoColor=white)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A browser fingerprinting engine written in [Zig](https://ziglang.org) 0.16.0 —
zero-dependency, deterministic SHA-256 hashing, cross-platform.

## Features

- **102 browser signals** across 21 categories: navigator, screen, canvas, WebGL, audio, fonts, hardware, platform, storage, permissions, media, network, locale, timezone, battery, speech synthesis, input devices, codecs, HDR, pointer, gamepad
- **Deterministic hashing** — SHA-256 with type-tag prefixes prevents cross-type collisions
- **Incremental hasher** — absorb features one at a time, final digest matches batch hash
- **Serialization** — compact TLV binary (`"FNGR"` magic) and human-readable JSON
- **Normalization** — type and bounds validation with actionable warnings
- **Similarity scoring** — weighted per-feature comparison (0.0–1.0)
- **Entropy analysis** — Shannon entropy per feature and weighted fingerprint entropy
- **Risk assessment** — quantifies missing features, bound violations, coverage, entropy deficit
- **WASM module** — browser-ready WebAssembly SDK
- **Native library** — C-compatible static library for backend integration

## Build

```bash
# Unit tests (290+ tests)
zig build test --summary all

# WebAssembly module (zig-out/bin/fingerprint.wasm)
zig build wasm

# Native static library (zig-out/lib/)
zig build native
```

## Quick Start (Browser)

```html
<script src="https://cdn.jsdelivr.net/npm/@akshay2642005/fingerprint-sdk"></script>
<script>
  const sdk = await Fingerprint.create();
  const fp = await sdk.collect();
  const hash = sdk.hashFingerprint(fp);
  console.log('Fingerprint:', hash);
  console.log('Risk:', sdk.computeRisk(fp));
  console.log('Entropy:', sdk.computeEntropy(fp));
</script>
```

## SDK Packages

| Package | Platform | Status |
| --------- | ---------- | -------- |
| [`@akshay2642005/fingerprint-sdk`](https://www.npmjs.com/package/@akshay2642005/fingerprint-sdk) | npm (browser WASM) | ✅ Published |

## Project Structure

```
.
├── src/
│   ├── core/              # Platform-independent fingerprint engine
│   │   ├── features/      # FeatureID (102), FeatureType (9), Registry, FeatureDefinition
│   │   ├── fingerprint/   # FeatureValue, Feature, Fingerprint, Metadata
│   │   ├── serialization/ # Binary TLV + JSON encode/decode
│   │   ├── normalization/ # Type validation, bounds checking
│   │   ├── hashing/       # SHA-256 feature/fingerprint digest
│   │   ├── validation/    # Required-feature checking
│   │   ├── similarity/    # Weighted per-feature comparison
│   │   ├── entropy/       # Shannon entropy analysis
│   │   └── risk/          # Risk assessment engine
│   ├── browser/           # WebAssembly SDK + JS bindings + collectors
│   │   ├── wasm/          # Zig WASM exports (hash, normalize, risk, entropy)
│   │   ├── bindings/      # TypeScript wrapper, types, demo page
│   │   └── collectors/    # 11 browser signal collectors (canvas, webgl, audio, etc.)
│   └── server/            # Native C-ABI library + C header + API bindings
│       ├── native/        # Zig native library exports
│       └── api/           # C header, Rust SDK, Python SDK
├── tests/                 # 290+ tests (features, serialization, hashing, etc.)
├── benchmark/             # Performance benchmarks (12 targets)
├── packages/              # Distribution packages
│   └── browser/           # npm build pipeline
├── docs/                  # API docs, architecture docs
└── build.zig              # Zig build system
```

## Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│                     Fingerprint Engine                            │
│                                                                   │
│   ┌──────────────┐  ┌──────────┐  ┌───────────┐  ┌─────────────┐  │
│   │ Collectors   │  │ WASM     │  │ Native    │  │ Packages    │  │
│   │ (JS/TS)      │  │ (Zig)    │  │ C ABI     │  │ npm/PyPI/   │  │
│   │ 11 collectors│─▶│ hash     │  │ matching  │  │ crates.io   │  │
│   │ 102 signals  │  │ normalize│  │ lookup    │  └─────────────┘  │
│   └──────────────┘  │ risk     │  │ entropy   │                   │
│                     │ entropy  │  │ risk      │                   │
│                     └──────────┘  └───────────┘                   │
│                                                                   │
│   ┌──────────────────────────────────────────────────────────┐    │
│   │                  Core Engine (Zig)                       │    │
│   │  features · fingerprint · hashing · normalization        │    │
│   │  serialization · similarity · entropy · risk             │    │
│   └──────────────────────────────────────────────────────────┘    │
└───────────────────────────────────────────────────────────────────┘
```

## License

MIT
