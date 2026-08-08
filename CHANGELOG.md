# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `zig build scripts -- amqp get [--address=host:port] [--count=N]
  [--timeout-ms=N]` — live broker inspector: binds a throwaway queue to all
  nine result routing keys (comptime loop over `io.frame.MessageType`),
  polls `basic.get`, decodes each FPKG frame (message type, integrity
  verdict, status, digest, features, schema), and nacks after reading.
  Verified end-to-end against RabbitMQ 4.3.4 (publisher confirms `basic_ack`
  delivery tags observed).
- Specs populated for the current status and backlog: index (`specs/README.md`),
  ADRs (`specs/decisions/` ADR-001…010), product vision/glossary/snapshot,
  architecture plans, verification checklists, epic archive, refreshed
  `plan.md` and status files. See `specs/README.md`.

## [0.2.2] - 2026-08-08

### Added

- Worker image published to GitHub Container Registry from the release
  pipeline — `ghcr.io/akshay2642005/fingerprint-engine/fingerprint-worker`
  with `:latest` and version tags.

### Fixed

- Release pipeline: GHCR image tags are now lowercased (Docker requires
  lowercase repository names, but `github.repository` preserves case),
  fixing the v0.2.1 image-push failure.
- npm publish is idempotent — it skips when the exact version is already on
  the registry, so re-running a tag after a failed job never redeploys npm.

### Changed

- Version bumped to 0.2.2 across `build.zig`/`build.zig.zon`, the browser SDK
  `package.json`, and the worker container tag (`fingerprint-worker:0.2.2`).
- Specs status files refreshed for v0.2.2 (`release-plan.yaml`,
  `planning-status.yaml`, `state.yaml`, `SCOPE_LATEST`, `DESIGN.md`).

## [0.2.1] - 2026-08-08

### Added

- `examples/demo.html` rewired to the hand-written browser SDK — the dev-only
  example now imports the shipped `dist/index.js` (no WASM, no in-browser
  fingerprint), lets you set the ingress and decision WebSocket URLs at runtime,
  and shows the SignalPackage metadata, worker reply, and session decision gate.
- `src/clients/browser/README.md` — npm package readme covering install, quick
  start, collect options, integrity headers, and the session decision gate.

- AMQP 0-9-1 adapter in `src/adapter/amqp/` — a synchronous client (`client.zig`) over a generated-style protocol layer (`spec.zig`/`protocol.zig`/`types.zig`) with publisher confirms on connect, `queue_declare`/`queue_bind` for consumers, and `get_message`/`get_message_body`/`nack` polling; plus a result publisher (`publisher.zig`) that converts each worker reply frame into one published message — routing key `result.<message-type>` (kebab-case), headers `fpkg-message-type`/`fpkg-envelope-version`, persistent delivery, timestamps, on the durable `fingerprint` direct exchange. Wired to the worker CLI as `--amqp-address`/`--amqp-user`/`--amqp-password`/`--amqp-vhost` (defaults `127.0.0.1:5672`, `guest`/`guest`, `/`). Broker topology and connection concerns live entirely behind the adapter; the engine and worker stay transport-free (D16).
- `zig build scripts -- amqp` — live broker smoke test: connects, declares the `fingerprint` exchange, binds a throwaway queue to `result.fingerprint-result`, publishes a frame, and verifies the round trip.
- `compose.yml` — local dev RabbitMQ 4 (management UI on 15672) for adapter and smoke-test work.
- AMQP adapter unit tests in `tests/adapter/amqp_test.zig` and worker-level publisher coverage in `tests/worker/worker_test.zig`.
- Deterministic worker executable in `src/worker/` — CLI (`start --transport=loopback|tcp [--listen=host:port] [--publish=none|amqp]`, `version`, `help`) with comptime transport injection: loopback moves FPKG frames over stdin/stdout pipes, tcp serves one request/response client at a time. Inbound message types map to specific engine operations (`signal_package` → `hash` is the canonical path); replies are FPKG frames whose payload is `u8 status | engine result`; poison frames are dropped and acked (D9, D16). The message type set gains `entropy_result` so the entropy operation has a distinct result frame. `--publish=amqp` routes reply frames to the broker through the AMQP adapter; publish failures are logged and the frame dropped, protocol violations are fatal.
- `deploy/Dockerfile.worker` — thin `alpine` runtime with `tini` as PID 1; the worker binary is built on the host by the zig build system (`zig build worker --release=safe`), nothing compiles inside the image. Exposed on 8080. Plus a CI `worker-build` job that builds the executable and uploads it as an artifact.
- `zig build docker:worker` — builds the worker container image from the prebuilt binary (tag `fingerprint-worker:0.2.1`, tracked to `build.zig.zon`), with `zig build scripts -- docker build-worker|run` helpers. CI gains a `docker-worker` job that builds the image and smoke-tests the entrypoint.
- `zig build scripts -- worker request [--listen=host:port]` — FPKG round-trip against a running worker (default `127.0.0.1:8080`, e.g. the container's published port): sends the canonical signal package fixture and prints the reply, cross-checking the digest against an in-process engine call.
- `zig build scripts -- generate fixture signal-package-v2` — writes the canonical v2 signal package fixture under `tests/fixtures/` and prints its engine hash. Worker e2e tests spawn the worker as a subprocess and speak the wire protocol directly (loopback pipe and tcp request/response), pinning that digest as a compile-time constant.
- Transport contract and adapter implementations in `src/adapter/` — comptime `transport.check` plus shared FPKG framing helpers (`buildFrame`/`decodeFrame`/`readFrameFrom` with a 16 MiB payload cap, integrity validated at the boundary), a `Loopback` transport (in-memory queues for tests, stdin/stdout pipes for processes), and a `Tcp` request/response server for the ingress → worker inbound path (D16). Adapters depend on `io` only; the engine and serialization stay transport-free.
- SignalPackage body v2 in `src/serialization/` — replay identity (`package_id` [16]u8), `sdk_version` and `collected_at` preserved on the wire (fixes the lossy v1 round-trip), version-field-driven encode/decode with v1 kept as a compatibility path, and a comptime `CodecID`/`Codec` interface (`codec.zig`) that the engine aliases as its single source of truth. Unknown body schema versions now map to `unsupported_version` at the engine boundary. SHA-256 payload integrity helpers (`integrity.zig`) keep serialization transport-free.
- Async IO primitives in `src/io/` — arena-backed `Message`/`MessagePool`, `RingBuffer`, typed `Channel`, embedded `Completion`, deterministic single-threaded `Executor`, FPKG `Frame` envelope, fixed-buffer `Reader`/`Writer`, and a comptime `Dispatcher` (zero dependencies, D7).
- Deterministic computation engine in `src/engine/` — versioned `Operation`/`Status`/`CodecID`, immutable `Request`, caller-owned `Response`, and `process()` with a comptime dispatch table plus per-op handlers (`validate`, `normalize`, `serialize`, `deserialize`, `hash`, `entropy`, `similarity`, `risk`, `package`) over the existing core algorithms (D3). The engine imports no io/transport code.

### Changed

- Docs site (`docs/`) rewritten for the distributed architecture — browser
  quick start moved to the TypeScript SDK (`configure`/`collect`), API page
  documents the engine/io/adapter/worker layers and the v2 wire format, and
  the architecture page reflects the real event flow and test counts. Mermaid
  diagrams (system flow, dependency graph, engine/worker sequence) added to
  the README and the docs site.
- Specs status files refreshed for v0.2.0/v0.2.1 (`release-plan.yaml`,
  `execution-status.yaml`, `planning-status.yaml`, `state.yaml`, `SCOPE_LATEST`).
- `CONVENTIONS.md` rewritten as a full style guide — the essence of style,
  safety (limits, assertions, determinism, memory), performance, and developer
  experience rules (naming, cache invalidation, off-by-one, tooling), with the
  project's operational conventions (commits, git, always-green, specs, tests)
  preserved.
- npm publishing is automated through the OIDC trusted publisher
  (`release.yml` `publish-npm` job) — v0.2.1 published straight from CI.
- Browser npm package is now strictly the runtime SDK — `dist/` ships only the UMD/ESM bundles and type declarations, no demo page. The browser demo moved to `examples/demo.html` at the repo root (dev-only, never published).
- Browser SDK rewritten as a hand-written TypeScript package (`src/clients/browser/src/`): `collect()` gathers plain `Signal[]`, `package.ts` serializes a versioned SignalPackage v2 body (mirroring `serialization/binary.zig` byte-for-byte, cross-checked by a golden parity test), and `transport.ts` POSTs it to the ingress URL (`--ingress-url` build option → `FINGERPRINT_INGRESS_URL` env → built-in default) with `x-fpkg-*` headers plus a SHA-256 integrity header. The browser never computes the canonical fingerprint. The base64-wasm-inlined UMD template and the wasm bindings are deleted; wasm stays in-repo for bench/test containers only. The package is ESM-only (`exports` map with `types`/`default` conditions, NodeNext module resolution so every import carries a `.js` extension).
- SDK middleware surface for the fraud platform (D17): `configure({ wsUrl })` opens the decision WebSocket, `assertAllowed()` returns the last-known decision, `onSessionBlocked(cb)` registers `session.blocked` callbacks — a client-side UX gate only; the app enforces.

### Added

- `zig build scripts -- generate fixture signal-package-v2` now also writes `signal-package-v2.signals.json` — the exact signals + metadata behind the `.bin` golden, feeding the TS parity test.
- TS SDK test suite (`tests/clients/browser/`, `node --test`, documented Node exception): golden parity (TS serializer vs Zig fixture bytes), wire-layout checks, middleware/transport unit tests with a mocked `fetch`.
- `src/build/dist_surface.zig` — dist surface guard run by `zig build clients:browser` after tsc: rejects `.wasm` files, wasm-instantiation markers (base64 blobs, `WebAssembly`, old engine exports) in any JS file, and `hash`/`compute` identifiers in the public `.d.ts` surface; unit-tested in `tests/build/dist_surface_test.zig`. The `dist/` tree is wiped before tsc so stale artifacts can never leak.
- Browser package TS tests are wired as `npm test --prefix src/clients/browser` (`node --test tests/clients/browser/`).

## [0.2.0] - 2026-08-07

### Added

- `zig build scripts` — single automation dispatcher binary with subcommands in `src/scripts/`.
- `zig build docs` — nested Zig project that snapshots `docs/` into `zig-out/docs/`.
- Self-verifying test registry at `tests/root.zig` — auto-discovers test files under `tests/`, fails with a "needs updating" message when the import list is stale (`SNAP_UPDATE=1` regenerates it), and supports `zig build test -- <filter>`.
- Integration and end-to-end smoke tests via `zig build test-integration` — the test binary contains no engine code and drives the pre-built `fingerprint-bench` and `scripts` executables as subprocesses (`src/integration_tests.zig`, `src/testing/shell.zig`).

### Changed

- Worker CLI diagnostics no longer pollute test output — `parse()` is pure (errors are returned, never printed) and `main()` owns stderr, printing the message plus usage exactly once per failed invocation.
- Toolchain downgraded from Zig 0.16.0 to **0.14.1** (`minimum_zig_version = "0.14.1"`); CI pinned to match.
- Build system unified into a single O(1) `build.zig` — tests, WASM, benchmarks, the browser npm package, docs, and automation scripts all build through `zig build`.
- Browser SDK `dist/` is now generated by Zig (`zig build clients:browser`) — the UMD/ESM bundles and `.d.ts` derive `FeatureID`/`FeatureType` from the Zig model (`src/model/feature.zig`), replacing the duplicated hand-maintained JS tables.
- Repository reorganized into layered modules (`src/{core,model,serialization,browser,clients,bench,build,scripts,docs_website}`) with dependencies flowing inward.
- Browser SDK relocated to `src/clients/browser/` and benchmarks to `src/bench/`.
- CI pipeline scoped to test + WASM build; the native library build job was removed.

### Removed

- Native server SDK and C ABI (`zig build native`, `src/server/`, `fingerprint.h`) — fingerprint workers ship as containers instead (decision D10).
- Node.js package build step (`build.mjs`) and the TypeScript dev dependency — the browser package builds with Zig only.
