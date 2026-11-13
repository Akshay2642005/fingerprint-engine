# Review — M8 (observability & ops)

**Date:** 2026-11-13
**Method:** `request-review` (Santa dual-blind AND-gate)
**Status:** ⚠️ **Gate not satisfied** — both reviewer subagents failed with
"Free usage limit reached" before producing reports. This document is a
single-pass manual review by the coding agent, *not* the required dual-blind
pair. Do not treat it as a PASS.

## Verification

`/Users/akshay/.zvm/0.14.1/zig build test --summary all` → **577/577 green**.

## Must-fix

### 1. Compose publishes the metrics ports to the host
`compose.yml` publishes `9091:9091` (worker) and `9090:9090` (ingress) on all
interfaces. ADR-014 §4 says the operational surface is `expose:`, not `ports:`
— reachable inside the network, never published to the host. The current
state exposes an unauthenticated `/metrics` and `/readyz` to anyone who can
reach the host.

- Introduced by `01ba3e6` ("fix(m8): harden broker recovery and record live
  gates"), most likely to allow live verification during the release gate.
- Fix (preferred): `expose: [9090]` / `expose: [9091]` in `compose.yml`, plus a
  `compose.override.yml` that publishes them for local dev/verification.
- Alternative: amend ADR-014 §4 with the exception and its rationale, and keep
  the published ports deliberate.

## Should-fix

### 2. Ingress `/readyz` can stay true after every worker dies while idle
`WorkerPool.liveCount()` counts slots holding a non-null client object, not
reachability. When a worker dies, the ingress's TCP connection stays non-null
until a request is attempted. The idle path only calls `refresh()` when
`liveCount() == 0` (`src/cmd/ingress/ingress.zig:427`), so a dead-but-connected
slot keeps the gauge at 1 and `/readyz` at 200 indefinitely.

- Recommendation: stamp each slot with `last_used_ns`; on the idle tick, drop
  and re-connect slots idle past a threshold so the gauge reflects reality.
- Or: document the approximation explicitly in ADR-014 §5 and bound it with a
  readiness TTL.

### 3. Files exceed the 300-line guideline
`src/obs/metrics.zig` (516) and `src/cmd/ingress/http.zig` (1026). The former is
a cohesive registry+renderer; the latter is pre-existing and grew by ~80 lines.
Flagged for a future split, not blocking.

## Consider

- **Histogram snapshot is not atomic as a group.** `observe()` increments
  `count`, `sum`, and one bucket separately, so a scrape can briefly observe
  `count ≠ Σ buckets`. Acceptable for monitoring; worth a comment.
- **`renderAll` (179 lines)** and **`start` (140–176 lines)** are long but are
  single cohesive handlers/lifecycle functions.
- **Test-only `early_stderr`** is capped at 8 KiB; sufficient for the startup
  block but silent truncation if startup logs grow.

## Positive notes

- All metric storage is atomic (`std.atomic.Value`), the hot path is one atomic
  add, and the `AtomicF64` CAS loop is correct.
- `Server` lifetime is documented ("must not be moved/copied after `start()`").
- `bindListener` sets `SO_REUSEADDR` only, never `SO_REUSEPORT`, so an occupied
  metrics port fails loudly.
- No secrets, no unbounded label cardinality, and no request/session ids in
  labels.
- Worker AMQP readiness is honest: a failed publish marks the connection
  disconnected and sets the gauge to 0; reconnect happens on the next frame.

## Next step

Retry the dual-blind pair when the model quota resets:

1. Reviewer A and Reviewer B, separate contexts, same brief.
2. AND-gate: both must have zero must-fix and score ≥ 94%.
3. Address must-fix #1 before any further merge activity.
