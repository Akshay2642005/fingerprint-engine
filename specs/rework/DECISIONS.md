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
├── sdk/            # npm browser package (moved from packages/)
└── tools/          # benchmark (moved from benchmark/), scripts (moved from scripts/)
```

**No `src/native/`.** See D10.

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

**Decision:**

1. **WASM stays for collection/packaging** (research: possible — see
   DESIGN.md §Browser). New stateless exports replace the stateful
   `init/add_*/compute` API. **Canonical fingerprint generation is removed
   from the browser** (`fingerprint_compute` dies). The WASM provides
   validation, normalization, serialization, integrity, packaging,
   diagnostics, collection helpers, optional lightweight risk.
2. **No native SDK.** `src/server/` is removed (native root, C header,
   empty rust dir). No static library, no C ABI. Workers are shipped as
   **Docker containers** running the worker executable.
3. The WASM artifact is additionally retained for **benchmarking and test
   containers** (e.g., wasmtime) that emulate browser signal collection
   deterministically.

## D11 — (folded into D10)

Native C ABI is dropped; no separate decision.

## D12 — Planning artifact location

**Decision:** Phase 1–3 artifacts live in `specs/rework/`:
`DECISIONS.md`, `ANALYSIS.md`, `DESIGN.md`, `MIGRATION.md`.
Final user-facing docs (`Architecture.md`, `Engine.md`, `IO.md`, `Worker.md`,
`AMQP.md`, `Serialization.md`, `Migration.md`, `Design.md`) are produced as
`docs/` files when implementation lands (REWORK.md deliverables).

## Environment constraints (recorded, not decisions)

- Sandbox terminal is broken (`libasound.so.2`) — validation and git must run
  on the user's machine until fixed.
- `bigpowers` skills are not installed; specs-first + TDD + green gates are
  followed in spirit.
- A local reference checkout of a hand-rolled systems codebase (excluded via
  `.git/info/exclude`); IO/build design is derived from the local source.
