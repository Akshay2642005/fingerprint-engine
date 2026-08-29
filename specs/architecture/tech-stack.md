# Tech Stack — Fingerprint Engine (current, v0.4.1)

Refreshed 2026-08-08. Supersedes the pre-rework inventory (Zig 0.16.0, 37
features, empty tests) — see `specs/decisions/rework/ANALYSIS.md` F8.

## Language & Toolchain

- **Language:** Zig 0.14.1 (downgraded from 0.16.0, decision D1 / ADR-001)
- **Dependencies:** none — Zig standard library only, zero third-party
  packages (`build.zig.zon` has no dependencies)
- **Build system:** `zig build` — single O(1) `build.zig`; every artifact
  (tests, wasm, bench, browser package, docs, docker, scripts) is a declared
  step
- **Browser SDK:** hand-written TypeScript (compiled with `tsc` — the only
  documented Node exception), tests with `node --test`
- **CI:** GitHub Actions (ci.yml: test, wasm-build, worker-build, docker-worker;
  release.yml: GitHub Release + GHCR + idempotent npm via OIDC)
- **Containers:** Docker, multi-stage `deploy/Dockerfile.worker` (alpine, tini,
  non-root); compose for local RabbitMQ 4

## Source inventory (`src/`)

| Module | Contents | Depends on |
|--------|----------|-----------|
| `model/` | FeatureID ×102, FeatureType, FeatureValue, Feature, Fingerprint, metadata, comptime registry | nothing |
| `core/` | hashing, normalization, validation, similarity, entropy, risk | model |
| `serialization/` | CodecID/Codec interface, binary TLV (v2 + v1 compat), json, integrity | model |
| `engine/` | Operation/Status/CodecID, Request/Response, process() comptime dispatch, ops/* | core, serialization |
| `io/` | Message/MessagePool, RingBuffer, Channel, Completion, Executor, FPKG Frame, Reader, Writer, Dispatcher | nothing |
| `adapter/` | comptime transport contract, loopback, tcp, amqp (client, protocol, types, publisher) | io, stdx |
| `worker/` | `main.zig` — start/version/help CLI | engine, adapter |
| `clients/browser/` | npm package `@akshay2642005/fingerprint-sdk` — hand-written TS src/, generated/ tables, dist/ | (tsc) |
| `wasm.zig` | infra-only WebAssembly artifact (bench + wasmtime test containers) | engine |
| `bench/` | benchmark harness (12 benchmarks) | model/core |
| `build/` | build-time generators (browser package generator, dist surface guard) | model |
| `scripts.zig` | automation dispatcher (worker request, amqp, generate fixture, docker, ...) | adapter, engine |
| `testing/` | e2e harness helpers (`shell.zig`) | — |
| `integration_tests.zig` | e2e tests (drive pre-built executables as subprocesses) | — |
| `docs_website/` | nested Zig project producing `zig build docs` | — |

## Architecture

```
Browser SDK (TS)                Ingress (planned, M5)             Fraud platform (Go, other repo)
     │  POST SignalPackage            │  FPKG frames                    │
     ▼                                ▼                                │
  ingress ──► worker pool ──► engine.process() ──► AMQP events ────────┤
                     (Docker containers)                                ▼
                                                              Postgres rules / workspace / AI
```

Layered dependency rule: everything depends inward. `model` → `core` /
`serialization` → `engine`; `io` → `adapter` → `worker`. The engine imports no
io/transport code; adapters never import the engine.

## Wire & data formats

- **FPKG envelope** (`src/io/frame.zig`): `"FPKG"` magic, 48-byte header,
  envelope version 1, 9 message types, codec id, payload length, SHA-256
  integrity. Payload cap 16 MiB at the adapter boundary.
- **SignalPackage v2 body** (`src/serialization/binary.zig`): feature TLVs +
  metadata (package_id, sdk_version, collected_at); v1 kept as a compat path.
- **AMQP 0-9-1** (outbound only): durable `fingerprint` direct exchange,
  routing keys `result.<message-type>` (kebab-case), persistent delivery,
  publisher confirms.

## Testing

- 385 tests (378 unit + 7 integration/e2e); 3 fuzz targets; 12 benchmarks.
- Golden fixture `signal-package-v2.bin` (digest `db29fc13…e6c75`, features=3,
  schema=2) pins the canonical digest across Zig/worker/TS parity tests.
- TS parity test cross-checks the SDK serializer against the Zig codec.

## Build targets

| Command | Output |
|---------|--------|
| `zig build test` / `zig build test-integration` | test suites (unit + integration) |
| `zig build wasm` | `zig-out/bin/fingerprint.wasm` (infra) |
| `zig build worker --release=safe` | `zig-out/bin/worker` |
| `zig build bench` | benchmark binary |
| `zig build clients:browser` | npm `dist/` (ESM + types) |
| `zig build docs` | docs snapshot in `zig-out/docs/` |
| `zig build scripts -- <sub>` | automation (worker request, amqp, generate fixture, docker) |
| `zig build docker:worker` | `fingerprint-worker:<version>` image |

## Active considerations (from the 2026-08-08 audit)

- BUG-001: SDK `parseWorkerReply` swaps schema/feature-count (S1).
- H-1: worker tcp transport lacks socket idle timeouts (S1).
- F-1: HTTP ingress is the next milestone (S4, `specs/architecture/ingress.md`).
- F-2: application logging (S3, `specs/architecture/logging.md`).
