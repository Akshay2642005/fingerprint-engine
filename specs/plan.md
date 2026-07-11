# Fingerprint Engine — Integration & Quality Plan

## M1 — Fill the Gaps (Immediate)

### 1.1 TypeScript/JS WASM bindings ✅

- [x] `src/browser/bindings/types.ts` — FeatureID, FeatureType, FeatureValue types
- [x] `src/browser/bindings/engine.ts` — FingerprintEngine class wrapping wasm exports
- [x] `src/browser/bindings/index.ts` — barrel export
- [x] `tests/browser/bindings_test.zig` — test that bindings compile/parse correctly

### 1.2 C header for native library ✅

- [x] `src/server/api/c/fingerprint.h` — public C API types and function declarations
- [x] `tests/server/cheader_test.zig` — validate C header matches zig exports via comptime checks

### 1.3 Test data & fixtures ✅

- [x] `tests/data/fingerprints/` — 5-10 canned fingerprints (JSON + binary) for regression
- [x] `tests/data/browser/` — realistic browser signal values
- [x] `tests/fixtures/datasets/` — multi-fingerprint datasets for similarity/entropy/risk testing

### 1.4 Test utilities ✅

- [x] `tests/utils/` — generators, mock fingerprint builders, assertion helpers
- [x] Coverage: reduce test boilerplate across all 11 phases

### 1.5 CI/CD pipeline

- [ ] `.github/workflows/ci.yml` — test on ubuntu/macos/windows, zig build test/wasm/native
- [ ] `.github/workflows/release.yml` — tag-based publish to npm/GitHub Releases
- [ ] Badges in README

### 1.6 Package metadata

- [ ] `build.zig.zon` — populate with version, description, dependencies, license

## M2 — Integration SDKs (Short-term)

### 2.1 npm package

- [ ] `packages/browser/` — publish WASM + TS bindings as `@fingerprint/sdk`
- [ ] Example: basic browser demo HTML page
- [ ] Example: Node.js fingerprint verification script

### 2.2 PyPI package ✅

- [x] `packages/server/python/` — Python bindings via ctypes/cffi to native lib
- [x] Example: Python server with fingerprint matching

### 2.3 Cargo crate ✅

- [x] `packages/server/rust/` — Rust `-sys` crate wrapping native lib
- [x] Example: Rust CLI tool

### 2.4 Usage examples

- [ ] `examples/browser-demo/` — vanilla HTML + WASM demo
- [ ] `examples/server-cli/` — CLI that reads fingerprints and computes digest/risk/similarity
- [ ] `examples/server-http/` — HTTP API server (Zig std.http or via binding)

## M3 — Production Readiness (Medium-term)

### 3.1 Benchmark harness

- [ ] `benchmark/` — zig bench targets for: hashing, serialization, normalization, similarity, entropy
- [ ] WASM size tracking
- [ ] Performance regression gate in CI

### 3.2 Fuzz testing

- [ ] Fuzz targets for: binary decode, JSON decode, normalize, deserialize
- [ ] OSS-Fuzz configuration

### 3.3 Documentation

- [ ] Full API docs (zig-created docgen or manual markdown)
- [ ] Migration guide (0.1.x → 0.2.x)
- [ ] Architecture overview updated

### 3.4 Cross-platform verification

- [ ] Test on macOS, Linux, Windows (CI covers this)
- [ ] Test WASM in Chrome, Firefox, Safari, Node.js
- [ ] Verify endianness invariance

### 3.5 Security

- [ ] `SECURITY.md` — fill with real policy
- [ ] Supply chain (lockfile, signed releases)
- [ ] Input validation audit (decode/deserialize paths)

## M4 — Signal Collection & Matching (Long-term)

### 4.1 Browser signal gatherers

- [ ] Canvas fingerprinting
- [ ] WebGL / WebGPU renderer
- [ ] AudioContext
- [ ] Installed fonts (CSS/Font API)
- [ ] Screen/display signals
- [ ] Navigator signals (already defined as feature IDs)

### 4.2 Server-side matching engine

- [ ] Fingerprint database (sqlite or in-memory)
- [ ] Lookup by digest + similarity fallback
- [ ] Risk-based scoring pipeline
- [ ] Anomaly detection over time (entropy drift)

### 4.3 Telemetry API

- [ ] Ingestion endpoint (HTTP/gRPC)
- [ ] Batch processing pipeline
- [ ] Dashboard/analytics

---

## Concrete Worktree Plan (Next ~10 branches)

| # | Branch | Epic | Est. Tests | Status |
| --- | -------- | ------ | ----------- | ------ |
| 1 | `m1-ts-bindings` | TS/JS WASM bindings | +4 | ✅ Merged |
| 2 | `m1-c-header` | C header + comptime validation | +4 | ✅ Merged |
| 3 | `m1-test-data` | Fixtures, datasets, test data | +5 | ✅ Merged |
| 4 | `m1-test-utils` | Test utility helpers | +14 | ✅ Merged |
| 5 | `m1-ci-cd` | GitHub Actions + badges | +0 (infra) | ✅ Merged |
| 6 | `m1-package-meta` | build.zig.zon + MIT license | +0 | ✅ Merged |
| 7 | `m2-npm-package` | npm + browser demo | +0 | ✅ Merged |
| 8 | `m2-server-packages` | Python SDK + Rust -sys crate | +0 | ✅ Merged |
| 9 | `m3-benchmarks` | Benchmark harness | +0 (bench) | 🏗️ Next |
| 10 | `m3-fuzz-docs-security` | Fuzz + docs + security audit | +20 | |
