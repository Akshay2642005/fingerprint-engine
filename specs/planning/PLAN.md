# Fingerprint Engine — Plan

Current: **v0.4.0** (2026-08-24), AMQP consumer + DLQ + full-stack compose shipped. The full
distributed-engine roadmap (M1–M5) is **complete**; the next milestone is unplanned
(see `specs/planning/PHASES.yaml` → next_phase). This file
replaces the pre-rework M1–M4 integration/quality plan (see
`specs/archive/` for the superseded items).

## Milestones

| Milestone | Scope | Status |
|-----------|-------|--------|
| M1 — Fill the gaps | fixtures, test utils, CI, package metadata (original 11-phase plan) | ✅ done |
| M2 — Integration SDKs | npm browser package; PyPI/Cargo dropped with the native SDK | ✅ done |
| M3 — Production readiness | benchmarks, fuzz, docs, security | ✅ done |
| M4 — Distributed rework | Zig 0.14.1, layered repo, engine/io/adapter/worker, AMQP, TS SDK, Docker | ✅ done (v0.2.0–v0.2.2) |
| M5 — Platform integration | **ingress** + full-stack compose + AMQP consumer/DLQ + release surface | ✅ done (v0.4.0) |

## M5 plan (delivered)

Sequenced by the 2026-08-08 audit (`specs/quality/audits/2026-08-08.md`); each slice
shipped in v0.4.0 (and follow-up PR #31):

| Slice | Contents | Status |
|-------|----------|--------|
| S1 | BUG-001 (SDK reply field swap) + H-1 tcp idle timeouts + H-2 graceful shutdown | ✅ done |
| S2 | Version single source of truth (BUG-002/003) | ✅ done |
| S3 | Application logging (`src/log.zig`, `--log-level`/`--log-format`, `--quiet`) | ✅ done |
| S4 | HTTP ingress MVP — executable, FPKG translation, worker pool, /healthz, Dockerfile, compose, CI, GHCR, e2e | ✅ done |
| S5 | AMQP push consumer + dead-letter queue | ✅ done |
| S6 | Full-stack compose + ingress release surface + docs refresh | ✅ done (compose DNS fix in PR #31) |

## Delivered in the rework (M4)

- Deterministic engine (Operation/Status/Request/Response, comptime dispatch).
- FPKG envelope + SignalPackage v2 + integrity; v1 compat.
- Async IO primitives; loopback/tcp adapters; AMQP 0-9-1 result publisher.
- Worker executable + Docker image (GHCR); hand-written TS browser SDK
  (collect → package → POST; middleware); WASM infra-only.
- O(1) `zig build` system; docs site; CONVENTIONS.md; CI/release pipelines;
  457 tests green.

## Out of scope for this repo

- The Go fraud platform (rules, matching at scale, admin workspace, AI
  agents) — separate repository, consumes our AMQP events (D15/D18/D19).
- Native SDK / C ABI (D10).
- RabbitMQ on the inbound path (D16 — inbound is FPKG request/response).

## Done criteria for M5

- [x] `zig build test --summary all` green after every slice.
- [x] Browser demo → ingress → worker → AMQP loop runs from `docker compose up`.
- [x] Ingress image published to GHCR; release notes list both images.
- [x] S1–S6 verification checklists signed off (see `specs/quality/verifications/`).
