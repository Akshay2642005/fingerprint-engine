<!-- story: m6-signal-contract -->
# Signal determinism contract (W3-D5)

Story: `m6-signal-contract` (SCRUM-44). This is the W3-D5 deliverable: it
**finalizes the triage** from `signal-determinism-matrix.md` into a written
contract — a precise statement of which collected signals are guaranteed
stable, which are condition-dependent, and exactly which features form the
**stable-core subset** hashed into `stable_core_digest` (D-v1-5 / D-v1-7).

Authority for the wire format remains DESIGN §9 / ADR-012; the two-digest
`fingerprint_result` layout is `specs/internal/05-two-digest-result-layout.md`
and the per-collection envelope is `decisions/0013-event-envelope-ledger-adr.md`.

Status: **complete** — contract documented; stable-core subset locked in the
registry (`core` flag, `core_version = 1`); CI green.

## Purpose

Two identical sessions on one device must produce the same digests; a *changed
device* must be distinguishable from *noise*. The matrix proved there is **no
run-to-run non-determinism** in any engine. The remaining question is which
signals may legitimately change over the life of one device, and which must
never feed a drift digest. This contract answers that.

It governs one artifact: the **stable-core digest** (`core_digest` /
`stable_core_digest`), computed over the `.core` feature subset only. It does
**not** change the existing full fingerprint digest, which continues to hash
every non-metadata feature exactly as before.

## The contract

| Tier | Membership | May change over the device's life? | In `core_digest`? |
|------|-----------|------------------------------------|-------------------|
| **Core — guaranteed durable** | the 26 features below | No (only when the device/host genuinely changes) | **Yes** |
| **Condition-dependent** (`y*`) | permissions 52–55, connection 62–66, battery 71–73, `TimePrecision` 85 | Yes — network, power, permission state | No |
| **Geometry** | 17–20, 24–28 (window/screen/viewport) | Yes — window resize, fullscreen, multi-monitor | No |
| **Update-drift** | UA surface (0, 8, 45, 46), capability booleans (86–95) | Yes — browser update | No |
| **Metadata** | 99–101 | Per collection | No (never hashed) |

The guarantee is deliberately **one-directional**: every `.core` feature is
guaranteed durable; *not* every durable feature is core (the set is kept tight
by the selection rule). A missing core feature on a given engine lowers the
gate's confidence and falls through to similarity — it does not defect the
digest.

## Stable-core subset (locked)

26 features, in registry order. `core_version = 1`.

| ID | Feature | Matrix class | Why it is core |
|----|---------|--------------|----------------|
| 1 | Language | stable | locale profile |
| 2 | Languages | stable | locale profile |
| 3 | Platform | env | OS family (not `AppVersion` — update-drift) |
| 11 | HardwareConcurrency | device | logical CPU core count |
| 12 | MaxTouchPoints | device | hardware capability |
| 13 | DeviceMemory | device | RAM tier |
| 16 | DeviceRam | device | RAM tier |
| 21 | ColorDepth | device | physical display, survives resize |
| 22 | PixelDepth | device | physical display, survives resize |
| 23 | DevicePixelRatio | device | physical display, survives resize |
| 30 | CpuCores | device | CPU profile |
| 31 | CpuArchitecture | device | CPU profile |
| 32 | PlatformArchitecture | device | CPU profile |
| 35 | CanvasHash | device | hardware rendering unit — the classic anchor |
| 37 | WebGLRenderer | device | GPU anchor |
| 39 | WebGLHash | device | GPU render digest |
| 43 | AudioHash | device | renderer/OS-dependent |
| 44 | FontsHash | device | OS installed-font profile |
| 59 | SupportedCodecs | env | codec capability surface |
| 60 | MediaFormats | env | codec capability surface |
| 61 | AudioFormats | env | codec capability surface |
| 68 | Timezone | stable | geo-class anchor |
| 79 | SpeechSynthesisVoices | env | OS voice set |
| 80 | GPUVendor | device | GPU anchor |
| 81 | GPURenderer | device | GPU anchor |
| 82 | GPUDriverVersion | device | GPU anchor |

Several of these (30–32, 39, 80–82) are registry-defined but **not yet
collected** by the current SDK; they are core so that when collection lands
they contribute without a subset change. On today's SDK the core digest is
computed over whichever of the 26 are present.

### Selection rule

A feature is core **iff** it is:

1. **durable** across normal browser use — including **browser-window
   resizing** — and
2. **hardware/host-determined**, not state-determined.

Breadth beats precision: missing core features lower confidence and fall to
similarity, so the set is kept tight. Cross-engine *presence* differences do
**not** disqualify a feature — presence is tolerated by design.

### Exclusion rules

- **Viewport/window geometry** (17–20, 24–28): flip on resize/fullscreen — the
  motivating case. `ScreenOrientation` (28) flips on device rotation.
- **Transient state** (52–55, 62–66, 71–73, 85): battery drains, network
  reconnects, permissions are granted — genuine state, not run-to-run noise
  (they are `y*`, not defects), but never a device anchor.
- **Update-drift UA surface** (0, 8, 45, 46) and **capability booleans**
  (86–95): a browser update flips them without the device changing.
- **Metadata** (99–101): never hashed into any digest.
- **Derived duplicates**: `TimezoneOffset` (69) is DST-dependent and derived
  from `Timezone`; `DateTimeFormat` (70) is locale-derived; `KeyboardLayout`
  (96) is derived from `Language` + `Platform`. All are excluded as redundant.

## Freeze policy

`core_version` is the **registry revision of the subset**. A `core_digest` is
only comparable against another stamped with the same `core_version` — a subset
change would otherwise masquerade as device drift.

- The subset lives in `src/model/definitions.zig` as the `core_subset` array,
  and `core_version` sits beside it.
- A comptime **lock guard** fails the build if the `.core` flags and
  `core_subset` disagree (in either direction), if any core feature is
  `sensitive`, or if a metadata feature is core. Changing the set therefore
  **cannot** compile without touching `core_subset`, which forces the
  `core_version` bump.
- `core_version` is **not** the full-digest `schema_version` and **not** the
  `stable_required` validation flag. It is the stable-core subset revision only.

## Enforcement in code

| Surface | Location |
|---------|----------|
| Flag bit + named combos | `FeatureFlags.core`, `.{stable_required,stable_entropy,critical}_core` — `src/model/feature.zig` |
| Predicate | `FeatureDefinition.isCore()` — `src/model/feature.zig` |
| Locked subset + `core_version` + guard | `src/model/definitions.zig` |
| Registry accessors | `Registry.isCore/coreSubset/coreCount/core_version` — `src/model/registry.zig` |
| Regression tests | `tests/model/registry_test.zig` (subset ⟷ flag agreement, exclusions, anchors) and `tests/model/definitions_test.zig` (per-feature flags) |

The two-digest *layout* and the `core_digest` **computation** are M7 / Week-5
work (`specs/internal/05-two-digest-result-layout.md`); this contract fixes the
membership they will hash. The window-resize property test from `05` becomes the
standing regression guard once the digest op exists; until then the membership
tests above hold the line at the definition level.

## Reconciliation with the matrix's draft input

`signal-determinism-matrix.md` §"Input to W3-D5" drafted the `stable` capability
class (86–95, 47–51, 77–78, 4–7, …) as the "strong candidates" and treated
device anchors as "heavier, decide later". **D5 reverses that emphasis**: the
core is the *device anchor* set, and the capability booleans are excluded as
update-drift.

Rationale: `core_digest` answers "did this device's stable identity change?".
Its value comes from high-entropy, device-discriminating anchors — a changed
canvas/WebGL/font/GPU/CPU/RAM profile is a meaningful event. Capability
booleans carry little device discrimination and flip on browser update, which is
exactly the drift the core must tolerate. This matches the concrete schema in
`specs/internal/07-stable-core-subset.md` and `03-stable-core-two-digest.md`.

## Residual risks / watch items

- **Codec + voice surface (59–61, 79)** is OS/browser-dependent and *can* widen
  on update. The matrix shows no within-run instability; if update-drift is
  observed in the field, narrow the subset and bump `core_version` (a
  deliberate, versioned event — never a silent change).
- **GPU/driver strings (37, 80–82)** drift on a GPU driver update. Accepted: a
  driver change is a legitimate render-stack change.
- The **connection family (62–66)** is additionally hidden by Brave shields; it
  is excluded from core regardless.
- Local Brave is `1.97.57` vs the pinned `1.97.56`; local runs are
  informational. A Brave/Playwright bump is a pin-reset event
  (`browser-matrix-design.md`).

## Reproduction

```sh
# Contract + subset tests
zig build test --summary all

# Prove the lock guard fires (temporarily drop one entry from core_subset)
#   -> "core guard: 26 features flagged .core but core_subset has 25 entries"
```

## Notes

- Matrix source: `specs/quality/signal-determinism-matrix.md` (W3-D4,
  `m6-signal-triage`).
- Two-digest design: `specs/internal/05-two-digest-result-layout.md`,
  `specs/internal/03-stable-core-two-digest.md`.
- Subset schema: `specs/internal/07-stable-core-subset.md`.
- Envelope contract that will carry `core_digest` / `core_version`:
  `specs/decisions/0013-event-envelope-ledger-adr.md`.
