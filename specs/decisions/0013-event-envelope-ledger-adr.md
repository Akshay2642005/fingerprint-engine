<!-- // story: m6-event-envelope -->

# ADR-013 — Per-collection event envelope + platform ledger contract

- **Status:** Proposed (Week-1 D4 field list + types chosen; full design
  detail + grill in Week 5 before M7 persistence depends on it)
- **Source:** `src/io/frame.zig`, `src/serialization/json.zig`,
  `src/engine/ops/risk.zig`, `src/engine/status.zig`, `src/adapter/amqp/publisher.zig`,
  `src/cmd/ingress/http.zig`
- **Extends:** ADR-004 (FPKG envelope + SignalPackage v2 + integrity),
  ADR-012 (versioning + compatibility contract), D-v1-4 / D-v1-5 / D-v1-6
  (ROADMAP-v1.0.0.md). Does not supersede any of them.

## Context

M7 needs one self-contained, durable record per collection that the platform
can persist and query without re-joining the live `result.*` fanout frames
(ordering drift, partial arrivals). Today the worker publishes every reply frame
as an AMQP message; that live fanout stays unchanged. What is missing is a
single per-collection document carrying the canonicalized signals, both
digests, and the evaluation outputs.

D-v1-4 removed the Zig store: the durable ledger is platform-side (Postgres
JSONB default / MongoDB), fed by the engine's existing AMQP publisher. This ADR
defines, at the wire/contract level, the **event envelope** (`collection_event`)
and the **ledger contract**. Deep implementation detail (exact worker wiring,
routing keys, DLQ topology) is out of scope and is specified internally; this
ADR fixes field names, types, and semantics so both sides of the contract can
be built independently.

## Decision

### 1. A new outbound message type per collection

Add `collection_event = 10` to `MessageType` in `src/io/frame.zig` — the
first appended value (10+, per ADR-012 §2 the enum is append-only). Rules:

- **Outbound only.** The engine emits it; no peer sends it. `operationFor`
  returns `null` for it (no engine op runs against it and it carries no status
  byte — it is not a reply to a request).
- **`codec = json`.** Its payload is the JSON envelope (§2); the deterministic
  `jsonEncode` already in `serialization/json.zig` writes it. No new JSON
  machinery.
- **One per collected `signal_package`**, in addition to the unchanged in-band
  reply frame, when the worker publisher is enabled. It is computed from the
  already-received, already-processed package — the same core ops run on the
  same user data, never cross-user state.

### 2. Envelope schema (JSON, fixed key order)

Keys are emitted byte-for-byte deterministically, in the fixed order below
(comptime keyed, mirroring `jsonEncode`'s stability). Digests are lower-hex.

| Key | Type | Semantics |
|-----|------|-----------|
| `schema_version` | int | = 2 (SignalPackage schema this collection used, ADR-012) |
| `package_id` | string (32 hex) | 128-bit SDK-minted id, one per collection; **ledger idempotency key** |
| `session_id` | string | browser/idp session for continuity queries; echoed from the `x-fpkg-session-id` header (§4) |
| `fingerprint_id` | string (64 hex) | full SHA-256 `fingerprint_digest` (v2 result) |
| `core_digest` | string (64 hex) | stable-core SHA-256 digest (D-v1-5; gate, not verdict) |
| `core_version` | int | increments when the stable-core subset definition changes (D-v1-7) |
| `feature_count` | int | number of features collected (SignalPackage `feature_count`) |
| `core_feature_count` | int | number of features in the stable core subset |
| `status` | int | `Status.code()` (engine/status.zig, `ok = 0 …`) — folded op outcome, engine never throws |
| `entropy` | float | per-collection entropy estimate |
| `risk` | object | `{ "score": float, "label": string, "flags": [string] }` — shape of `core.risk.computeRisk` |
| `collected_at` | int | unix seconds, collection time (SignalPackage `collected_at`) |
| `ingress_received_at` | int | unix seconds, ingress receipt time |
| `sdk_version` | string | SDK semantic version that minted the collection |
| `signals` | object | canonicalized feature values, keys = registry names (stable; name reuse is a breaking change) |

All digests and JSON serialization are deterministic: same input, same bytes,
any platform (project convention).

### 3. `fingerprint_result` carries two digests (D-v1-5)

The reply to the browser/server gains the stable-core digest — but only as an
**append-extend** of the existing v1 result layout so the first 36 bytes stay
parseable by legacy readers (the additive stable-prefix case ADR-012 §3
describes):

```
[32] fingerprint_digest | u16 feature_count | u16 schema_version   ← v1, unchanged
[32] core_digest       | u16 core_feature_count | u16 core_version ← appended
```

This is a result-format change, versioned via the existing schema-version
field per ADR-012 §3 (breaking → dual-decode). The full digest stays
byte-identical for existing consumers.

### 4. New `x-fpkg-session-id` request header

Add `x-fpkg-session-id` to the ingress-allow-listed headers (`ParsedHead` in
`src/cmd/ingress/http.zig`), echoed into the frame/package metadata and the
envelope. Today the correlation surface is only `package_id`; the envelope
needs `session_id` for continuity/investigation queries.

### 5. Ledger contract (platform side)

- Consumer binds the collection-event topic; on consume: parse envelope →
  idempotency check on **`package_id`** → insert → ack; parse failure → DLQ.
- Postgres shape (JSONB default):

```
collection_events(
  package_id          uuid PRIMARY KEY,
  session_id          text,
  fingerprint_id      bytea,
  core_digest         bytea,
  core_version        int,
  signals             jsonb,   -- canonicalized values (§2)
  risk                jsonb,   -- {score, label, flags}
  entropy             float8,
  sdk_version         text,
  collected_at        timestamptz,
  ingress_received_at timestamptz
)
```

- Indexes: btree on `fingerprint_id` / `session_id` / timestamp (continuity
  + investigation); GIN over `signals` for agent/workspace queries.
- Optional AES-GCM at rest for stored signal JSON; reads through an
  authenticated API, never raw keys.
- Exactly-once is guaranteed by engine exactly-once publishing of `package_id`
  (envelope is deterministic per collection) plus a platform-side uniqueness
  check; the ledger's unique index is `package_id`.

## Consequences

- The platform persists one document per collection with zero join work; the
  live fanout, replies, and engine ops are unchanged.
- The engine stays stateless and browser-facing contract-identical; the new
  message type is additive (ADR-012's append-only rule).
- Deterministic JSON keeps ledger bytes reproducible across platforms and
  comparable for debugging.
- The stable-core subset is not yet defined (that is D-v1-7: registry `core`
  metadata + `core_version`, calibrated against the M6 golden matrix). Until
  then `core_digest`/`core_feature_count`/`core_version` are emitted from the
  agreed selection rule; the ADR does not bake the subset itself.

## Open items (Week 5)

- Full envelope ↔ `fingerprint_result` two-digest wiring + version bump.
- `stable-core` subset definition and `core_version` policy (D-v1-7).
- Ledger access API + workspace query surface (works with `01`-style
  investigation needs but is platform-owned).

## Out of scope

AMQP routing key contract, DLQ topology, worker publish policy details,
platform identity-resolution logic (M7.1), and the ledger access API. These
are internal or platform-side and are specified elsewhere.