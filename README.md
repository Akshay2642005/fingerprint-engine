# Fingerprint Engine

[![CI](https://github.com/fingerprint/sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/fingerprint/sdk/actions/workflows/ci.yml)
[![Release](https://github.com/fingerprint/sdk/actions/workflows/release.yml/badge.svg)](https://github.com/fingerprint/sdk/actions/workflows/release.yml)
![Zig](https://img.shields.io/badge/Zig-0.16.0-%23F7A41D?logo=zig&logoColor=white)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A browser fingerprinting engine written in [Zig](https://ziglang.org) 0.16.0 —
zero-dependency, deterministic SHA-256 hashing, cross-platform.

## Features

- **37 feature signals** across 14 categories: navigator, screen, canvas, WebGL, audio, fonts, hardware, platform, storage, permissions, media, network, locale, timezone
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
# Unit tests
zig build test --summary all

# WebAssembly module
zig build wasm

# Native static library
zig build native
```

## SDK Integrations

- **TypeScript/JS** — `src/browser/bindings/` with typed WASM wrapper
- **C** — `src/server/api/c/fingerprint.h` public header
- **Node.js, Python, Rust** — planned (see [Integration Plan](specs/plan.md))

## Project Structure

```
.
├── src/
│   ├── core/          # Platform-independent fingerprint engine
│   │   ├── features/  # FeatureID, FeatureType, Registry, FeatureDefinition
│   │   ├── fingerprint/ # FeatureValue, Feature, Fingerprint, Metadata
│   │   ├── serialization/ # Binary TLV + JSON encode/decode
│   │   ├── normalization/ # Type validation, bounds checking
│   │   ├── hashing/   # SHA-256 feature/fingerprint digest
│   │   ├── validation/ # Required-feature checking
│   │   ├── similarity/ # Weighted per-feature comparison
│   │   ├── entropy/   # Shannon entropy analysis
│   │   └── risk/      # Risk assessment engine
│   ├── browser/       # WebAssembly SDK + JS bindings
│   └── server/        # Native C-ABI library + C header
├── tests/             # Test suite (282+ tests)
└── build.zig          # Zig build system
```

## License

MIT
