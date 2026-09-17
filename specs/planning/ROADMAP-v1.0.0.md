# Roadmap — Fingerprint Engine v1.0.0

Status: **Draft** (planning)
Updated: 2026-09-07
Supersedes: nothing — extends `specs/planning/PLAN.md` (M1–M5 complete at v0.4.1). Locked decision **D-v1-3 (own Zig store) superseded by D-v1-4 (2026-09-07)**; M7/M7.1 re-scoped accordingly.
Source of truth for decisions: `specs/decisions/` (ADRs) + `specs/decisions/rework/DECISIONS.md`

## Context

v0.4.1 ships the full distributed-engine roadmap (M1–M5): deterministic engine,
FPKG v2 / SignalPackage v2, async IO, HTTP ingress, Zig worker + Docker, AMQP
outbound, hand-written TS SDK, docs site, 457 tests. `PLAN.md` marks the next
milestone as *unplanned*. This document defines the path to a stable **1.0.0**.

`VISION.yaml` long-term goals this roadmap delivers: production-grade distributed
ingestion, a durable at-least-once event stream, cross-language serialization
parity behind `CodecID`, one-command release, and a stable public API.

## Locked decisions (from planning discussion)

| # | Decision | Rationale |
|---|----------|-----------|
| D-v1-1 | **Enterprise scope stays compute-only.** Matching, similarity candidate selection, and the identity graph remain in the Go fraud platform (separate repo). | `VISION` non-targets; keeps the engine a pure, testable function. |
| D-v1-2 | **Auth / api_key are platform-side**, added after platform integration (M10). The engine ingress for 1.0 trusts the network and optionally verifies HMAC integrity + a replay window; it does **not** own tenancy. | User direction; avoids building a gatekeeper into the compute layer. |
| D-v1-3 | **Storage = our own TigerBeetle-inspired Zig store (Option B).** *(Superseded 2026-09-07 → D-v1-4.)* The vendored `tigerbeetle/` tree is *reference only* (excluded via `.git/info/exclude`, never committed). We do **not** depend on TigerBeetle-the-binary. | License hygiene (project is MIT; upstream TigerBeetle is BSL). Fits the minimal-deps / Zig / zero-alloc ethos. We only need an append-only, ordered, crash-safe log — ~5% of what TigerBeetle offers. |
| D-v1-4 | **Storage is platform-side, not a Zig store.** The durable event ledger lives in Postgres (JSONB default) or MongoDB, owned by the platform's AMQP consumer. The engine publishes the event envelope on AMQP and never calls a database; there is no `stored` service and no AOF/segment store. | Re-scopes M7 (2026-09-07 design session); removes a full compute-side storage subsystem in favor of existing AMQP + S5 consumer/DLQ machinery + a general-purpose DB. |
| D-v1-5 | **Two-digest `fingerprint_result`.** The v1.0 wire carries both the full and the stable-core SHA-256 digests (append-extend of the v1 layout, per ADR-012's additive path), so the platform can answer "did the stable core change?" (drift) without replaying signals. A `core_version` distinguishes device drift from changes to the subset definition. | ADR-012 stable-prefix rule; keeps the full digest byte-identical for existing consumers. |
| D-v1-6 | **One event envelope per collection** (`collection_event`) on the existing outbound publisher: `package_id, session_id, fingerprint_id, core_digest, feature_count, core_feature_count, status, entropy, risk, sdk_version, canonicalized signals (JSON), schema_version`. Exactly-once via the SDK-minted `package_id`. | One self-contained ledger document; no platform-side join across the `result.*` fanout; worker replies to the browser stay unchanged. |
| D-v1-7 | **Stable-core subset = new registry `core` metadata**, not the existing `stable_required` validation flag. Uses a reserved `FeatureFlags` bit; locked with the registry in M6, calibrated against the cross-browser golden matrix. | The `stable` bit conflates validation with durability — battery/connection/window-size features are `stable` yet transient. |
| D-v1-8 | **Identity resolution is platform-side.** `fingerprint_id` stays a drifting descriptor; the platform resolves `identity_id` via stable-core digest equality with fallback to the existing core `similarity` score on drift — never raw full-digest blocking. | Preserves D-v1-1 (compute-only engine); renews D-v1-2 (no auth in engine). |

## Definition of v1.0.0 (done criteria)

A **frozen public contract** + **durable event record** + **operational maturity**
+ **documented risk model**. Not "more features."

- [ ] Wire ABI (FPKG v2 / SignalPackage v2 / `CodecID`) frozen; versioning & compatibility ADR published.
- [ ] TS SDK public API frozen; SemVer + deprecation policy; `npm@1.0.0`.
- [ ] `FeatureID` registry (0–101) locked; **stable-core subset locked (two-digest result, `core_version`) on the wire**; capability negotiation supported (engine tolerates missing/extra signals).
- [ ] Cross-browser golden matrix green (Chromium / Firefox / WebKit) — digest byte-stability across a major version.
- [ ] Durable, platform-side event ledger ingesting the per-collection `collection_event` envelope (Postgres JSONB default / MongoDB); exactly-once via `package_id`; optional AES-GCM at rest.
- [ ] Metrics + tracing + health/readiness; chaos test for an SLO.
- [ ] Risk / entropy / similarity model documented and calibrated.
- [ ] `zig build test` green; release pipeline (GHCR images + npm) one-command.

## Phases

| Phase | Theme | Scope | Status |
|-------|-------|-------|--------|
| M6 | API & determinism contract | Freeze wire + SDK; lock registry; cross-browser golden; event schema | Planned |
| M7 | Event envelope + platform ledger contract | Two-digest result + `collection_event` envelope on AMQP; platform Postgres/MongoDB ledger schema (JSONB, idempotent on `package_id`); no Zig store (D-v1-4) | Planned |
| M7.1 | Identity anchoring (platform, compute-only, optional) | Platform resolves `identity_id` from stable-core digest equality + core similarity; no matching in core | Planned (fast-follow) |
| M8 | Observability & ops | Prometheus metrics, `request_id` tracing, probes, chaos SLO | Planned |
| M9 | Signal breadth, quality & SDK ergonomics | Confidence/entropy, anti-tamper, new categories; SDK wrappers/script tag/consent | Planned |
| M10 | Platform integration | Platform owns auth/api_key/tenant; ledger feeds platform matching | Planned |

### M6 — API & determinism contract
- ADR: **versioning & compatibility policy** for FPKG / SignalPackage / `CodecID` (how a future v3 is introduced without breaking 1.0 consumers) — [ADR-012](decisions/0012-versioning-compatibility-adr.md).
- Freeze TS SDK public API; publish SemVer + deprecation policy; cut `npm@1.0.0`.
- Lock `FeatureID` 0–101; `flags`/`weight` governance doc.
- **Capability negotiation**: SDK reports collected signal set; engine tolerates missing/extra (`definitions` lookup is tolerant).
- **Cross-browser golden matrix**: headless Chromium/Firefox/WebKit collect → encode → compare digest bytes against a pinned golden; CI gate.
- Define the **event envelope schema** (`collection_event`, one per collection): `package_id, session_id, fingerprint_id, core_digest, feature_count, core_feature_count, status, entropy, risk, sdk_version, canonicalized signals (JSON), schema_version`. `fingerprint_result` carries **two digests** (full + stable-core) per ADR-012's additive append-extend path (D-v1-5/D-v1-6). Schema (field list + types) drafted in [ADR-013](decisions/0013-event-envelope-ledger-adr.md) (Week-1 D4), refined + grilled Week 5.
- Lock the **stable-core subset** as registry `core` metadata (a reserved `FeatureFlags` bit, D-v1-7): selection rule + `core_version`, calibrated against the cross-browser golden matrix.

### M7 — Event envelope + platform ledger contract

> **Superseded 2026-09-07 (D-v1-4).** The prior M7 — a dedicated Zig `stored`
> service with an append-only TigerBeetle-inspired store — is **replaced** by a
> platform-side ledger. The superseded text is retained below for history:
>
> ~~A `storage` adapter (depends inward; symmetric to the AMQP adapter). Core
> engine unchanged. Inspired by `tigerbeetle/src/aof.zig`, `storage.zig`,
> `lsm/`, `io/`. Design (minimal for 1.0): append-only segment files,
> checksummed entries, `fsync` on write, replay on startup, idempotency key =
> `package_id`, ingestion via a dedicated `stored` service, read surface =
> CLI.~~

**New scope** (engine side, D-v1-4/D-v1-5/D-v1-6): the engine's month-2 work is
the **two-digest `fingerprint_result`** and the outbound **`collection_event`
envelope** on the existing AMQP publisher. Compute stays untouched: workers
remain stateless and the browser-facing reply contract is unchanged. **No Zig
storage abstraction and no `stored` service.**

**Platform ledger contract** (Postgres JSONB default / MongoDB):
- Table `collection_events(package_id PK, session_id, fingerprint_id, core_digest,
  core_version, signals jsonb, risk jsonb, entropy, sdk_version, collected_at,
  ingress_received_at)`.
- Idempotency key = SDK-minted **`package_id`** → exactly-once; secondary
  indexes on `fingerprint_id` / `session_id` / timestamp (continuity +
  investigation); GIN for agent/workspace queries over `signals`.
- Optional **AES-GCM at rest** for stored signal JSON; workspace/agents read
  through an authenticated API (never raw keys).

Out of scope for M7: in-engine on-disk format, consensus, replication, LSM
compaction. Those are intentional from the previous plan and remain out.

### M7.1 — Identity anchoring (platform, compute-only, optional, fast-follow)

The platform maps `(fingerprint_id, session_id)` → `identity_id`: **stable-core
digest equality** first, falling back to the existing `core.similarity`
fingerprint score when the core mismatches (drift). `identity_id` is maintained
across drift; a first-seen/last-seen view serves self-hosters. **No
similarity/matching logic moves into engine core** (D-v1-1/D-v1-8); core only
exposes the digest + score it already computes. Deferred from 1.0 to keep M7
tight.

### M8 — Observability & ops
- Prometheus metrics on ingress + worker: latency, throughput, queue/ledger
  depth, DLQ rate, signal coverage, similarity distribution.
- `request_id` tracing correlated across ingress → worker → ledger event.
- Health/readiness probes, graceful drain, autoscale signals.
- Chaos test (worker death, ledger outage) asserting an SLO.

### M9 — Signal breadth, quality & SDK ergonomics
- Per-signal **confidence / entropy**; **anti-tamper** scores (easy-to-spoof signals weighted down).
- New categories: fonts/emoji, audio, battery, sensors, server-side TLS/JA3 hints, webview/mobile detection.
- SDK: React/Vue/Svelte wrappers, drop-in script tag, SSR safety, retry/backoff, offline queue, **consent gating** (carries retention metadata into the event record).

### M10 — Platform integration (auth/api_key arrive here)
- Platform owns auth/api_key/tenant; ingress trusts platform-issued tokens or sits behind the platform gateway (D-v1-2).
- The event stream + platform ledger feed the platform's matching / identity-graph (the ledger is already platform-owned per D-v1-4; M10 wires auth + tenant around it).
- Cross-language codecs behind `CodecID` (flatbuffers / cap'n proto) pair naturally with the platform ledger's JSON envelope.

## Open questions / defaults

- **M7 scope** *(superseded 2026-09-07 → D-v1-4)*: the prior default (event/audit log only, own store) is replaced by the **platform-side ledger contract** (Postgres JSONB / MongoDB); device ledger is now identity anchoring (M7.1).
- **In-engine security for 1.0** (unanswered): default = keep HMAC integrity + replay-window (cheap, proves tamper/origin, no tenancy); full auth deferred to M10.
- **Cross-language codec**: planned for M10; with no Zig on-disk format (D-v1-4) it now matters only if the platform ledger needs codec-parity beyond JSON.

## Relationship to existing specs

- Extends `PLAN.md` (M1–M5 done). `PLAN.md` `next_phase` → this document.
- Consumes `VISION.yaml` long-term goals; respects `SCOPE.yaml` out-of-scope.
- No Zig storage adapter exists (D-v1-4): the event ledger is platform-side; the AMQP outbound envelope follows `architecture/tech-stack.md` adapter contract (`adapters depend inward`).
- Security notes land in `security/SECURITY_PLAN.md` (refresh for HMAC/replay).
- New ADRs required: versioning/compatibility (M6) — [ADR-012](decisions/0012-versioning-compatibility-adr.md) drafted; two-digest result + event envelope + ledger contract — [ADR-013](decisions/0013-event-envelope-ledger-adr.md) (Week 5 full draft; Week-1 D4 skeleton drafted).

## Execution plan

The **complete day-by-day execution timeline** (16 weeks, one task per working
day, monthly releases v0.5.0 → v0.6.0 → v0.7.0 → v1.0.0) is a working/internal
plan kept **out of the repo** at `specs/internal/ROADMAP-v1.0.0-DAILY.md`
(excluded via `.git/info/exclude`, like `tigerbeetle/`). It is the operating
schedule for executing M6 (Month 1), M7 (Month 2), M8 (Month 3), and hardening +
release (Month 4). This file is the source of truth for *what* ships; the
internal file is the source of truth for *when/how day-to-day*.