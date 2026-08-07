# Rework Decisions — Fingerprint Engine

Status: Locked (2026-08-07)

Source: REWORK.md + review session. These decisions drive `ANALYSIS.md`,
`DESIGN.md`, and `MIGRATION.md`. If a decision changes, update this file first
and re-derive the downstream docs.

## D1 — Zig downgrade ordering

**Decision:** Downgrade Zig 0.16.0 → 0.14.1 **first**, as its own story, before
any restructuring.

**Why:** "Each commit must compile and pass tests" is only satisfiable on a
stable toolchain. Downgrading last produces two overlapping giant diffs and
breaks bisectability.

**Scope of the downgrade story:**
- `build.zig` — 0.16 module API → 0.14 API (`b.addModule`, `addExecutable` with
  `root_source_file`/`target`/`optimize`, `addStaticLibrary`, entry-point
  handling for WASM).
- `std.Io.*` (0.16-only) → `std.io.*` (0.14) in `serialization/binary.zig` and
  `serialization/json.zig`.
- `build.zig.zon` — `minimum_zig_version` 0.14.1.
- `.github/workflows/ci.yml` — `ZIG_VERSION: 0.14.1`.
- Note: `std.ArrayList` usage is already 0.14-style (`.empty` +
  allocator-passing); no change needed there.

## D2 — Repository layout

**Decision:** Full reorganization into layered `src/` tree. Not additive.

**Target tree (final):**

```
src/
├── model/          # pure data: FeatureID, FeatureValue, Feature, metadata, registry (zero deps)
├── core/           # algorithms: hashing, entropy, similarity, risk, normalization, validation (deps: model)
├── serialization/  # codec interface + binary + json (deps: model, io)
├── engine/         # Operation, Request, Response, process(), per-op handlers (deps: core, serialization)
├── io/             # Message, RingBuffer, Channel, Completion, Executor, Frame, Reader, Writer, Dispatcher (zero deps)
├── adapter/        # transport interface + loopback; amqp/ (deps: io, engine)
├── worker/         # worker main.zig (deps: engine, adapter)
├── browser/        # wasm exports (deps: engine), bindings/, collectors/
├── clients/browser # npm browser package (self-contained SDK; moved from sdk/browser/)
├── bench/          # benchmarks (moved from tools/bench/)
├── build/          # build-time helper programs (browser_package.zig)
├── scripts.zig     # single automation dispatcher binary; subcommands in scripts/
├── scripts/        # automation subcommands (added with the first real script)
└── docs_website/   # nested Zig project producing docs (zig build docs)
```

**No `src/native/`.** See D10. Layout revised per D13.

## D3 — Engine API shape

**Decision:** Single entry point, easy to change:

```
Engine.process(request: *const Request, response: *Response, arena: Allocator) !void
```

- `Request = { operation: Operation, payload: []const u8 }` — payload is
  **serialized bytes** in and out. Transport-free and replayable.
- `Operation` is a versioned `enum(u8)`: validate, normalize, serialize,
  deserialize, hash, entropy, similarity, risk, package.
- `similarity` carries **two** payloads (`a`, `b`); encoded as one payload via
  the codec so `Request` stays uniform.
- **Easy to change:** each operation is an independent public handler function
  (`ops/validate.zig`, `ops/risk.zig`, ...). `process()` is a comptime dispatch
  table over `Operation`. Adding per-op convenience functions later is a
  one-line wrapper per op; adding a new op is a new file + one table row. No
  runtime registration, no vtable.

## D4 — Message envelope

**Decision:** Extend, don't replace. Keep the feature TLV as the signal package
body; add a proper framed envelope ("FPKG") with version, message type, codec,
payload length, and integrity digest.

- Fixes today's lossy round-trip: `encode` drops `sdk_version` and
  `collected_at`; `decode` rebuilds empty metadata. The v2 body carries full
  metadata including a new `package_id`.
- `schema_version` bumps 1 → 2. Existing binary fixtures become compatibility
  goldens; v1 body decode kept for compat tests.

## D5 — Integrity semantics

**Decision:** Integrity = **SHA-256 digest of the canonical serialized payload**,
stored in the frame header. Tamper-evidence, corruption detection, dedupe.

**Not** HMAC/signing — the engine must never know keys, auth, or users
(REWORK.md absolute rules). Authenticity is the ingress/adapter's
responsibility.

## D6 — Determinism & replay

**Decision:** The engine never reads the clock and never uses randomness.
`collected_at` and `package_id` arrive **inside** the signal package as input
data. Same input bytes → same output bytes, enforced by:
- golden-fixture replay tests (process-level),
- worker end-to-end replay tests (loopback transport),
- version-compatibility tests (unknown envelope version → explicit error).

## D7 — IO abstraction

**Decision:** **Async-first** from day one. The `io/` layer ships:
Message, RingBuffer, Channel (SPSC), Completion, Executor (event loop),
Frame, Reader, Writer, Dispatcher.

- Completion-based async with explicit message ownership, **not
  copied**: minimal surface, no io_uring dependency, portable.
- The **engine stays synchronous and deterministic**; async lives at the
  transport boundary (adapter/worker).
- Deferred: `Pipeline`, `Command` (add only when a consumer needs them).

## D8 — AMQP adapter depth

**Decision:** Staged, per recommendation.

- **v1:** comptime transport interface + in-memory loopback transport + full
  message codec. Adapter and worker fully testable without a broker.
- **v2:** real RabbitMQ 0-9-1 client (connection, channels, exchange/queue
  declare, publisher confirms, consumer, reconnect, DLQ, backoff, heartbeat)
  as a separate module, after v1 is green.

## D9 — Worker shape

**Decision:** Tiny `worker/main.zig`. Transport injected at comptime:

- `--transport=loopback` — framed messages over stdin/stdout (repl-style;
  enables e2e tests via pipes). v1.
- `--transport=amqp` — v2.
- Worker logic: receive frame → deserialize → `engine.process()` →
  serialize → publish. No business logic.

## D10 — Browser WASM and native SDK

**Decision (revised 2026-08-07 by D14):**

1. **No WASM in the shipped browser SDK.** The browser SDK is hand-written
   TypeScript (D14): it collects signals, serializes a `SignalPackage`, and
   POSTs it to the ingress endpoint. Validation, normalization, and all
   computation happen **server-side in the workers**. The browser never
   generates the canonical fingerprint (`fingerprint_compute` dies), and
   the base64-wasm-inlined UMD template approach (D13-era) is deprecated.
2. **WASM remains in-repo as an infra artifact only** — benchmark harness
   and test containers (e.g., wasmtime) that emulate browser signal
   collection deterministically in CI. It is **not shipped** in the npm
   package.
3. **No native SDK.** `src/server/` is removed (native root, C header,
   empty rust dir). No static library, no C ABI. Workers are shipped as
   **Docker containers** running the worker executable.

## D11 — (folded into D10)

Native C ABI is dropped; no separate decision.

## D12 — Planning artifact location

**Decision:** Phase 1–3 artifacts live in `specs/rework/`:
`DECISIONS.md`, `ANALYSIS.md`, `DESIGN.md`, `MIGRATION.md`.
Final user-facing docs (`Architecture.md`, `Engine.md`, `IO.md`, `Worker.md`,
`AMQP.md`, `Serialization.md`, `Migration.md`, `Design.md`) are produced as
`docs/` files when implementation lands (REWORK.md deliverables).

## D13 — Build & layout convention

**Decision:** Adopt a unified build-system and repository conventions:

1. **O(1) `build.zig`** — top-level steps declared upfront as a tuple
   (`test`, `wasm`, `bench`, `clients:browser`, `docs`, `scripts`,
   `scripts:build`); helper functions per concern
   (`build_test`, `build_wasm`, `build_bench`, `build_browser_client`,
   `build_scripts`, `build_docs`); `pub fn build(b: *std.Build) !void`;
   `b.reference_trace = 10`; preferred optimize mode ReleaseSafe.
2. **Everything builds via Zig** — docs, packages, and the browser SDK
   `dist/` are produced by `zig build` only. The Node.js package build
   (`build.mjs`) is deleted. The browser SDK is **hand-written TypeScript**
   (D14); `zig build clients:browser` compiles/assembles it and injects the
   `FeatureID`/`FeatureType` tables derived from `src/model/feature.zig`
   (single source of truth — kills the duplicated hardcoded tables). The
   legacy base64-wasm-inlined generator (`src/build/browser_package.zig`)
   is superseded by the D14 SDK. Node remains only for `npm publish` and
   the documented TS compile step.
3. **Layout** — `sdk/browser/` → `src/clients/browser/` (self-contained npm
   package at `src/clients/browser/`; fixes the `../../..` ROOT depth
   bug in `build.mjs`/`package.json` which only resolves at 3-deep);
   `tools/bench/` → `src/bench/`; new `src/scripts.zig` dispatcher
   (subcommands in `src/scripts/`); new `src/build/` for build-time helper
   programs; new `src/docs_website/` nested Zig project wired from root via
   `zig build docs`.
4. **Steps** — `zig build clients:browser` (TS SDK → `dist/`),
   `zig build docs` (nested build), `zig build scripts -- <subcommand>`
   (free-form automation).

## D14 — Browser SDK shape

**Decision (2026-08-07 review):** The browser SDK is **hand-written,
human-readable TypeScript** — the published artifact is real source code,
not a generated template blob. It:

- **collects** the 102 signals (TS collectors),
- **serializes** them into the `SignalPackage` v2 body via a hand-written TS
  serializer (`package.ts`) mirroring `src/serialization/binary.zig`,
- **POSTs** the bytes to a configurable **ingress endpoint** (the SDK never
  talks to RabbitMQ directly; the ingress service owns the queue — browser
  → ingress → RabbitMQ, per REWORK.md).

Validation, normalization, hashing, risk, and similarity are **not** in the
browser — they run server-side in the workers. The browser's only output is
a versioned, integrity-carrying `SignalPackage`.

**Parity guarantee:** the TS serializer is tested against the same golden
fixtures as the Zig codec (cross-language golden vectors), so the two
implementations cannot drift.

## D15 — Fraud platform boundary (cross-repo)

**Decision (2026-08-07 review):** The **fraud platform is a separate
repository** (Go) — out of scope for this repo. This repo ends at the
engine's published events.

- The engine (workers) publishes typed events to the queue:
  `FingerprintComputed`, `RiskResult`, `SimilarityResult`,
  `ValidationResult`, `Diagnostics` (contracts in DESIGN §5.3).
- The Go platform consumes those events and owns everything downstream:
  **Postgres rule-based fraud detection**, the **admin workspace**, and
  **AI-agent tooling**. The Zig engine never imports databases, auth,
  users, organizations, policies, or business logic (REWORK.md absolute
  rules).
- This repo defines the **event contracts** (schema-versioned messages);
  the Go repo implements consumption.

## Environment constraints (recorded, not decisions)

- Sandbox terminal is broken (`libasound.so.2`) — validation and git must run
  on the user's machine until fixed.
- `bigpowers` skills are not installed; specs-first + TDD + green gates are
  followed in spirit.
- A local reference checkout of a hand-rolled systems codebase (has `src/`,
  `src/clients/`, `src/docs_website/`, `src/scripts.zig`, `src/build/`),
  excluded via `.git/info/exclude`; IO/build design is derived from the
  local source.
