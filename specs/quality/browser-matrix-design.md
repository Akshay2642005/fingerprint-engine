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
- Pin manifest: `tests/fixtures/browser/pins.json` — `{ schema, provisional,
  note, playwright_version, captured_at, runner, engines: { <engine>:
  { browser, browser_family, digest, signal_count } } }`. `provisional:
  true` marks a local (non-authoritative) capture; the golden-capture
  workflow rewrites it to `false`.
- Chromium-family executable: the locally installed **Brave**, never
  Chrome/Chromium (policy — no `playwright install chromium`). The runner
  keeps `chromium` as the engine-class key; `FP_BRAVE=/path/to/brave`
  overrides auto-detection. Brave is used because its shields *hide* the
  connection family (signals 62–66) that drifted in vanilla Chromium
  (`ConnectionDownlink` 10→9.9→9.4), and its session-scoped
  fingerprinting randomization is pinned via a persistent profile
  (`tests/browser-matrix/.profiles/`, git-ignored) plus the
  `brave.profile.managed_default_content_settings.brave_fingerprinting_v2
  = 1` pref — without that seed, HardwareConcurrency/DeviceMemory/
  CanvasHash/AudioHash re-randomize every launch.

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
- D3 (shipped): `browser-matrix` on `ubuntu-24.04` gates PRs —
  pins-absent → green "capture pending"; pins-present → **Layer 1** strict
  (`hash-verify --check`) + **Layer 2** live collect → `hash-verify
  --check --live` (digest mismatch fails; while `provisional: true` the
  live comparison is warn-only) + per-signal diff uploaded as the
  `browser-matrix-diff` artifact.
- D3 fallback (provisional exclusion list): if CI shows run-to-run noise,
  gate on the stable subset documented here and formalized in D5 — drift
  stays visible via the diff artifact, never silently dropped.

## Capture runbook (D3)

CI is the golden source of truth; local macOS captures are informational.

1. Merge the PR that adds/updates the runner, snapshots, or `pins.json`.
2. Actions → **Golden Capture** → *Run workflow* → pick `develop`.
   Until `workflow_dispatch` registers (it needs this file on the default
   branch, which lands at v0.5.0), push an **empty commit to `develop`**
   whose subject contains `[golden-capture]` — the job guard on the push
   trigger runs the capture. Either way the run installs the same pins as
   `browser-matrix` (ubuntu-24.04, Zig 0.14.1, Node 22, Brave 1.97.56,
   Playwright lockfile), collects 3 × 3 repeats, writes `pins.json`
   (`provisional: false`), verifies Layer 1 against the new pins, and
   auto-commits fixtures + pins back to the branch (`chore(golden): …`).
3. GITHUB_TOKEN pushes do not trigger CI — see the authoritative pins
   verified by pushing any follow-up commit to `develop` (e.g. the STATUS
   docs update) or by opening the next PR.
4. Re-run the capture on: Playwright lockfile bump (pin-reset event),
   Brave version bump, runner-image change, or any intended signal-set
   change. The commit diff of `pins.json` records the reset.

Risks: GitHub may roll the `ubuntu-24.04` image between capture and gate
(fonts/GPU libs), and Layer 2 can surface engine run-to-run noise — both
land in the D3 fallback above (stable subset in D5), never as a silent
pin change.

## Non-goals

- No `stable_core_digest` engine op in W3 (M7 wire work, D-v1-5). D5 lands
  the registry `core` flag (D-v1-7) + the deterministic subset list + the
  contract doc.
- No local gating: `npm`-level or `zig build` steps for the matrix stay
  opt-in; CI owns the gate.
