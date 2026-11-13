# Audit Report — v0.7.1

**Date:** 2026-11-13  
**Scope:** `fix/v0.7.1-readiness-and-compose` off `develop` @ `ac12c68` —  
`src/cmd/ingress/{pool,ingress}.zig`, `compose.yml`, `compose.override.yml`,  
`tests/cmd/pool_test.zig`, `tests/build/compose_surface_test.zig`,  
`build.zig.zon`, plus docs.  
**Auditor:** coding agent (self-review, `audit-code` skill).  
**Verification:** `/Users/akshay/.zvm/0.14.1/zig build test --summary all` →  
**587/587 green** (560 unit + 27 integration); `zig build` installs the  
`ingress`/`worker`/`fingerprint` binaries; both manual UAT drills pass (see  
`specs/quality/verifications/v0.7.1.md`).  

## Checklist  

### Supply Chain & Security  
- [✓] No new dependencies — std-only; `build.zig.zon` changed only `.version`.  
- [✓] No secrets in the diff.  
- [✓] OWASP spot-check:  
  - Exposure: this patch *reduces* attack surface. The unauthenticated  
    `/metrics` and `/readyz` were published on all host interfaces and are now  
    `expose:` only; the local override binds loopback (`127.0.0.1`), verified  
    with `docker compose config` (`host_ip: 127.0.0.1`).  
  - Injection: no new parsing of external input. The new code compares  
    monotonic-ish timestamps and calls `connect`.  
  - DoS: the readiness re-probe is bounded by `timeout_ns` per slot and only  
    runs on the time-gated idle tick (2 s with no accepted connection), so the  
    delay is paid by a request arriving in that window, not by steady traffic.  
  - Data exposure: no new logging of addresses beyond the existing connect log.  

### Provenance & Metadata  
- [✓] New constants and fields carry doc comments citing ADR-014 §5.  
- [✓] Docs updated in the same branch (`observability.md`,  
  `0014-observability-surfaces.md`, CHANGELOG, release checklist).  

### Law of Demeter / Design  
- [✓] `WorkerPool` owns slot lifecycle; the ingress only reads the returned  
  count. No new cross-module reach-through.  
- [✓] `isStale` lives on `Slot` (data + behaviour together).  
- [✓] `pub const pool` mirrors the existing `http`/`hmac`/`metrics` exports  
  and is done solely so the tests can drive the probe without spawning an  
  ingress. No production consumer changes.  

### CONVENTIONS.md Compliance  
- [✓] Conventional Commits: two `fix:`, one `docs:`, one `chore:`.  
- [✓] No AI attribution, no `Co-authored-by`.  
- [✓] Work on a branch off `develop`; `master` untouched.  
- [✓] Output under `specs/`.  

### Boy Scout Rule  
- [✓] No TODOs/FIXMEs introduced; no commented-out code.  
- [✓] `pool.zig` has CRLF line endings (pre-existing at `develop`; the file is  
  already flagged by `zig fmt --check` along with ~60 other files, none of  
  which are gated in CI). This patch preserves CRLF to keep the diff  
  reviewable instead of normalising the whole file.  

### Types and Safety  
- [✓] `nowNs()` clamps a negative `nanoTimestamp` to 0 before `@intCast`, so  
  no undefined behaviour on a pre-epoch clock.  
- [✓] `isStale` uses wrapping subtraction, so a backwards clock jump degrades  
  to "stale" (one extra reconnect) rather than an underflow panic in safe  
  builds.  
- [✓] `refresh` closes the client before clearing the slot, so no leak if the  
  reconnect fails.  

### Test Coverage  
- [✓] `tests/cmd/pool_test.zig` (6 tests):  
  1. `pool: refresh drops a connection whose worker went away` (TTL 0 after kill → 0;  
     asserts `liveCount() == 1` before, i.e. the defect state).  
  2. `pool: refresh trusts a connection younger than the readiness TTL` (uses  
     `pool.idle_probe_after_ns` and `pool.idle_probe_after_ns - 1`, production constants).  
  3. `pool: refresh reports zero when the seed was never reachable`.  
  4. `pool: a partially dead pool reports one live worker` (2 seeds, kill one,  
     TTL 0 → 1) — the exact state that kept `/readyz` green before.  
  5. `pool: an empty pool has no live workers and cannot be made live` (`init(alloc, &.{})`).  
  6. `pool: probe backoff doubles to the cap and resets on success` (base → 2x → capped  
     at `retry_max_ns` after 16 failures → reset; boundary asserts `active(base-1)` true /  
     `active(base)` false).  
- [✓] `tests/build/compose_surface_test.zig` (2 tests): no published  
  `9090`/`9091` mapping plus `expose:` present; override binds loopback.  
- [✓] Manual UAT: worker `--publish=none` → `/readyz 200`; ingress + worker →  
  gauge 1/`200`, kill worker, 35 s idle → gauge 0/`503`.  
- [✓] F.I.R.S.T: sockets are ephemeral loopback, no fixed ports, no sleeps  
  beyond the connect handshake, no shared state between tests.  

### SOLID and Heuristics  
- [✓] Single Responsibility: `refresh` decides reachability; the ingress  
  publishes the count.  
- [✓] No duplication; no new abstraction for one caller.  

### Refactoring Smells (Fowler)  
- None detected. `refresh` grew from 6 to ~20 lines, still one coherent  
  operation.  

### Accepted trade-offs (explicit, not silent)  
- The re-probe blocks the accept loop for up to `probe_timeout_ns` per probed  
  slot. It only runs on the **time-gated idle tick (~2 s with no accepted  
  connection)**, so the delay is paid by a request arriving in that window, not  
  by steady traffic. A permanently unreachable seed costs at most 250 ms every  
  2 s while the ingress is idle.  
- Readiness is now *bounded-stale* (TTL + tick) rather than live. A strictly  
  live probe would need a protocol-level ping the worker does not have, or a  
  connect per scrape.  

### Red flags  
- Rationalization caught: "the pool only refreshes when empty" was documented  
  in the code comment as if intentional. It was a defect, not a design; the  
  comment and behaviour are both corrected.  
- Registry-red incident: `tests/root.zig` import registry was hand-edited out of  
  sorted order (`build/compose_surface_test.zig` at line 14 instead of after  
  `build/browser_package_test.zig`), causing the quine `root.test.registry: import  
  list is up to date` to panic (signal 6) and `zig build test` to exit 1 on commits  
  `8f617f4`..`770a3d0`. Fixed by running `SNAP_UPDATE=1 /Users/akshay/.zvm/0.14.1/zig  
  build test`, which regenerated the sorted registry. No code change caused this  
  — it was an artifact of committing new test files before running the snapshot  
  update.  

### Result  

All items PASS. No defects found during this audit. Ready for the independent  
review gate.