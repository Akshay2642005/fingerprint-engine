# Audit Report — M8 (observability & ops)

**Date:** 2026-11-13
**Scope:** M8 code landed in v0.7.0 — `src/obs/*`, `src/cmd/ingress/metrics.zig`,
`src/cmd/worker/metrics.zig`, and the instrumentation added to
`src/cmd/ingress/{http,ingress,pool}.zig`, `src/cmd/worker/{worker,collection_event}.zig`,
`src/integration_tests.zig`, plus the supporting tests.
**Auditor:** coding agent (self-review, `audit-code` skill).
**Verification:** `/Users/akshay/.zvm/0.14.1/zig build test --summary all` → 577/577 green;
Windows cross-compile of `ingress`/`worker` succeeds; manual UAT re-run green.

## Checklist

### Supply Chain & Security
- [✓] No new dependencies — std-only, `build.zig.zon` unchanged (no packages added).
- [✓] No secrets in diff (`sk-`, `ghp_`, `AKIA`, `.env` values) — grep clean.
- [✓] OWASP spot-check:
  - Injection: scrape endpoint is GET-only, no body parsing, fixed 8 KiB head cap.
  - Broken auth: metrics endpoint is intentionally unauthenticated but bound on an
    internal port (`expose:`, never `ports:`); documented in ADR-014 §4.
  - Sensitive data: no request id, session id, digest, or peer address in any label
    (observability.md §Correlation); verified by the catalog and the render tests.
  - Misconfiguration: `--metrics-listen=off` is explicit and logged; invalid/occupied
    addresses exit 1 instead of silently disabling the surface.
- [✓] No unaddressed HIGH findings. One defect found and fixed in this audit (see
  "Discovered defect" below) on branch `fix/worker-readyz-publish-none`.

### Provenance & Metadata
- [✓] New artefacts cite ADR/commit: `src/obs/*` and `src/cmd/*/metrics.zig` carry
  `story m8-observability` doc comments; ADR-014…017 adopted and referenced.
- [✓] Implementation steps reference ADR-014 §2/§4/§5 and the metric catalog.

### Law of Demeter
- [✓] Collaborators talk to immediate neighbors; callbacks are context-pointer based
  (`RenderFn`, `ReadyFn`), keeping `obs` free of engine/adapter/cmd imports.

### CONVENTIONS.md Compliance
- [✓] All output files under `specs/` (state files, ADRs, audit report).
- [✓] No `gh issue create` / direct GitHub REST calls in new code.
- [✓] `gh` used only for PRs (`gh pr create`).

### Scope
- [✓] Changes limited to M8; no speculative features.
- [✓] Boy Scout applies to files opened for the gate failure (see defect fix).

### Boy Scout Rule
- [✓] No dead code or commented-out blocks in the new modules (`grep TODO/FIXME/XXX/HACK` clean).
- [~] `src/obs/metrics.zig` (516 lines) and `src/cmd/ingress/http.zig` (1026 lines)
  exceed the 300-line guideline. The former is a single cohesive registry+renderer
  whose type factories are inseparable; the latter is pre-existing and grew by ~80
  lines. No split warranted now; flagged for a future cleanup pass.

### Types and Safety
- [✓] No `any` types (Zig); all public functions typed; no `@ts-ignore` equivalent.
- [✓] `@enumFromInt` is only used on exhaustive local enums (`Op`, `JobResult`, …),
  never on the non-exhaustive `engine.Operation` — see `metrics.opOf`.

### Test Coverage
- [✓] Every new function has at least one test:
  - `statusClass`, `authReason` → `tests/cmd/ingress_http_test.zig`
  - registry render (ingress + worker) → `tests/obs/metrics_test.zig`, `tests/worker/metrics_test.zig`
  - scrape listener + occupied port → `tests/obs/scrape_test.zig`
  - `--metrics-listen` parse → `tests/cmd/ingress_test.zig`, `tests/worker/worker_test.zig`
  - e2e `/metrics` + `/readyz` 200/503 → `src/integration_tests.zig`
  - HMAC rejection reasons + replay-cache depth → `src/integration_tests.zig`
- [✓] Tests exercise public interfaces (registry render, CLI parse, HTTP scrape), not
  internals.
- [✓] F.I.R.S.T: tests use fixed buffers, no shared state, fast.

### SOLID and Heuristics
- [✓] Single Responsibility: `obs/metrics.zig` (storage+render), `obs/scrape.zig`
  (transport), `cmd/*/metrics.zig` (catalog+mapping) are separate.
- [✓] Dependency Inversion: `obs` is a leaf module; `cmd/*` depend on it, not the
  reverse. Callbacks are context-pointer based.
- [✓] Open/Closed: extended through the registry struct, not by modifying stable code.

### Refactoring Smells (Fowler)
- None detected. No duplicated code (the two `metrics.zig` catalogs are intentionally
  separate ingress/worker surfaces, not copy-paste).

### Code Style (CONVENTIONS.md)
- [✓] Early returns over nested ifs; max 2 levels of indentation in new code.
- [✓] Conditionals expressed as positives where practical.
- [✓] Comments explain WHY, not WHAT (e.g. the `SO_REUSEPORT` rationale).
- [~] Function length: `renderAll` (179 lines) in `scrape.zig` and `start` (140–176
  lines) in both apps exceed 20 lines. These are single cohesive handlers/lifecycle
  functions; splitting them would obscure the flow. Flagged, not fixed.

### Red Flags
- Rationalization caught: I initially considered leaving the `--publish=none` readiness
  bug as "out of scope for the audit" because no test exercises it. That is not
  acceptable — the documented contract (ADR-014 §5) is the spec, and a silently
  503 worker with no broker is a real defect. Fixed on `fix/worker-readyz-publish-none`.
- Rationalization caught: I considered skipping the file-size flag because "it's a
  registry." Noted above instead of silently ignoring.

## Discovered defect (fixed)

**Defect:** `src/cmd/worker/worker.zig` `isReady` required `amqp_connected > 0`
unconditionally, but with `--publish=none` no publisher is created and the gauge
stays 0, so `/readyz` always returned 503 for a worker that was never given a
broker — contradicting ADR-014 §5 ("with `--publish=none` the worker is ready as
soon as it is listening").

**Fix:** set `registry.amqp_connected` to 1 when `options.publish == .none`.
Branch: `fix/worker-readyz-publish-none` (commit `2323713`), PR to follow.
Tests: 577/577 still green.

## Result

All checklist items PASS except two documented `[~]` style flags (file size and
function length) which are accepted as-is for lifecycle/registry code. One defect
was found and fixed during the audit. The M8 code is otherwise clean and ready for
an independent second opinion.

**Suggested next step:** run `request-review` for an independent reviewer pass, or
open the follow-up PR for `fix/worker-readyz-publish-none`.
