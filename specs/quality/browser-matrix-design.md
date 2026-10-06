# Browser golden matrix — runner design (W3-D1)

Story: `m6-runner-design` (SCRUM-30). Authority for the wire format remains
DESIGN §9 / ADR-012; this doc covers only the cross-browser collection
runner, its inputs, and the two-layer golden contract.

## Goal

Prove the SDK → engine path is deterministic per browser engine
(Chromium, Firefox, WebKit): collect real signals in each engine, serialize
with the SDK, hash with the engine, and pin a digest per engine. Run-to-run
drift inside one engine is the defect signal; cross-engine differences are
expected (UA, platform, GPU) and triaged in D4/D5.

## Layout

- Runner: `tests/browser-matrix/` — its own `package.json` with Playwright
  pinned (lockfile committed). The SDK package keeps only `typescript` as a
  devDependency; the npm package ships `dist/` only. Root has no package.json.
- Page harness (D2): a minimal static server + HTML page loading the SDK
  from `dist/` (`zig build clients:browser` output). No new SDK public
  surface — the runner deep-imports `dist/index.js` and
  `dist/collectors/index.js` (W4 freezes the public API).
- Snapshots: `tests/fixtures/browser/{chromium,firefox,webkit}.signals.json`.
- Pin manifest: `tests/fixtures/browser/pins.json` —
  `{ engine, playwright_version, digest, signal_count, captured_at }` per
  engine.

## Snapshot schema

Mirrors `tests/fixtures/fingerprints/signal-package-v2.signals.json`
(`schema_version`, `sdk_version`, `collected_at`, `package_id` hex,
`signals[]` of `{ id, type, value }`; byte values as hex strings). Committed
snapshots use fixed `sdk_version`/`collected_at`/`package_id` values — the
digest covers only the canonicalized feature buffer, so replay identity
never affects the pin (W2-D5).

## Two layers

- **Layer 1 — static codec regression (no browsers).** Committed snapshot
  JSON → `encodeSignalPackage` (deep import from `dist/`) →
  `zig build scripts -- hash` (in-process engine `hash` op, D3; same code
  path as `generate fixture` / `worker request`) → assert equals that
  engine's pin in `pins.json`.
- **Layer 2 — live collection.** CI job launches Playwright × 3 engines
  headless with fixed viewport/locale/timezone, collects via
  `collectSignals` in-page, serializes, hashes → assert equals the pin, and
  emits a per-signal diff against the committed snapshot (D4's raw material).
  The harness also pins `screen.*`/outer dims to the viewport via init
  script (Firefox otherwise reports the host display).

## Environment rules

- **CI is the source of truth.** Snapshots and pins are captured by a
  `workflow_dispatch` capture flow on the pinned runner image; the gating
  job verifies on the same image. Local runs are informational only —
  macOS/Linux differ (fonts, GPU renderer, UA platform) and can never match.
- Playwright version is pinned by the runner lockfile; a lockfile bump is a
  pin-reset event (re-capture in CI, note it in the manifest).

## CI job contract

- D1: `browser-matrix` skeleton — verifies the design doc exists; green
  trivially before fixtures/runner exist.
- D3: real assertions for both layers; gates `develop`/`master` PRs.
- D3 fallback (provisional exclusion list): if CI shows run-to-run noise,
  gate on the stable subset documented here and formalized in D5 — drift
  stays visible via the diff artifact, never silently dropped.

## Non-goals

- No `stable_core_digest` engine op in W3 (M7 wire work, D-v1-5). D5 lands
  the registry `core` flag (D-v1-7) + the deterministic subset list + the
  contract doc.
- No local gating: `npm`-level or `zig build` steps for the matrix stay
  opt-in; CI owns the gate.
