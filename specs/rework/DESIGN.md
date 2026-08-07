# Phase 2 — Design (Fingerprint Engine Rework)

Status: Draft for approval (2026-08-07)
Decisions source: `specs/rework/DECISIONS.md` (D1–D15).

## 1. Design goals

1. **Deterministic computation engine**, not a service. No transport, no
   networking, no queues, no auth inside the engine (REWORK absolute rules).
2. **Browser never generates the canonical fingerprint.** Browser produces a
   versioned `SignalPackage`; workers canonicalize.
3. **Everything depends inward** — adapters → engine → core → model; io is
   foundation.
4. **Async-first IO** at the transport boundary, minimal,
   portable, deterministic core.
5. **Stateless, replayable, versioned messages** with integrity.
6. **Zig 0.14.1** baseline from day one; every commit compiles and passes tests.
7. **Browser SDK is hand-written, human-readable TypeScript** (D14); the
   only client-side computation is signal collection and `SignalPackage`
   serialization — validation and all computation live in the workers.

Non-goals for v1: real RabbitMQ client (v2; outbound-only publisher, D16/D20),
multi-threaded executor, Pipeline/Command abstractions,
protobuf/flatbuffers/capnproto codecs (interface ready, codecs later).

## 2. Layering

```
┌─────────────────────────────────────────────────────────────┐
│  worker/   adapter/   browser/   sdk/   tools/              │  consumers
├─────────────────────────────────────────────────────────────┤
│                       engine/                               │  orchestration
├─────────────────────────────────────────────────────────────┤
│  core/  (algorithms)        serialization/  (codecs)        │  computation
├─────────────────────────────────────────────────────────────┤
│                     model/  (pure data)                     │  data
├─────────────────────────────────────────────────────────────┤
│                     io/  (async primitives)                 │  foundation
└─────────────────────────────────────────────────────────────┘
```

Dependency rule: a layer may import itself and everything below it. `model/`
and `io/` depend on nothing (only std). `engine/` depends on `core/`,
`serialization/`, `model/`. `adapter/` depends on `io/` + `engine/`.
`worker/` depends on `engine/` + `adapter/`. `browser/` (wasm) depends on
`engine/`. No circular imports; enforced by review + `zig build` module graph.

## 3. Module tree (final)

```
src/
├── model/
│   ├── feature.zig        FeatureID, FeatureType, FeatureCategory,
│   │                      FeatureFlags, FeatureDefinition     (from features/model.zig)
│   ├── definitions.zig    compile-time definition table       (from features/definitions.zig)
│   ├── registry.zig       compile-time O(1) lookup             (from features/registry.zig)
│   ├── value.zig          FeatureValue tagged union            (from fingerprint/value.zig)
│   ├── feature.zig        Feature { id, value }                (from fingerprint/feature.zig)
│   ├── metadata.zig       FingerprintMetadata                  (from fingerprint/metadata.zig)
│   ├── fingerprint.zig    Fingerprint                          (from fingerprint/fingerprint.zig)
│   └── root.zig
├── core/
│   ├── hashing/           hasher, feature, fingerprint         (moved)
│   ├── entropy/           entropy                              (moved)
│   ├── similarity/        feature, fingerprint                 (moved)
│   ├── risk/              risk                                 (moved)
│   ├── normalization/     types, bounds, normalize             (moved)
│   ├── validation/        required                             (moved)
│   └── root.zig
├── serialization/
│   ├── codec.zig          comptime Codec interface (encode/decode)
│   ├── binary.zig         SignalPackage v2 TLV body            (rewritten)
│   ├── json.zig           JSON body                            (rewritten)
│   └── root.zig
├── engine/
│   ├── operation.zig      Operation enum(u8)
│   ├── request.zig        Request
│   ├── response.zig       Response, Status
│   ├── engine.zig         process() + comptime dispatch table
│   ├── ops/               validate.zig normalize.zig serialize.zig deserialize.zig
│   │                      hash.zig entropy.zig similarity.zig risk.zig package.zig
│   └── root.zig
├── io/
│   ├── message.zig        Message (arena-backed, ownership)
│   ├── ring_buffer.zig    fixed-capacity SPSC ring
│   ├── channel.zig        typed SPSC channel
│   ├── completion.zig     Completion { ctx, callback }
│   ├── executor.zig       async event loop (submit/tick/run)
│   ├── frame.zig          FPKG envelope encode/decode
│   ├── reader.zig         fixed-buffer Reader (version-proof, no std.io dep)
│   ├── writer.zig         fixed-buffer Writer (same)
│   ├── dispatcher.zig     comptime op → handler routing
│   └── root.zig
├── adapter/
│   ├── transport.zig      comptime Transport interface contract
│   ├── loopback.zig       in-memory transport (+ stdin/stdout framing)
│   ├── tcp.zig            FPKG-framed request/response server (ingress→worker, D16)
│   ├── amqp/
│   │   ├── codec.zig      AMQP 0-9-1 frame encode/decode (v1, D20)
│   │   └── root.zig       v2: outbound publisher (connection/channel/DLQ/confirms)
│   └── root.zig
├── worker/
│   └── main.zig           tiny executable, comptime transport injection
├── browser/
│   └── wasm/root.zig      stateless exports — infra only (bench harness +
│                          wasmtime test containers); NOT shipped in the
│                          npm SDK (D14)
├── clients/browser/       npm package — hand-written TypeScript SDK (D14)
│   ├── src/               index.ts (public API), collectors/ (signal
│   │                      gatherers), package.ts (SignalPackage v2
│   │                      serializer — mirrors serialization/binary.zig),
│   │                      transport.ts (POST to ingress + WS to platform),
│   │                      middleware.ts (assertAllowed/onSessionBlocked, D17)
│   ├── index.d.ts         hand-written declarations
│   ├── demo/
│   └── dist/              generated by `zig build clients:browser`
├── tools/
│   ├── bench/             benchmark harness (moved from benchmark/)
│   └── scripts/           (moved from scripts/)
└── (no src root.zig — layered modules only)

deploy/
└── Dockerfile.worker      multi-stage: zig build worker → static binary
```

## 4. Engine API

### 4.1 Request / Response / Operation

```zig
pub const Operation = enum(u8) {
    validate = 1,      // validation + normalization passes → warnings
    normalize = 2,     // canonical normalization → normalized package
    serialize = 3,     // model → bytes (codec from request)
    deserialize = 4,   // bytes → model
    hash = 5,          // canonical digest (workers only; not exported to wasm)
    entropy = 6,       // entropy score
    similarity = 7,    // two packages (a, b) → score
    risk = 8,          // risk assessment
    package = 9,       // validate + normalize + serialize + integrity (browser's call)
};

pub const Request = struct {
    operation: Operation,
    codec: CodecID,          // binary = 1, json = 2 (default binary)
    payload: []const u8,     // borrowed input; similarity → dual-encoded payload
};

pub const Status = enum(u8) {
    ok = 0,
    invalid_request = 1,     // malformed operation/codec
    invalid_payload = 2,     // decode failure
    unsupported_version = 3, // envelope version mismatch
    invalid_input = 4,       // validation/normalization failed hard
    buffer_overflow = 5,
    out_of_memory = 6,
    internal_error = 7,
};

pub const Response = struct {
    operation: Operation,
    status: Status,
    payload: []u8,           // written into caller buffer; caller owns
    payload_len: usize,
};

pub fn process(req: *const Request, res: *Response, scratch: Allocator) !void;
```

- `process()` dispatches through a **comptime table** (`Dispatcher`): one row
  per `Operation` → handler fn. Adding an op = new `ops/*.zig` file + table
  row. Per-op public wrappers (`engine.validate(req,res,arena)`, ...) are
  one-liners around `process()` — the API surface can grow without rework
  (D3).
- **Determinism:** no clock, no RNG, no globals. `collected_at` and
  `package_id` are input data inside the payload.
- **Similarity pair:** payload = codec-encoded `{a, b}` container; `ops/
  similarity.zig` decodes both and calls `core.similarity.fingerprintScore`.
- Memory: input borrowed; output written to a caller-provided buffer (resize
  via `payload_len`); intermediate allocations come from `scratch` (arena).

### 4.2 Per-op behavior

| Op | Input | Output |
|----|-------|--------|
| validate | SignalPackage | ValidationResult (missing required, type, bounds warnings; ok flag) |
| normalize | SignalPackage | NormalizationResult (warnings + canonical feature set) |
| serialize | SignalPackage | bytes in requested codec |
| deserialize | bytes | SignalPackage |
| hash | SignalPackage (canonicalized) | FingerprintResult (digest, schema, feature count) |
| entropy | SignalPackage | entropy score (f64) |
| similarity | dual payload (a, b) | SimilarityResult (score, compared count) |
| risk | SignalPackage | RiskResult (score, label, flags) |
| package | raw collected features | SignalPackage envelope (validate→normalize→serialize→integrity) |

## 5. Message envelope ("FPKG")

Fixed little-endian frame header, versioned, integrity-protected:

```
FrameHeader (48 bytes):
  magic:        [4]u8  = "FPKG"
  version:      u16    = 1
  message_type: u8     (MessageType enum)
  codec:        u8     (1 = binary, 2 = json)
  payload_len:  u32
  reserved:     u32    = 0
  integrity:    [32]u8 = SHA-256(payload)
```

MessageType (u8): `signal_package = 1, validation_result = 2,
normalization_result = 3, fingerprint_result = 4, risk_result = 5,
similarity_result = 6, diagnostics = 7, fingerprint_computed = 8`.

Envelope versioning: unknown `version` → `unsupported_version` at the engine
boundary (worker rejects, adapter routes to DLQ in v2). Integrity: recomputed
on ingest; mismatch → `invalid_payload`; the adapter treats it as a
poison-message signal.

### 5.1 SignalPackage body v2 (codec = binary)

Fixes F4 (lossy round-trip) and adds replay identity:

```
SignalPackage body (little-endian):
  schema_version:  u16 = 2
  sdk_version_len: u16
  sdk_version:     [len]u8
  collected_at:    i64          (client-provided input data — engine never clocks)
  package_id:      [16]u8       (client-generated UUID bytes — correlation)
  feature_count:   u16
  features:        TLV ×N       (FeatureID u16 | type u8 | len u32 | payload — unchanged)
```

v1 decode (schema_version = 1, no sdk/collected_at/package_id) kept as a
compatibility path in `serialization/binary.zig` and covered by golden
fixtures. Other result messages use compact fixed layouts:
FingerprintResult = `{ digest: [32]u8, schema: u16, feature_count: u16 }`,
RiskResult = `{ score: f64, flags_len: u8, flags: u8× }`, etc.

### 5.2 Codec interface

```zig
// serialization/codec.zig — comptime interface, no vtables (convention: no
// dynamic dispatch).
pub const Codec = struct {
    id: CodecID,
    encode: fn (writer: anytype, value: anytype) anyerror!void,
    decode: fn (reader: anytype, allocator: Allocator, value: anytype) anyerror!void,
};
```

`binary` and `json` implement it; protobuf/flatbuffers/capnproto are future
implementations selected by `codec` in the envelope. Serialization operates on
`anytype` writers/readers, so it works with `io.Writer`/`io.Reader`, test
buffers, or adapters — and is insulated from std.io API churn across Zig
versions.

### 5.3 Cross-repo contract — fraud platform (D15)

The engine's published events are the **contract boundary** with the fraud
platform (a separate Go repository). Workers publish:

| Event | Payload |
|-------|---------|
| `FingerprintComputed` | digest, schema, feature_count, package_id, integrity |
| `RiskResult` | score, label, flags, package_id |
| `SimilarityResult` | score, compared count, package_ids |
| `ValidationResult` | warnings, ok flag, package_id |
| `Diagnostics` | engine version, op timing, non-canonical client signals |

The Go platform consumes these events and owns **Postgres rule-based fraud
detection**, the **admin workspace**, and **AI-agent tooling**. The Zig
engine never imports databases, auth, users, organizations, policies, or
business logic (REWORK.md absolute rules). This repo defines the contracts;
the Go repo implements consumption.

The cross-repo surface (D17) is **events + a decision API + a block
channel** — the events above (async), plus:

- **Sync decision API** (Go): `GET /v1/risk/session/:id` →
  `allow | deny | challenge`, cached; the app gates sensitive actions.
- **WebSocket block push** (Go → browser SDK): `session.blocked` events in
  real time; the SDK acts as middleware (`assertAllowed`/`onSessionBlocked`)
  while the app enforces server-side.

## 6. IO abstraction (async-first, minimal)

All primitives are sync-determined and portable; async is used by transports
and the worker loop. Engine itself remains synchronous.

| Type | Responsibility |
|------|----------------|
| `io.Message` | Arena-backed byte buffer with explicit ownership transfer. Caller gets a `Message`, writes payload, transfers it (channel/transport). `MessagePool` recycles arenas (arena-pool pattern, simplified). |
| `io.RingBuffer` | Fixed-capacity SPSC ring buffer over `[]u8` or `*Message` slots. |
| `io.Channel` | Typed SPSC channel over a `RingBuffer`: `send(T)`, `recv()`; blocking and completion-based variants. |
| `io.Completion` | `{ context: ?*anyopaque, callback: *const fn (*Completion) void }` — embedded in consumer structs, zero allocation (completion pattern). |
| `io.Executor` | Event loop: `submit(*Completion)`, `tick()`, `run(timeout)`. v1 single-threaded; queue drained deterministically for tests. Multi-threaded executor is a later, opt-in addition. |
| `io.Frame` | Encode/decode the FPKG FrameHeader over any Reader/Writer (used by loopback, worker pipes, and the future AMQP client). |
| `io.Reader` / `io.Writer` | Fixed-buffer readers/writers (own implementation — no std.io dependency, version-proof). |
| `io.Dispatcher` | Comptime op → handler table; used by `engine.process()` and the worker's message routing. |

Deferred (per D7): `Pipeline`, `Command`.

## 7. Adapter layer

### 7.1 Transport interface (comptime)

```zig
// adapter/transport.zig
// A Transport implements: init/deinit, readFrame, writeFrame, publish, ack/nack.
// The worker is generic over T: Transport — swapping loopback → tcp → amqp is
// a CLI flag / comptime switch, zero worker logic changes (D16):
//   loopback  (v1) stdin/stdout framing — e2e tests via pipes
//   tcp       (v1) FPKG-framed request/response server — ingress→worker path
//   amqp      (v2) outbound event publisher only — worker→Go events
```

### 7.2 Loopback transport (v1)

In-memory queues + stdin/stdout framing mode (`--transport=loopback`):
reads FPKG frames from stdin, writes FPKG frames to stdout. Enables e2e tests
via pipes and deterministic replay testing without a broker.

### 7.3 TCP transport (v1, D16)

`adapter/tcp.zig` — FPKG-framed request/response server for the
ingress→worker path: `accept → readFrame → process → writeFrame`.
Connection pool on the ingress side; any worker answers any request
(stateless engine). Inbound is at-most-once; clients retry idempotently.

### 7.4 AMQP (staged, outbound-only — D16/D20)

- **v1 — codec only:** `adapter/amqp/codec.zig` implements AMQP 0-9-1 frame
  framing (method/header/body frames, type/class decoding), generated from
  the official AMQP 0-9-1 spec XML (D20 — reference: TigerBeetle
  `src/cdc/amqp/spec_parser.py`). Tested against captured byte fixtures —
  no broker required.
- **v2 — outbound publisher:** connection, channels, exchange/queue
  declare, basic.publish with publisher confirms, heartbeats, reconnect
  with backoff, dead-letter queue handling. **Publish-only** — the worker
  never consumes inbound requests over AMQP (D16). All RabbitMQ knowledge
  stays here — never in `engine/`.

Adapter flow (v2, for reference):

```
Worker loop (inbound request, tcp/loopback)
  → readFrame (FPKG envelope)
  → deserialize → Request (operation from message_type)
  → engine.process()
  → writeFrame (Response)                  // sync reply to ingress
  → publish AMQP events                    // FingerprintComputed, RiskResult, ...
  → publisher confirm / ack                // poison → DLQ after retries
```

## 8. Worker

```zig
// src/worker/main.zig — ~80 lines. No business logic.
// CLI: --transport=loopback|tcp, --publish=amqp|none (D16)
loop:
  request_frame = transport.readFrame()       // FPKG envelope (inbound)
  message = deserialize(request_frame)
  request = mapMessageToRequest(message)
  engine.process(request, response, arena)
  transport.writeFrame(serialize(response))   // sync reply to ingress
  publish(serialize(result_events))           // AMQP → fraud platform
  transport.ack(request_frame)
```

The worker's canonical path for a `SignalPackage`:

```
SignalPackage → validate → normalize → hash → entropy → risk →
FingerprintComputed { result, package_id, integrity } → publish
```

### 8.1 Worker CLI (TigerBeetle-style)

Thin arg parser modeled on TigerBeetle's `src/tigerbeetle/cli.zig`
(`Command = union(enum)` + typed, validated args; `main.zig` dispatches).
No business logic — the CLI parses args, constructs the transport + engine,
and runs the loop:

```
fingerprint-worker start --transport=tcp|loopback --listen=<addr>
                         --publish=amqp|none --config=<path>
fingerprint-worker version
fingerprint-worker help
```

- `start` — the loop above. `--transport` selects the inbound transport
  (comptime, D16); `--publish` selects the outbound event sink
  (v2: amqp).
- `version` / `help` — static output; no engine code.
- `Command` fields are validated and desugared (e.g. sizes → counts)
  before dispatch, TigerBeetle-style.

## 9. Browser SDK / WASM

### 9.1 Flow (D14 — hand-written TS, no wasm shipped)

```
Browser
  → TS collectors (canvas, webgl, audio, fonts, ...)
  → package.ts: serialize SignalPackage v2 (mirrors the Zig binary codec)
  → transport.ts: POST to ingress endpoint (request/response — no queue on
    this path, D16)
  → ingress → worker (FPKG-framed request/response)
  → worker → Go platform via AMQP events (durable outbound fan-out)
  → Go → browser SDK via WebSocket (session.blocked push, D17)
```

The browser **never generates the canonical fingerprint** — it cannot: the
`hash` op is not exported anywhere client-side, and the SDK contains no
WASM. Validation and normalization happen **server-side** in the worker's
canonical path (validate → normalize → hash → entropy → risk). The
browser's only output is a versioned `SignalPackage` with integrity.

### 9.2 SDK layout (`src/clients/browser/`)

```
src/
  index.ts          public API: collect(), FeatureID, FeatureType, types
  collectors/       signal gatherers (navigator, canvas, webgl, audio, ...)
  package.ts        SignalPackage v2 serializer (FPKG body, see §5.1)
  transport.ts      POST SignalPackage bytes to ingress + WS to platform (D17)
  middleware.ts     assertAllowed(action), onSessionBlocked(cb) — enforces the
                    last-known decision client-side; app enforces server-side
index.d.ts          hand-written declarations
demo/               demo page: collect → show package_id → send

  dist/             generated by `zig build clients:browser`
```

- Everything in `src/` is hand-written, human-readable TypeScript.
- `zig build clients:browser` compiles the TS, injects the
  `FeatureID`/`FeatureType` tables derived from `model` (single source of
  truth), injects the package version, and assembles `dist/`.
- **Parity:** `package.ts` is cross-tested against the Zig codec with the
  same golden fixtures, so the TS and Zig serializers cannot drift.
- Optional lightweight risk may be computed client-side for UX, explicitly
  labeled non-canonical.

### 9.3 WASM (infra-only artifact)

The WASM module (`src/browser/wasm/root.zig`) keeps the stateless exports
`fp_version` / `fp_process` / `fp_alloc` / `fp_free`, but it is **not
shipped in the npm package**. It serves two infra purposes:

- **benchmark harness** for the engine,
- **test containers** (wasmtime) that emulate browser signal collection
  deterministically in CI.

No global feature buffer, no init/reset/scratch: input is allocated via
`fp_alloc`, processed via `fp_process`, output read from the result region.

## 10. Docker

`deploy/Dockerfile.worker` — multi-stage:

1. Build stage: `zig build worker --release=safe` (0.14.1 registers
   `--release`/`-Drelease` when a preferred mode is set; `-Doptimize` is not
   accepted).
2. Runtime stage: copy the static `worker` binary; `ENTRYPOINT ["/worker",
   "--transport=amqp"]` (v2) or loopback for dev.

Static Zig binary → distroless/scratch runtime. CI adds a worker-build +
`docker build` job. No native library, no C ABI, no header.

## 11. Event flows

### 11.1 End-to-end (canonical)

```mermaid
flowchart TD
    B[Browser SDK] --> C[TS Collectors]
    C --> P[package.ts serialize SignalPackage + package_id]
    P --> I[Ingress Service]
    I -->|FPKG framed request| WK[Workers validate normalize hash entropy risk]
    WK -->|FPKG response| I
    WK -->|AMQP events| FP[Fraud Platform Go - separate repo]
    FP --> PG[(Postgres rule-based fraud detection)]
    FP --> WS[Admin workspace + AI agents]
    FP -->|WebSocket session.blocked| B
    APP[App backend] -->|sync decision API| FP
```

### 11.2 Worker internals

```mermaid
flowchart LR
    R[readFrame request] --> D[deserialize]
    D --> PR[Engine.process]
    PR --> S[serialize response]
    S --> RESP[writeFrame response]
    RESP --> PUB[publish AMQP events]
    PUB --> ACK[ack]
```

### 11.3 Dependency graph

```mermaid
flowchart TD
    MODEL[model - zero deps] --> CORE[core algorithms]
    IO[io - zero deps] --> SER[serialization]
    MODEL --> SER
    CORE --> ENG[engine]
    SER --> ENG
    IO --> ENG
    ENG --> AD[adapter]
    IO --> AD
    ENG --> BRO[browser wasm - infra only, bench/test containers]
    ENG --> WK[worker]
    AD --> WK
```

### 11.4 Blocking flow (D17)

```mermaid
sequenceDiagram
    participant B as Browser SDK (middleware)
    participant APP as App backend
    participant G as Fraud platform (Go)
    participant W as Worker (Zig)

    W->>G: AMQP events (FingerprintComputed, RiskResult, SimilarityResult)
    G->>G: rules evaluate (versioned, dry-run→promote) → session blocked
    G-->>B: WebSocket session.blocked (reason, expiry)
    B-->>B: SDK blocks UI flow / raises onSessionBlocked
    G-->>APP: decision API denies (cached, TTL)
    APP-->>B: sensitive action rejected (server-enforced)
```

## 12. Testing strategy

| Suite | Covers |
|-------|--------|
| `tests/model/` | feature definitions, registry, values, metadata (moved) |
| `tests/core/` | hashing, entropy, similarity, risk, normalization, validation (moved) |
| `tests/serialization/` | binary v1 compat, binary v2 round-trip, JSON, codec interface |
| `tests/engine/` | request/response, per-op behavior, dispatch table, determinism, replay goldens, unknown-version rejection |
| `tests/io/` | message ownership, ring buffer, channel, completion, executor drain, frame encode/decode |
| `tests/adapter/` | transport contract, loopback e2e, tcp framing e2e (ingress→worker), AMQP codec vs byte fixtures |
| `tests/worker/` | pipe e2e: frames in → FingerprintComputed out; tcp request/response e2e; replay determinism |
| `tests/browser/` | wasm export surface (stateless; infra artifact only) |
| `tests/clients/browser/` (TS) | package.ts serializer golden vectors vs Zig fixtures; middleware/WS contract against a mock decision server; SDK type-check |
| `tests/fuzz/` | decode, hashing, normalize (kept) |

All existing tests are preserved (relocated) except `tests/server/*`, which die
with the native SDK (D10).

## 13. Documentation deliverables

Final `docs/` files (land with implementation): `Architecture.md`, `Engine.md`,
`IO.md`, `Worker.md`, `AMQP.md`, `Serialization.md`, `Migration.md`,
`Design.md`. `docs/api.md` and `docs/architecture.md` are rewritten to drop the
deprecated browser-canonical and native-SDK content.
