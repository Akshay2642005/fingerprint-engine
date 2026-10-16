<!-- story: m6-signal-triage -->
# Signal determinism matrix (W3-D4)

Story: `m6-signal-triage` (SCRUM-43). Scope: the cross-browser golden matrix
(W3-D1..D3). Authority for the wire format remains DESIGN §9 / ADR-012; this
doc records **which collected signals are deterministic**, the evidence behind
that verdict, and the input it feeds into W3-D5 (the determinism contract and
the stable-core subset).

Status: **complete** — no run-to-run non-determinism observed; matrix published.

## Question

For every signal the SDK collects, is its value **deterministic** — i.e. does
it produce the same value on repeated collections in the same environment?
Non-determinism here is the defect signal (two identical sessions must hash to
the same digest); cross-environment differences (OS / UA / GPU / fonts) are
**expected** and are not defects.

## Evidence

Two independent sources, per `browser-matrix-design.md` ("CI is the source of
truth; local runs are informational"):

1. **Authoritative — CI golden capture** (`golden-capture` run `37723823405`,
   `ubuntu-24.04`, `provisional: false`). All three engines collected **×3
   repeats** and reported `stable across 3 repeats`:
   - chromium (Brave 155.1.97.56): 71 signals
   - firefox (155.0): 61 signals
   - webkit (26.6): 67 signals
   Raw log: `collect.log` in that run's `golden-capture` artifact.
2. **Supporting — local Brave sweep** (macOS, Brave 1.97.57): Chromium family
   collected **×10 repeats**, `stable across 10 repeats`.

The run-to-run comparison is `diffRepeats` in `collect.mjs` (compares every
repeat against run 1 per signal id). The cross-capture/cross-environment
comparison is `diff-snapshots.mjs` (live capture vs committed golden, per
signal).

## Determinism classes

| Class | Meaning | Verdict |
|-------|---------|---------|
| `stable` | Static browser/DOM capability or config; environment-independent | **y** |
| `env` | Derived from OS / UA / platform / codecs / installed voices / fonts; deterministic within an environment, differs across environments | **y** |
| `device` | Hardware/capacity or render-entropy derived (cores, memory, canvas/audio/webgl/fonts/screen); deterministic per device | **y** |
| `condition` | Depends on live runtime state (network, battery, permissions); stable while the condition holds | **y\*** |

`y*` = deterministic within a fixed session/condition, but **expected to change
as the underlying condition changes** (e.g. battery drains, network reconnects,
a permission is granted). It is not run-to-run noise; it is genuine state.

## Matrix

Columns: `C`/`F`/`W` = present in the chromium/firefox/webkit golden snapshot
(✓) or absent (–); `Det` = deterministic (y = verified run-to-run stable;
y\* = condition-dependent).

| ID | Signal | Type | C | F | W | Det | Class |
|----|--------|------|---|---|---|-----|-------|
| 0 | UserAgent | String | ✓ | ✓ | ✓ | y | env |
| 1 | Language | String | ✓ | ✓ | ✓ | y | stable |
| 2 | Languages | StringArray | ✓ | ✓ | ✓ | y | stable |
| 3 | Platform | String | ✓ | ✓ | ✓ | y | env |
| 4 | Vendor | String | ✓ | ✓ | ✓ | y | stable |
| 5 | Product | String | ✓ | ✓ | ✓ | y | stable |
| 6 | ProductSub | String | ✓ | ✓ | ✓ | y | stable |
| 7 | AppName | String | ✓ | ✓ | ✓ | y | stable |
| 8 | AppVersion | String | ✓ | ✓ | ✓ | y | env |
| 9 | CookieEnabled | Boolean | ✓ | ✓ | ✓ | y | stable |
| 10 | DoNotTrack | String | ✓ | ✓ | ✓ | y | stable |
| 11 | HardwareConcurrency | Integer | ✓ | ✓ | ✓ | y | device |
| 12 | MaxTouchPoints | Integer | ✓ | ✓ | ✓ | y | device |
| 13 | DeviceMemory | Float | ✓ | – | – | y | device |
| 14 | PdfViewerEnabled | Boolean | ✓ | ✓ | ✓ | y | stable |
| 16 | DeviceRam | Integer | ✓ | – | – | y | device |
| 17 | ScreenWidth | Integer | ✓ | ✓ | ✓ | y | device |
| 18 | ScreenHeight | Integer | ✓ | ✓ | ✓ | y | device |
| 19 | AvailableWidth | Integer | ✓ | ✓ | ✓ | y | device |
| 20 | AvailableHeight | Integer | ✓ | ✓ | ✓ | y | device |
| 21 | ColorDepth | Integer | ✓ | ✓ | ✓ | y | device |
| 22 | PixelDepth | Integer | ✓ | ✓ | ✓ | y | device |
| 23 | DevicePixelRatio | Float | ✓ | ✓ | ✓ | y | device |
| 24 | InnerWidth | Integer | ✓ | ✓ | ✓ | y | device |
| 25 | InnerHeight | Integer | ✓ | ✓ | ✓ | y | device |
| 26 | OuterWidth | Integer | ✓ | ✓ | ✓ | y | device |
| 27 | OuterHeight | Integer | ✓ | ✓ | ✓ | y | device |
| 28 | ScreenOrientation | String | ✓ | ✓ | ✓ | y | device |
| 35 | CanvasHash | Bytes | ✓ | ✓ | ✓ | y | device |
| 36 | WebGLVendor | String | ✓ | – | ✓ | y | device |
| 37 | WebGLRenderer | String | ✓ | – | ✓ | y | device |
| 38 | WebGLVersion | String | ✓ | – | ✓ | y | device |
| 40 | WebGLExtensions | StringArray | ✓ | – | ✓ | y | device |
| 41 | WebGLParameters | String | ✓ | – | ✓ | y | device |
| 43 | AudioHash | Bytes | ✓ | ✓ | ✓ | y | device |
| 44 | FontsHash | Bytes | ✓ | ✓ | ✓ | y | device |
| 47 | LocalStorage | Boolean | ✓ | ✓ | ✓ | y | stable |
| 48 | SessionStorage | Boolean | ✓ | ✓ | ✓ | y | stable |
| 49 | IndexedDB | Boolean | ✓ | ✓ | ✓ | y | stable |
| 50 | CacheStorage | Boolean | ✓ | ✓ | ✓ | y | stable |
| 51 | CookiesEnabled | Boolean | ✓ | ✓ | ✓ | y | stable |
| 52 | NotificationPermission | String | ✓ | ✓ | ✓ | y* | condition |
| 53 | GeolocationPermission | String | ✓ | ✓ | ✓ | y* | condition |
| 54 | CameraPermission | String | ✓ | ✓ | ✓ | y* | condition |
| 55 | MicrophonePermission | String | ✓ | ✓ | ✓ | y* | condition |
| 59 | SupportedCodecs | StringArray | ✓ | ✓ | ✓ | y | env |
| 60 | MediaFormats | StringArray | ✓ | ✓ | ✓ | y | env |
| 61 | AudioFormats | StringArray | ✓ | ✓ | ✓ | y | env |
| 67 | Locale | String | ✓ | ✓ | ✓ | y | stable |
| 68 | Timezone | String | ✓ | ✓ | ✓ | y | stable |
| 69 | TimezoneOffset | Integer | ✓ | ✓ | ✓ | y | stable |
| 70 | DateTimeFormat | String | ✓ | ✓ | ✓ | y | stable |
| 71 | BatteryLevel | Float | ✓ | – | – | y* | condition |
| 72 | BatteryCharging | Boolean | ✓ | – | – | y* | condition |
| 73 | BatteryChargingTime | Integer | ✓ | – | – | y* | condition |
| 76 | HDRSupport | Boolean | ✓ | ✓ | ✓ | y | env |
| 77 | CryptoSupport | Boolean | ✓ | ✓ | ✓ | y | stable |
| 78 | SubtleCrypto | Boolean | ✓ | ✓ | ✓ | y | stable |
| 79 | SpeechSynthesisVoices | StringArray | – | – | ✓ | y | env |
| 86 | CSSCustomProperties | Boolean | ✓ | ✓ | ✓ | y | stable |
| 87 | CSSGridSupport | Boolean | ✓ | ✓ | ✓ | y | stable |
| 88 | CSSFlexboxSupport | Boolean | ✓ | ✓ | ✓ | y | stable |
| 89 | CSSContainerQuery | Boolean | ✓ | ✓ | ✓ | y | stable |
| 90 | CSSHasSelector | Boolean | ✓ | ✓ | ✓ | y | stable |
| 91 | ServiceWorkerSupport | Boolean | ✓ | ✓ | ✓ | y | stable |
| 92 | WebWorkerSupport | Boolean | ✓ | ✓ | ✓ | y | stable |
| 93 | SharedWorkerSupport | Boolean | ✓ | ✓ | ✓ | y | stable |
| 94 | WebSocketSupport | Boolean | ✓ | ✓ | ✓ | y | stable |
| 95 | WebRTCSupport | Boolean | ✓ | ✓ | ✓ | y | stable |
| 96 | KeyboardLayout | String | ✓ | ✓ | ✓ | y | env |
| 97 | PointerEvents | Boolean | ✓ | ✓ | ✓ | y | stable |
| 98 | GamepadSupport | Boolean | ✓ | ✓ | ✓ | y | stable |

72 distinct signals are observed across the three engines. The remaining
`FeatureID` values (e.g. 29–34, 39, 42, 45, 46, 56–58, 62–66, 74, 75, 80–85,
99–101) are **not collected** by the current SDK and therefore cannot
contribute to a digest. The connection family (62–66) is additionally hidden by
Brave shields (see `browser-matrix-design.md`).

## Cross-environment differences (expected, not defects)

`diff-snapshots.mjs` against the committed CI golden reports **38 differing
signals** when the CI golden is compared to a local macOS capture
(chromium 13, firefox 13, webkit 12). Every difference is explained by
environment, never by run-to-run noise:

| Signal | Why it differs across environments |
|--------|------------------------------------|
| UserAgent, AppVersion, Platform, KeyboardLayout | OS/UA string (`Linux x86_64` vs `MacIntel`) |
| HardwareConcurrency, DeviceMemory/DeviceRam | Physical host cores/RAM (`4` vs `10`) |
| CanvasHash, AudioHash, FontsHash | GPU / font set / audio renderer |
| WebGLVendor, WebGLRenderer, WebGLParameters, WebGLExtensions | GPU driver (`SwiftShader` vs `Apple M5`) |
| SupportedCodecs, MediaFormats, HDRSupport | Platform media stack |
| SpeechSynthesisVoices | Installed TTS voices |

This is exactly the boundary the digest pin is meant to freeze: a **new
environment is a pin-reset event** (re-capture), never a silent change. Within
one environment, all 72 signals are stable.

## Findings

1. **No run-to-run non-determinism was observed** in any engine: CI 3×3
   (authoritative) and local Brave 10×10 both reported zero volatile signals.
   The strict digest gate (W3-D3) passes — the canonicalized feature buffer is
   stable.
2. **All cross-capture drift is environmental.** The 38 differences are the
   OS/UA/GPU/font/codec/voice axes; none are clock-, entropy-, or
   allocation-order-derived.
3. **The at-risk set is small and already isolated.** Only three families can
   change *within* a fixed device over time, and all are marked `y*`
   (condition-dependent): permissions (52–55), battery (71–73), and the
   Brave-hidden connection family (62–66).
4. **Entropy signals are stable-per-device, not noisy.** Canvas (35), Audio
   (43), Fonts (44) and WebGL (36–41) are intentionally high-entropy *device*
   fingerprints. `audio.ts` renders through `OfflineAudioContext` with no
   wall-clock dependency (BUG-010 fix); canvas/fonts/WebGL depend only on the
   GPU/font set, which is fixed per environment.

## Input to W3-D5 (stable-core subset) — resolved

The stable-core digest (`core_digest`, D-v1-5/D-v1-7) selects signals that are
**stable across repeated sessions on one device** and are **device/host
anchors**, while excluding entropy-optional noise and the `condition` class
(which genuinely changes). This draft input was **finalized in W3-D5**; the
authoritative contract is `signal-determinism-contract.md`.

- **Core (locked, 26 features)**: durable device/host anchors — Canvas/Audio/
  Fonts/WebGL/GPU (35, 37, 39, 43, 44, 80–82), CPU/RAM (11, 13, 16, 30–32),
  MaxTouchPoints (12), Platform (3), Locale profile (1, 2), Timezone (68),
  physical display (21–23), codec surface (59–61), voices (79).
- **Excluded — `condition`** (52–55, 62–66, 71–73): must not feed a drift digest.
- **Excluded — geometry** (17–20, 24–28): flip on resize/fullscreen.
- **Excluded — update-drift** (0, 8, 45, 46, capability booleans 86–95): a
  browser update flips them without the device changing.

The matrix's earlier draft leaned toward the `stable` capability class as
"strong candidates"; D5 **reverses that emphasis** — the core is the device
anchor set, and capability booleans drop out as update-drift. See
`signal-determinism-contract.md` §"Reconciliation".

## Reproduction

```sh
# Build the SDK dist (needs the local tsc on PATH: src/clients/browser/node_modules/.bin)
PATH="$PWD/src/clients/browser/node_modules/.bin:$PATH" zig build clients:browser

# Local N-repeat determinism sweep (Brave; firefox/webkit need `npx playwright install`)
node tests/browser-matrix/collect.mjs --engines=chromium --repeats=10

# Per-signal diff: local capture vs committed CI golden
node tests/browser-matrix/diff-snapshots.mjs

# Authoritative CI capture (3x3): Actions → Golden Capture (see browser-matrix-design.md)
```

## Notes

- Local Brave reported `1.97.57` while `pins.json` pins `1.97.56` (CI). Local
  runs are informational; the CI capture installs the sha256-pinned `1.97.56`.
  A Brave version bump is a pin-reset event (`browser-matrix-design.md`).
- The matrix is derived from committed golden fixtures + the CI `collect.log`;
  regenerate the table with the golden snapshots whenever the signal set or
  engine versions change.
