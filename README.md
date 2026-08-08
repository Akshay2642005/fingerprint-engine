# Fingerprint Engine

[![CI](https://github.com/Akshay2642005/fingerprint-engine/actions/workflows/ci.yml/badge.svg)](https://github.com/Akshay2642005/fingerprint-engine/actions/workflows/ci.yml)
[![Release](https://github.com/Akshay2642005/fingerprint-engine/actions/workflows/release.yml/badge.svg)](https://github.com/Akshay2642005/fingerprint-engine/actions/workflows/release.yml)
![Zig](https://img.shields.io/badge/Zig-0.14.1-%23F7A41D?logo=zig&logoColor=white)
[![npm](https://img.shields.io/npm/v/@akshay2642005/fingerprint-sdk)](https://www.npmjs.com/package/@akshay2642005/fingerprint-sdk)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A deterministic, zero-dependency distributed fingerprint engine written in
[Zig](https://ziglang.org) 0.14.1.

The engine is a **reusable deterministic computation engine**, not a service:
canonical fingerprints are computed server-side by stateless Zig workers that
run `engine.process()` over a versioned `SignalPackage`. The browser never
computes the canonical digest — the TypeScript SDK only collects signals,
serializes them into a `SignalPackage` v2 body, and POSTs it to an ingress
endpoint. The engine knows nothing about transport, queues, databases, or
business logic; adapters (loopback, TCP, AMQP) live outside it. Everything
builds through `zig build`.

## Features

- **102 browser signals** across 21 categories: navigator, screen, canvas, WebGL, audio, fonts, hardware, platform, storage, permissions, media, network, locale, timezone, battery, speech synthesis, input devices, codecs, HDR, pointer, gamepad
- **Deterministic hashing** — SHA-256 with type-tag prefixes prevents cross-type collisions
- **Incremental hasher** — absorb features one at a time, final digest matches batch hash
- **Serialization** — compact TLV binary (`"FNGR"` magic) and human-readable JSON
- **Normalization** — type and bounds validation with actionable warnings
- **Similarity scoring** — weighted per-feature comparison (0.0–1.0)
- **Entropy analysis** — Shannon entropy per feature and weighted fingerprint entropy
- **Risk assessment** — quantifies missing features, bound violations, coverage, entropy deficit
- **Deterministic engine** — versioned `Operation`/`Status`, immutable `Request`, caller-owned `Response`, comptime dispatch — no io/transport code inside
- **Async IO primitives** — arena-backed `Message`/`MessagePool`, `RingBuffer`, typed `Channel`, `Executor`, FPKG `Frame`, fixed-buffer `Reader`/`Writer`, comptime `Dispatcher`
- **Worker executable** — `--transport=loopback|tcp`, `--publish=none|amqp`, ships as a Docker container
- **Browser SDK** — hand-written TypeScript (`dist/` from `zig build clients:browser`): collect → `SignalPackage` v2 → POST to the ingress, plus `assertAllowed()`/`onSessionBlocked()` middleware for the fraud platform's blocking decisions

## Build

Requires [Zig 0.14.1](https://ziglang.org/download/). Everything builds
through `zig build` steps — no scripts, no separate toolchains. Node is only
needed for the documented exceptions: the browser SDK's `tsc` step and the
TS test suite.

```bash
# Unit + integration/e2e tests
zig build test --summary all

# Only unit tests matching a filter
zig build test -- "hashing"

# Integration and e2e smoke tests only
zig build test-integration

# WebAssembly infra artifact (zig-out/bin/fingerprint.wasm)
zig build wasm

# Worker executable (zig-out/bin/worker)
zig build worker --release=safe

# Performance benchmarks
zig build bench

# Browser npm package (src/clients/browser/dist/)
#   generator → tsc → dist surface guard; ingress URL resolution:
#   --ingress-url option → FINGERPRINT_INGRESS_URL env → built-in default
zig build clients:browser

# Browser SDK TS tests (requires dist/ built above)
npm test --prefix src/clients/browser

# Docs snapshot (zig-out/docs/)
zig build docs

# Automation scripts
zig build scripts -- help
```

## Quick Start (Browser)

The SDK never computes a fingerprint — it collects signals, serializes a
versioned `SignalPackage`, and POSTs it to the ingress URL baked into the
bundle (`--ingress-url` at build time, or `FINGERPRINT_INGRESS_URL`):

```typescript
import { configure, collect } from '@akshay2642005/fingerprint-sdk';

configure({ ingressUrl: 'https://ingress.example.com/v1/fingerprints' });

const result = await collect();
console.log('package id:', result.packageId); // replay identity
console.log('signals:   ', result.signalCount);
console.log('sent:      ', result.sent);        // ingress accepted (HTTP 2xx)
console.log('reply:     ', result.reply);       // worker digest, when relayed
```

As fraud-platform middleware (the app remains the authority):

```typescript
import { onSessionBlocked, assertAllowed } from '@akshay2642005/fingerprint-sdk';

onSessionBlocked((decision) => {
  if (decision.reason) UI.notify(`Session blocked: ${decision.reason}`);
});

if (assertAllowed().blocked) {
  return; // do not proceed — last-known decision
}
```

## SDK Packages

| Package | Platform | Status |
| --------- | ---------- | -------- |
| [`@akshay2642005/fingerprint-sdk`](https://www.npmjs.com/package/@akshay2642005/fingerprint-sdk) | npm (browser, ESM) | ✅ Published (0.1.x WASM-era; 0.2.x signal-collection SDK) |

## Project Structure

```
.
├── build.zig                 # O(1) build system — every step declared up front
├── src/
│   ├── model/                # FeatureID (102), FeatureType, registry, fingerprint model — depends on nothing
│   ├── core/                 # Deterministic algorithms: hashing, normalization, validation, similarity, entropy, risk — depends on model
│   ├── serialization/        # Binary TLV + JSON codecs, codec interface, integrity — depends on model
│   ├── engine/               # Operation/Status/Request/Response/process — comptime dispatch, no io — depends on core+serialization
│   ├── io/                   # Async transport primitives (message, ring buffer, channel, completion, executor, frame, reader, writer, dispatcher) — depends on nothing
│   ├── adapter/              # Transport implementations: loopback, tcp, AMQP 0-9-1 — depends on io+stdx only
│   ├── worker/               # Deterministic worker executable — depends on engine+adapter
│   ├── stdx.zig              # Leaf utilities (copy helpers, bitsets, test PRNG)
│   ├── wasm.zig              # WebAssembly infra artifact (bench + wasmtime test containers only)
│   ├── clients/browser/      # hand-written TypeScript SDK: src/ + generated/ + dist/ (via `zig build clients:browser`)
│   ├── bench/                # Benchmark harness
│   ├── build/                # Build-time generators (browser package generator, dist surface guard)
│   ├── scripts.zig           # Automation dispatcher subcommands
│   └── docs_website/         # Nested Zig project — `zig build docs`
├── examples/
│   └── demo.html             # Dev-only browser demo (never shipped in the npm package)
├── tests/
│   ├── root.zig              # Self-verifying test registry (SNAP_UPDATE=1 regenerates)
│   ├── model/ core/ serialization/ engine/ io/ adapter/ worker/ build/ browser/
│   ├── clients/browser/      # TS SDK tests (node --test; golden parity, middleware, transport)
│   ├── fuzz/                 # Fuzz harnesses (decode, normalize, hashing)
│   ├── data/ fixtures/       # Test vectors, similarity suites, signal-package-v2 golden + manifest
│   └── utils/                # Test helpers
├── specs/                    # Planning docs (decisions, design, migration)
├── docs/                     # GitHub Pages site (index, api, architecture)
└── .github/workflows/        # ci.yml (test + wasm-build), release.yml (tags v*)
```

Dependencies flow inward: `model` → `core` / `serialization` → `engine`;
`io` → `adapter` → `worker`. Nothing depends outward; there are no circular
imports. Adapters depend on the engine's transport interface, never the
reverse.

## Architecture

The engine is layered so that every module depends inward and nothing depends
outward. The core contains only deterministic computation — no HTTP, no
queues, no databases, no business logic; adapters and the worker own every
transport concern.

```
Browser (TS SDK)
  │  collectors (102 signals)
  ▼
SignalPackage v2  ← validated, normalized, serialized in the browser
  │  POST (integrity header)
  ▼
Ingress (out of repo)
  │  FPKG request/response
  ▼
Worker (Docker)   ← engine.process(): validate → normalize → hash → entropy → risk
  │  reply frame
  ▼
Fraud platform (Go, out of repo)
  │  WebSocket push
  ▼
Browser SDK middleware (assertAllowed / onSessionBlocked)
```

The canonical fingerprint is computed only by the workers; the browser SDK
is a collection + packaging + middleware layer. Workers ship as Docker
containers — there is no native SDK and no C ABI.

## License

MIT
