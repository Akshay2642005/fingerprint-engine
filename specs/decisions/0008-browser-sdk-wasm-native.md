# ADR-008 — Hand-written TS SDK; WASM infra-only; no native SDK

- **Status:** Adopted (2026-08-07, revised by D14)
- **Rework decisions:** D10, D11, D14

## Context

The pre-rework browser package inlined a base64 WASM binary into a generated
UMD template and computed the canonical fingerprint in the browser — exactly
what the rework forbids. A native C ABI server library existed too.

## Decision

1. **The shipped browser SDK is hand-written, human-readable TypeScript**
   (`src/clients/browser/src/`) — the published artifact is real source code,
   not a generated template blob:
   - collects the 102 signals (TS collectors),
   - serializes them into a `SignalPackage` v2 body via `package.ts`
     (mirrors `serialization/binary.zig` byte-for-byte; golden parity test),
   - POSTs the bytes to a configurable **ingress endpoint**
     (`configure({ ingressUrl })`; build option `--ingress-url` →
     `FINGERPRINT_INGRESS_URL` env → built-in default) with `x-fpkg-*` headers
     + SHA-256 integrity header.
   - doubles as middleware for fraud-platform decisions:
     `assertAllowed()`, `onSessionBlocked()` (D17).
   - The browser **never** computes the canonical fingerprint.
2. **WASM remains in-repo as an infra-only artifact** (`src/wasm.zig`) — for
   the benchmark harness and wasmtime test containers that emulate browser
   signal collection deterministically in CI. **Not shipped** in the npm
   package; the dist surface guard (`src/build/dist_surface.zig`) rejects any
   `.wasm`/wasm-instantiation markers/compute identifiers in `dist/`.
3. **No native SDK.** `src/server/` (native root, C header, rust dir) removed.
   No static library, no C ABI (D11). Workers ship as Docker containers.

## Consequences

- npm package `@akshay2642005/fingerprint-sdk` is ESM-only with hand-written
  `.d.ts`, built by `zig build clients:browser` (generated FeatureID/FeatureType
  tables derived from `src/model/feature.zig` — single source of truth).
- The SDK's reply parsing must match the worker's wire layout exactly —
  currently violated by **BUG-001** (schema/count field swap in
  `parseWorkerReply`, self-consistent green test) — first fix in slice S1.
- Node is a documented exception (tsc compile step + TS test suite only).
