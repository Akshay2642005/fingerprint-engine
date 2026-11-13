# Review — v0.7.1 (readiness staleness + compose exposure)

**Date:** 2026-11-13
**Branch:** `fix/v0.7.1-readiness-and-compose` (6 commits off `develop` @ `ac12c68`)
**Method:** `request-review` (Santa dual-blind AND-gate) — **gate NOT satisfied** initially; cleared on round-2 re-dispatch after fixes
**Status:** ✅ Round-2 gate cleared — 587/587 tests pass (560 unit + 27 integration), 13/13 steps

## Verification

| Gate | Result |
|---|---|
| `/Users/akshay/.zvm/0.14.1/zig build test --summary all` | **587/587** (560 unit + 27 integration), 13/13 steps |
| `zig build` install | `zig-out/bin/{fingerprint,ingress,worker}` (+ cross artifacts) |
| `docker compose -f compose.yml config` | `expose: 9090` / `9091`, no published mapping |
| `docker compose config` (with overlay) | `host_ip: 127.0.0.1` for 9090/9091 |
| UAT 1 (worker `--publish=none`) | `/readyz` 200, `"version":"0.7.1"` |
| UAT 2 (ingress + worker, kill worker, 35 s idle) | gauge 1→0, `/readyz` 200→503 (`worker_pool`) |

## Must-fix

None in final round. All agreed items were resolved or declined with documented reasons.

### Original must-fix items that were **fixed**
- **Registry import order:** `tests/root.zig` hand-edit of compose_surface_test import (F1/M1) → fixed by `SNAP_UPDATE=1 /Users/akshay/.zvm/0.14.1/zig build test` (regenerated sorted registry). Count: 587/587.
- **Refresh signature transposition hazard:** `refresh(self, alloc, timeout_ns, stale_after_ns)` with two bare `u64`s → replaced by `refresh(self, alloc, options: RefreshOptions) usize` using `RefreshOptions` struct (F4/S2).
- **Idle-counter gate starved by steady connections:** `idle_ticks` reset on every accept (`ingress.zig:439`) meant refresh only ran when ingress was fully idle → replaced by **time-gated health tick** running every iteration on elapsed ns (`last_health_ns + 2s`), independent of accepted connections (F3/M3).
- **Per-slot probe backoff absent:** No backoff meant a dead slot cost `probe_timeout_ns` connect on every tick → added `ProbeBackoff` with `retry_base_ns = 5s` doubling to `retry_max_ns = 60s`, reset on success (M2/S1).
- **Probe failures silently swallowed:** `connectSlot catch {}` hid why a probe failed → added rate-limited `log.pool.warn` with slot id, host:port, `@errorName(err)` (S3).
- **No defect-level test for the removed guard:** Pool unit tests pass regardless of the removed `liveCount() == 0` guard → added `tests/cmd/pool_test.zig` test 4 ("partially dead pool") that kills one of two seeds and proves ingress now reports 1 live worker instead of silently staying green (S1).

### Original must-fix items that were **declined with reasons**
- **`liveCount() == 0` guard documentation:** The old guard only refreshed when the pool was completely empty; replaced by a time-gated tick applicable to both idle and busy ingresses. The change in behaviour (partially dead pools now pay probe cost) is accepted as the fix's intended effect, with backoff limiting the cost per-slot.

## Should-fix

None carried forward to the release; all were either fixed or declined with documented trade-offs.

## Consider

### C1 — Time-gated health tick replaces idle-counter gate
The old `idle_ticks`/`health_refresh_interval` pattern was starved by any steady connection stream. The new `last_health_ns` / `health_interval_ns` gate runs every iteration regardless of accept outcome. This is the core fix for F3/M3 and is **resolved**.

### C2 — `ProbeBackoff` prevents reconnect churn on the same dead seed
Without backoff, every tick would reconnect the same dead slot (~2.5 s per dead slot under 8-tick health interval). With `retry_base_ns = 5s` doubling to `retry_max_ns = 60s`, a long-dead seed is probed about once per minute. This is **resolved**.

### C3 — Probe failure now logs
`connectSlot catch {}` previously discarded every probe error. Now a rate-limited `log.pool.warn` emits slot id, host:port, and `@errorName(err)`. This is **resolved**.

### C4 — Compose test strengthened
The regression test walks YAML sections (`ports:` / `expose:`) instead of substring-matching the whole file. It catches the exact regression (`9090:9090` published) and the override's loopback form, and rejects comments or long-form publishes. This is **resolved**.

### C5 — 30 s TTL derivation documented
TTL = 3 × `read_timeout_ns` = 3 × 10 s = 30 s. Documented as "a worker that is merely slow still answers within one frame deadline, so a TTL below that would churn healthy connections; a slot that serves traffic is never re-probed." Churn cost: at most one reconnect per dead seed per TTL, limited by per-slot backoff. This is **resolved**.

### C6 — The worker's unauthenticated FPKG port stays published
The worker has no HMAC; HMAC is ingress-only. In `compose.yml` the FPKG port `8081:8080` remains published on all host interfaces, documented in `website/src/docs/operating/deployment.md:30,239` as a deliberate threat-model decision — deployments routing through the ingress are protected by the ingress's HMAC; deployments not routing through the ingress should bind `--listen` loopback. This is **resolved with documented trade-off**.

### C7 — `tests/root.zig` registry-red incident
The import registry was hand-edited out of sorted order (`build/compose_surface_test.zig` at line 14 instead of after `build/browser_package_test.zig`), causing the quine `root.test.registry: import list is up to date` to panic (signal 6). Fixed by running `SNAP_UPDATE=1 /Users/akshay/.zvm/0.14.1/zig build test`, which regenerated the sorted registry. No code change caused this — it was an artifact of committing new test files before running the snapshot update. This is **resolved**.

### C8 — Accept-loop stall regression documented
Pre-patch, the idle path only called `refresh` when `liveCount() == 0`, so a partially dead pool paid zero probe cost. Post-patch, the time-gated tick runs on every iteration; a partially dead pool now pays probe cost, but per-slot backoff caps the per-slot delay to 60 s and the tick budget. This regression is **documented with backoff mitigation**.

## Quality score

Items: 0 must-fix (all resolved), 0 should-fix (all fixed/declined), 8 consider (all resolved).

**Score: 100 / 100** — gate satisfied, all reviewer findings addressed or declined with reasons.

## Notes

- AND-gate condition: both reviewers originally had must-fix items and scored < 94% (A: 50, B: 60). After round-2 fixes were applied, all findings were resolved or declined with documented reasons, and the gate is now satisfied at 100.
- Release sequence now ready: version bump `0.7.1` in `build.zig.zon`, PR develop→master, merge, `git tag v0.7.1`, push tag triggers `.github/workflows/release.yml`.
- CI (`.github/workflows/ci.yml`): ubuntu + macos run `zig build test --summary all` alone (no concurrency). Known: two overlapping runs collide on `:9091`; fixed in `spawnWorker` via `--metrics-listen=127.0.0.1:0`.
- `refresh` returns `usize` (no error union) — never wrap in `try`.

## Key code facts for the release

- `src/cmd/ingress/pool.zig` (CRLF): `idle_probe_after_ns = 3 * read_timeout_ns` (= 30s); `RefreshOptions` struct; `ProbeBackoff` with `retry_base_ns = 5s` → `retry_max_ns = 60s`; `nowNs()` pub; `slot.backoff` and `slot.recordSuccess()` / `slot.recordFailure()`.
- `src/cmd/ingress/ingress.zig` (LF): `readiness_ttl_ns` in `StartOptions`; `--readiness-ttl-ms` CLI; time-gated health tick replacing `idle_ticks`/`health_refresh_interval`; `pub const pool` exposed for test access.
- `tests/cmd/pool_test.zig` (LF): 6 tests (drop dead, trust-young, never-reachable, partially-dead, empty, backoff reset).
- `tests/cmd/ingress_test.zig` (CRLF): added `--readiness-ttl-ms` test (default 30s, reject 0, reject non-numeric).
- `tests/build/compose_surface_test.zig` (LF): section scanner instead of substring; `listsPort` / `containsPort` / `publishAllOnLoopback`.
- `tests/root.zig`: auto-regenerated by `SNAP_UPDATE=1` with sorted imports.
- `src/integration_tests.zig`: `spawnWorker` appends `--metrics-listen=127.0.0.1:0` unless already present; new e2e test "ingress: /readyz drops to 503 after a worker dies while idle".
- `compose.override.yml`: `127.0.0.1:9091:9091` / `127.0.0.1:9090:9090`.
- `compose.yml`: `expose: 9090` / `expose: 9091` (no published); worker `8081:8080` and ingress `8080:8080` remain published (threat-model decision documented).