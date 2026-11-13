# Review — v0.7.1 (readiness staleness + compose exposure)

**Date:** 2026-11-13
**Branch:** `fix/v0.7.1-readiness-and-compose` (4 commits off `develop` @ `ac12c68`)
**Method:** `request-review` (Santa dual-blind AND-gate) — **gate NOT satisfied**
**Status:** ⚠️ Two independent reviewer subagents were dispatched with identical
briefs and separate contexts; neither returned a report. This document is a
single-pass second look by the coding agent, recorded as the fallback with the
same disclosure used in `specs/verifications/REVIEW-m8.md`. It is **not** a PASS
under the AND-gate (two reviewers, zero must-fix each, score ≥ 94%).

## Verification

| Gate | Result |
|---|---|
| `/Users/akshay/.zvm/0.14.1/zig build test --summary all` | **582/582** (556 unit + 26 integration), 13/13 steps |
| `zig build` install | `zig-out/bin/{fingerprint,ingress,worker}` (+ Windows cross artifacts) |
| `docker compose -f compose.yml config` | `expose: 9090` / `9091`, no published mapping |
| `docker compose config` (with overlay) | `host_ip: 127.0.0.1` for 9090/9091 |
| UAT 1 (worker `--publish=none`) | `/readyz` 200, `"version":"0.7.1"` |
| UAT 2 (ingress + worker, kill worker, 35 s idle) | gauge `1`→`0`, `/readyz` `200`→`503` (`worker_pool`) |

## Must-fix

None found.

## Should-fix

### 1. The readiness fix is proven by a unit test, not by the loop that ships it
`tests/cmd/pool_test.zig` pins `WorkerPool.refresh` semantics (drop a dead
connection, respect the TTL, report zero for an unreachable seed), but nothing
automated pins the ingress idle path that *calls* it — the actual defect was the
`liveCount() == 0` guard in `src/cmd/ingress/ingress.zig`, which no test now
covers. `src/integration_tests.zig` could not close the gap cheaply: proving it
end to end means idling past `pool.idle_probe_after_ns` (30 s).

- Mitigation in place: UAT 2 above reproduces the pre-fix behaviour and the
  post-fix transition manually, and the checklist records it.
- Not fixed: making the TTL injectable (CLI flag or `StartOptions` field) purely
  for a test would add production surface for test convenience. Accepting the
  manual evidence instead. Revisit if the ingress loop gets a seam for other
  reasons.

### 2. A stale slot loses a possibly-usable connection before the probe
`refresh` closes the pooled client and then reconnects, so if the *probe* fails
transiently (worker restarting, accept backlog momentarily full) a single-worker
ingress reports 503 until the next tick reconnects. Connecting first and swapping
would keep the old socket on probe failure, at the cost of a second fd and a more
convoluted invariant.

- Accepted as-is: close-then-connect is what makes "a half-open socket is never
  mistaken for a reachable worker" true, which is the property the fix exists to
  establish. Transient probe failure costs one tick (~2 s) and is visible in
  `pool: connected` / `pool: unavailable` logs.

## Consider

- **The overlay auto-loads.** Docker Compose merges `compose.override.yml` by
  default, so `docker compose up` in any directory still publishes 9090/9091 —
  now loopback-only, so not reachable off-host, and documented in the file
  header. Deployments that must not publish at all should use
  `docker compose -f compose.yml up`. No production compose file exists in the
  repo to encode that, so the constraint lives in the header comment and
  ADR-014 §4.
- **`tests/build/compose_surface_test.zig` asserts on substrings.** It reads both
  files relative to the process cwd, which is the repo root under `zig build
  test`. It catches the exact regression (`9090:9090`) and the override's
  loopback form, but a restructured YAML could pass while changing meaning. A
  `docker compose config` assertion would be more faithful and is not worth
  shelling out from a unit test.
- **Blocking on the idle path.** A dead slot costs up to `probe_timeout_ns`
  (250 ms) per probe inside the accept loop, every health tick while it stays
  down. Unchanged in magnitude from the pre-fix `liveCount() == 0` branch — the
  difference is that a *partially* dead pool now pays it too. Acceptable because
  the tick only fires on an idle ingress (`health_refresh_interval` idle accepts)
  and TCP refusal normally returns in microseconds.

## Positive

- The TTL is stamped on the strongest available liveness signal — a completed
  exchange — so busy slots are never churned.
- `nowNs` clamps a pre-epoch clock and `isStale` uses wrapping subtraction, so a
  clock adjustment degrades to one extra reconnect instead of a permanently
  stale or permanently churning slot.
- The `errdefer client.close()` in `connectSlot` means repeated failed probes
  cannot leak file descriptors, which matters now that probes are periodic.
- Dropping the slot in `request` on exchange failure is unchanged and still the
  first line of defence; `refresh` only handles the case where no request ever
  arrives.
- Compose change narrows exposure without touching the public FPKG surface
  (`8080`/`8081` remain published) and keeps the documented Ports contract in
  `specs/architecture/observability.md` true.
- Version, changelog, ADR-014 §5 wording, observability doc, and the release
  checklist all agree that the engine version is `0.7.1` and the browser SDK
  stays `1.0.0-rc.1`.

## Next step

Retry the dual-blind pair when model quota allows; both must report zero
must-fix and ≥ 94%. Until then this branch ships on documented single-pass
review plus manual UAT, matching the precedent set for v0.7.0.
