# Tech Stack — Fingerprint Engine

## Language & Runtime

- **Language:** Zig 0.16.0
- **Minimum Zig version:** 0.16.0
- **Dependencies:** None (standard library only)
- **Package manager:** Zig build system (built-in)

## Source Inventory

- **11 source files**, 346 total lines, 8,605 bytes
- All files are under the 300-line cap (largest: `model.zig` at 120 lines)
- **Zero tests** exist yet (`tests/` directory is empty scaffolding)
- **Zero docs** materialized (`docs/` is empty scaffolding)
- **Zero examples** (`examples/` is empty scaffolding)
- **Zero benchmarks** (`benchmarks/` is empty scaffolding)

## Architecture

```
                 Zig Core Engine
                        │
        ┌───────────────┴────────────────┐
        │                                │
 Browser SDK (WASM)              Server Library
        │                                │
 Signal Collection          Fingerprint Processing
 Normalization              Matching
 Validation                 Similarity
 Serialization              Fraud Detection
 Hashing                    Device Linking
                             Risk Scoring
```

### Implemented Modules (src/)

| Module | Path | Lines | Status |
| -------- | ------ | ------- | -------- |
| **Features** | `src/core/features/` | 295 | ✅ Implemented |
| **Fingerprint** | `src/core/fingerprint/` | 29 | ⚠️ Scaffold only |
| **Browser SDK** | `src/browser/wasm/` | 8 | ⚠️ Stub (add fn) |
| **Server SDK** | `src/server/native/` | 10 | ⚠️ Stub (hello fn) |

#### Features Module (`src/core/features/`)

| File | Lines | Purpose |
| ------ | ------- | --------- |
| `model.zig` | 120 | Types: `FeatureCategory`, `FeatureType`, `FeatureWeight`, `FeatureFlags`, `FeatureID` (37 IDs), `FeatureDefinition` |
| `definitions.zig` | 114 | 11 concrete feature definitions (UserAgent, Canvas, WebGL, etc.) |
| `registry.zig` | 49 | Compile-time O(1) lookup table with duplicate/missing detection |
| `root.zig` | 12 | Public re-exports |

**Key patterns:**

- Compile-time array lookup (no HashMap, no runtime initialization)
- `@compileError` for duplicate and missing definitions
- `packed struct(u8)` for bitfield flags
- `inline for` for enum validation
- Comptime assertions on struct sizes (`@sizeOf`)

#### Fingerprint Module (`src/core/fingerprint/`)

| File | Lines | Purpose |
| ------ | ------- | --------- |
| `feature.zig` | 8 | `Feature` struct (id + value) |
| `fingerprint.zig` | 12 | `Fingerprint` struct (metadata + features slice) |
| `metadata.zig` | 6 | `FingerprintMetadata` (schema ver, sdk ver, timestamp) |
| `root.zig` | 3 | Re-exports |

**⚠️ Dead imports:** `feature.zig` imports `../features/id.zig` (doesn't exist — `FeatureID` is in `model.zig`) and `value.zig` (doesn't exist at all). These files won't compile standalone — they depend on planned but unimplemented modules.

#### Browser SDK (`src/browser/wasm/root.zig`)

```zig
pub export fn add(a: i32, b: i32) i32 { ... }
```

Placeholder WASM export. No fingerprint collection logic.

#### Server SDK (`src/server/native/root.zig`)

```zig
pub export fn hello() void { ... }
```

Placeholder native export. No fingerprint processing logic.

### Planned Modules

- `src/core/normalization/` — String/number normalization, canonical representation
- `src/core/hashing/` — SHA-256, incremental hashing, fingerprint digest
- `src/core/validation/` — Required features, value/schema/compatibility validation
- `src/core/similarity/` — Feature comparison, weighted similarity, distance metrics
- `src/core/entropy/` — Per-feature and overall entropy, statistical uniqueness
- `src/core/scoring/` — Spoof detection, anomaly detection, risk scoring

### Import Graph (Current)

```
browser/wasm/root.zig  ──────── core
server/native/root.zig ──────── core
core/features/model.zig ─────── std
core/features/definitions.zig ─ model.zig
core/features/registry.zig ──── std, model.zig, definitions.zig
core/features/root.zig ──────── model.zig, registry.zig
core/fingerprint/feature.zig ── ../features/id.zig ⚠️(dead), value.zig ⚠️(dead)
core/fingerprint/fingerprint.zig ─ feature.zig, metadata.zig
core/fingerprint/root.zig ───── features/root.zig, fingerprint/root.zig
```

**Dangling references:** `feature.zig` imports `FeatureID` from a non-existent `id.zig` (should be `model.zig`) and `FeatureValue` from a non-existent `value.zig` (not yet implemented).

## Design Principles (Observed)

- **Compile-time first** — Lookup tables, validation, and ABI enforcement at comptime
- **Zero runtime allocation** — Core algorithms avoid heap allocation
- **Deterministic** — Same input → same output across all platforms
- **Data-driven** — Algorithms consume metadata, not hardcoded switch statements
- **Stable ABI** — Explicit integer sizes (u8, u16, packed structs)
- **No circular dependencies** — Currently holds (feature.zig dead imports excluded)
- **Public facade** — Every module exports through `root.zig`

## Build Targets

| Command | Output |
| --------- | -------- |
| `zig build` | All artifacts |
| `zig build wasm` | WebAssembly module (`fingerprint.wasm`) |
| `zig build native` | Static library (`libfingerprint.a`) |
| `zig build test` | Core test suite |

## Testing

- Tests live outside `src/` in `tests/` — but `tests/` is **empty scaffolding**
- No embedded tests in production code
- No tests exist yet
- Future: fuzz tests, golden datasets, regression benchmarks

## Signals & Active Considerations

### Greenfield gaps

1. **`FeatureValue` type is undefined** — referenced by `feature.zig` but no `value.zig` exists. Needs an enum/union for all `FeatureType` variants (String, Integer, Float, Bytes, arrays).
2. **Dead imports in `feature.zig`** — `FeatureID` is in `model.zig`, not `id.zig`. Fix required.
3. **No tests** — Foundation layer (features module) has zero test coverage despite having the most complex logic (comptime validation, lookup table).
4. **No serialization** — No binary or JSON format for fingerprint data.
5. **No hashing** — Canvas and WebGL feature types reference hashes but no hashing module exists.
6. **Stub-only platform targets** — Browser and server modules are placeholders with no real integration.

### Consistency

- ✅ All files under 300-line cap
- ✅ Public facade pattern (`root.zig`) used consistently
- ✅ Module structure reflects the documented architecture
- ✅ Compile-time validation used throughout features module
- ❌ Fingerprint module contains dangling imports — needs cleanup

### Dependency graph health

- Features module is self-contained ✅
- Fingerprint module depends on features and std ✅
- Browser and server depend on core only ✅
- Planned modules (hashing, validation, etc.) will depend on fingerprint + features
