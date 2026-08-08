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

**Decision:** Staged, per recommendation. AMQP is **outbound-only** — it
carries the worker → fraud-platform event stream and is never used for
inbound requests (D16).

- **v1:** comptime transport interface + in-memory loopback transport +
  FPKG-framed TCP transport + full message codec. Adapter and worker fully
  testable without a broker.
- **v2:** real RabbitMQ 0-9-1 **publisher** (connection, channels,
  exchange/queue declare, publisher confirms, reconnect, DLQ, backoff,
  heartbeat) as a separate module, after v1 is green. Implementation follows
  the TigerBeetle CDC module as reference (D20).

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
  talks to RabbitMQ directly). The ingress forwards the package to a worker
  as a framed request/response and relays the computed reply back (D16) —
  RabbitMQ is **not** on the inbound path; it carries only the worker →
  fraud-platform event stream.

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

## D16 — Transport split: inbound request/response, outbound AMQP events

**Decision (2026-08-07 review):** Remove RabbitMQ from the browser→worker
inbound path. Inbound is a **framed request/response** protocol; AMQP
carries **only** the outbound worker→Go event stream.

Modeled on TigerBeetle, verified in the local reference (`src/cdc/runner.zig`):
VSR (TigerBeetle's own protocol) serves every inbound client request; AMQP
appears only in CDC as an **outbound** event publisher to RabbitMQ. There is
no AMQP inbound anywhere. We take the shape, not the machinery — the engine
is stateless, so VSR's consensus/replication is not needed; only its
request/response contract is.

- Browser → ingress: HTTP POST of the `SignalPackage` (unchanged;
  `transport.ts`).
- Ingress → worker: FPKG-framed request over a worker connection pool
  (`io.Frame` + `io.Reader`/`io.Writer`); any worker answers any request
  (stateless engine — no ordering, no affinity).
- Worker → ingress: framed response (`FingerprintComputed` + base risk);
  the ingress relays it to the caller.
- Worker → Go: AMQP events (`FingerprintComputed`, `RiskResult`,
  `SimilarityResult`, `ValidationResult`, `Diagnostics`) — the durable,
  at-least-once path (publisher confirms, DLQ).

**Reliability split:** inbound is at-most-once with idempotent client
retries (a worker crash drops one request; the browser re-POSTs). Outbound
is at-least-once — fraud events must not be lost.

**Why:** "here are my signals, give me my identity/risk" is a synchronous
request/response; a queue adds latency, reordering, and a broker dependency
to the one path that benefits most from synchronous semantics. AMQP stays
where it earns its keep: durable fan-out of computed events to the platform.

## D17 — Decision & blocking surface (sync API + WebSocket push)

**Decision (2026-08-07 review):** Blocking is a three-lever surface owned
by Go and the application; the engine only computes. Go signals, the app
enforces, the SDK surfaces.

1. **Sync decision API** (Go): `GET /v1/risk/session/:id` →
   `allow | deny | challenge`. The app gates sensitive actions (login,
   checkout, withdrawal) on it. Decisions cached (Redis, TTL).
2. **WebSocket push** (Go → browser SDK): `WS /v1/ws?session_id=...`.
   When Go flips a session to blocked (rules, similarity, manual review),
   it pushes `session.blocked` (+ reason, expiry). The SDK raises an event;
   the app kills the session locally; the SDK blocks UI flows client-side.
3. **App enforcement** (unchanged responsibility): token revocation,
   denylist, device-level denial at session creation.

The browser SDK doubles as **middleware** (D14 stays): it collects signals
AND enforces the last-known decision for UX — `assertAllowed(action)`,
`onSessionBlocked(cb)` — while the app enforces authoritatively
server-side. WS is a best-effort fast path; the sync API is the authority.

## D18 — Similarity at scale (candidate selection)

**Decision (2026-08-07 review):** Go owns candidate selection; the engine
only scores pairs (`similarity(op)` takes `{a, b}` in the payload, D3).
Ordered strategy:

1. **Exact digest match** — indexed Postgres lookup. Always first; free.
2. **Coarse-bucket prefilter** — group stored digests by stable feature
   subsets (platform + UA family + screen class) to bound the candidate set.
3. **Engine pair scoring** — Go submits `{candidate, stored}` pairs; the
   worker scores and publishes `SimilarityResult`; thresholds are config.
4. **LSH / embedding clustering** — later optimization if volume demands;
   not v1.

The §5.3 contract gains a compare-request flow: Go asks for a similarity
evaluation (via the decision API or an AMQP request message); the worker
publishes `SimilarityResult` back.

## D19 — Rules-as-data (Go platform)

**Decision (2026-08-07 review, Go-repo contract guidance):** The Go rule
engine is **data, not code**:

- Rules are versioned rows: conditions over engine signals (risk score,
  flags, digest bucket, velocity, similarity) → action
  (`allow/block/challenge/review`) + priority + TTL.
- Every evaluation records the rule version + inputs for audit.
- Dry-run mode: rules evaluate but do not act until promoted.
- This repo only defines the signal schema the rules consume (D15); the
  engine never sees rules.

## D20 — AMQP implementation reference (TigerBeetle CDC)

**Decision (2026-08-07 review):** `adapter/amqp/` follows the TigerBeetle
CDC module (`src/cdc/amqp.zig` + `src/cdc/amqp/`) as the reference:

- **Wire protocol** (`protocol.zig`): frames `type(u8) | channel(u16) |
  size(u32) | payload | 0xCE`, big-endian; method/header/body/heartbeat
  frame types; single-frame bodies for v1.
- **Generated spec** (`spec_parser.py`): method/argument tables generated
  from the official AMQP 0-9-1 spec XML into `spec.zig` — no hand-written
  wire tables.
- **Client shape** (`amqp.zig`): single channel, fixed send/receive
  buffers, batched publish, publisher confirms (`confirm_select`), queue/
  exchange declare, get/nack, heartbeats, connect state machine (dial →
  handshake → auth → connection_open → channel_open → confirm_select).
  Reconnect/backoff/DLQ stay in the adapter (v2).
- **Substrate:** the `io/` layer (D7) is the client's engine;
  `stdx/ring_buffer.zig` is the reference for `io/ring_buffer.zig`
  (comptime-generic FIFO, array-or-slice backing).

## Environment constraints (recorded, not decisions)

- Sandbox terminal is broken (`libasound.so.2`) — validation and git must run
  on the user's machine until fixed.
- `bigpowers` skills are not installed; specs-first + TDD + green gates are
  followed in spirit.
- A local reference checkout of TigerBeetle (has `src/io/`, `src/vsr/`,
  `src/cdc/`, `src/stdx/`, `src/clients/`, `src/docs_website/`,
  `src/scripts.zig`, `src/build/`), excluded via `.git/info/exclude`;
  IO/build design and the AMQP adapter (D20) are derived from the local
  source. TigerBeetle uses VSR for inbound client requests; AMQP appears
  only in `src/cdc/` as an outbound event stream (D16).
