# Roadmap — Fingerprint Engine v1.0.0

Status: **Draft** (planning)
Updated: 2026-08-30
Supersedes: nothing — extends `specs/planning/PLAN.md` (M1–M5 complete at v0.4.1)
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
| D-v1-3 | **Storage = our own TigerBeetle-inspired Zig store (Option B).** The vendored `tigerbeetle/` tree is *reference only* (excluded via `.git/info/exclude`, never committed). We do **not** depend on TigerBeetle-the-binary. | License hygiene (project is MIT; upstream TigerBeetle is BSL). Fits the minimal-deps / Zig / zero-alloc ethos. We only need an append-only, ordered, crash-safe log — ~5% of what TigerBeetle offers. |

## Definition of v1.0.0 (done criteria)

A **frozen public contract** + **durable event record** + **operational maturity**
+ **documented risk model**. Not "more features."

- [ ] Wire ABI (FPKG v2 / SignalPackage v2 / `CodecID`) frozen; versioning & compatibility ADR published.
- [ ] TS SDK public API frozen; SemVer + deprecation policy; `npm@1.0.0`.
- [ ] `FeatureID` registry (0–101) locked; capability negotiation supported (engine tolerates missing/extra signals).
- [ ] Cross-browser golden matrix green (Chromium / Firefox / WebKit) — digest byte-stability across a major version.
- [ ] Durable, ordered, tamper-evident event store in place (M7); exactly-once via `package_id`.
- [ ] Metrics + tracing + health/readiness; chaos test for an SLO.
- [ ] Risk / entropy / similarity model documented and calibrated.
- [ ] `zig build test` green; release pipeline (GHCR images + npm) one-command.

## Phases

| Phase | Theme | Scope | Status |
|-------|-------|-------|--------|
| M6 | API & determinism contract | Freeze wire + SDK; lock registry; cross-browser golden; event schema | Planned |
| M7 | Durable event ledger (TigerBeetle-inspired store) | Our own Zig append-only store adapter; exactly-once; audit/replay | Planned |
| M7.1 | Device ledger (optional, compute-only) | Append-only "seen this ID?" records; no matching in core | Planned (fast-follow) |
| M8 | Observability & ops | Prometheus metrics, `request_id` tracing, probes, chaos SLO | Planned |
| M9 | Signal breadth, quality & SDK ergonomics | Confidence/entropy, anti-tamper, new categories; SDK wrappers/script tag/consent | Planned |
| M10 | Platform integration | Platform owns auth/api_key/tenant; ledger feeds platform matching | Planned |

### M6 — API & determinism contract
- ADR: **versioning & compatibility policy** for FPKG / SignalPackage / `CodecID` (how a future v3 is introduced without breaking 1.0 consumers).
- Freeze TS SDK public API; publish SemVer + deprecation policy; cut `npm@1.0.0`.
- Lock `FeatureID` 0–101; `flags`/`weight` governance doc.
- **Capability negotiation**: SDK reports collected signal set; engine tolerates missing/extra (`definitions` lookup is tolerant).
- **Cross-browser golden matrix**: headless Chromium/Firefox/WebKit collect → encode → compare digest bytes against a pinned golden; CI gate.
- Define the **event record schema** (M7 consumer): `package_id, canonical_digest, status, similarity, risk, entropy, sdk_version, collected_at`.

### M7 — Durable event ledger (our own TigerBeetle-inspired store)
A `storage` adapter (depends inward; symmetric to the AMQP adapter). Core engine
unchanged. Inspired by `tigerbeetle/src/aof.zig`, `storage.zig`, `lsm/`, `io/`.

Design (minimal for 1.0):
- **Append-only segment files**; each entry checksummed (tamper-evident).
- `fsync` on write (crash-safe); **replay on startup** to rebuild in-memory index.
- Idempotency key = `package_id` → **exactly-once** (duplicate box ⇒ no duplicate record).
- Ingestion = a dedicated `stored` service **subscribing to AMQP** (existing S5 consumer + DLQ machinery); workers unchanged.
- Store read surface for 1.0 = **CLI** (`stored replay` / `stored lookup` / `stored status`).

Out of scope for M7: consensus, replication, LSM compaction, accounts/transfers.
Those are intentionally *not* copied from TigerBeetle.

### M7.1 — Device ledger (optional, compute-only)
Append-only records keyed by `canonical_digest` enabling "have we seen this
device before?" for self-hosters. **No similarity/matching logic in core** —
only a lookup + first-seen timestamp. Deferred from 1.0 to keep M7 tight.

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
- The M7 ledger feeds the platform's matching / identity-graph.
- Cross-language codecs behind `CodecID` (flatbuffers / cap'n proto) pair naturally with the fixed-size stored record.

## Open questions / defaults

- **M7 scope**: default = event/audit log only for 1.0; device ledger as M7.1. Override to fold into 1.0 if desired.
- **In-engine security for 1.0** (unanswered): default = keep HMAC integrity + replay-window (cheap, proves tamper/origin, no tenancy); full auth deferred to M10.
- **Cross-language codec**: planned for M10; could pull earlier if the store needs a stable on-disk format beyond the native Zig struct.

## Relationship to existing specs

- Extends `PLAN.md` (M1–M5 done). `PLAN.md` `next_phase` → this document.
- Consumes `VISION.yaml` long-term goals; respects `SCOPE.yaml` out-of-scope.
- Storage adapter follows `architecture/tech-stack.md` module-inventory + adapter contract (`adapters depend inward`).
- Security notes land in `security/SECURITY_PLAN.md` (refresh for HMAC/replay).
- New ADRs required: versioning/compatibility (M6), storage adapter (M7).

## Execution plan

The **complete day-by-day execution timeline** (16 weeks, one task per working
day, monthly releases v0.5.0 → v0.6.0 → v0.7.0 → v1.0.0) is a working/internal
plan kept **out of the repo** at `specs/internal/ROADMAP-v1.0.0-DAILY.md`
(excluded via `.git/info/exclude`, like `tigerbeetle/`). It is the operating
schedule for executing M6 (Month 1), M7 (Month 2), M8 (Month 3), and hardening +
release (Month 4). This file is the source of truth for *what* ships; the
internal file is the source of truth for *when/how day-to-day*.