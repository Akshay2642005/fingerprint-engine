# Phase 2 — Runtime Model

> Builds on Phase 1 (Features module) to create the runtime fingerprint object model.

## Scope

### In Scope

1. **FeatureValue** — A tagged union type that can hold any feature value variant (Boolean, Integer, Float, String, Bytes, StringArray, IntegerArray, FloatArray, BytesArray) matching the existing `FeatureType` enum
2. **FeatureCollection** — An ordered, fixed-capacity container of feature values indexed by `FeatureID`, designed for zero-allocation collection on the browser side and deserialization on the server side
3. **FingerprintMetadata fix** — Ensure metadata is a complete, stable type with schema version, SDK version, and collection timestamp
4. **Feature struct fix** — Repair `feature.zig` to import from the correct paths (`model.zig`, not `id.zig`)
5. **Fingerprint struct fix** — Wire metadata + feature collection as the runtime object
6. **Wire fingerprint module** into `src/core/root.zig` so consumers can import `core.fingerprint`
7. **Test suite** — Unit tests for FeatureValue, FeatureCollection, Fingerprint, and FingerprintMetadata
8. **Preflight** — `zig build test` must pass green

### Out of Scope

- Serialization (Phase 3)
- Normalization (Phase 4)
- Hashing (Phase 5)
- Validation (Phase 6)
- Similarity/Entropy/Scoring (Phases 7–9)
- Browser SDK collectors (Phase 10)
- Server SDK wrappers (Phase 11)

## Design Decisions

### Decision 1: FeatureValue as Tagged Union

`FeatureValue` is a Zig tagged union indexed by `FeatureType`. This gives us:

- **Compile-time type safety** — each variant's payload matches its discriminator
- **No heap allocation** — all value types are fixed-size; arrays use slices pointing to external memory
- **Deterministic** — same input serialization every time
- **FeatureType alignment** — every FeatureDefinition already declares `.value_type`

```zig
pub const FeatureValue = union(FeatureType) {
    boolean: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    bytes: []const u8,
    string_array: []const []const u8,
    integer_array: []const i64,
    float_array: []const f64,
    bytes_array: []const []const u8,

    pub fn valueType(self: FeatureValue) FeatureType {
        return @as(FeatureType, self);
    }
};
```

### Decision 2: FeatureCollection as Slice

`FeatureCollection` is a `[]const Feature` slice — the simplest possible container that allows consumers to allocate how they wish. The browser SDK will collect into a fixed-size buffer (stack-allocated), while the server deserializer can use an arena.

```zig
pub const FeatureCollection = []const Feature;
```

### Decision 3: Fingerprint as Top-Level Runtime Object

`Fingerprint` bundles metadata + feature collection. It's the object that all downstream phases (serialization, normalization, hashing, validation, similarity, entropy, scoring) consume.

### Decision 4: Typedef for FeatureID instead of Broken Import

The dead import `../features/id.zig` is replaced by importing from `model.zig` where `FeatureID` already lives. The hypothetical `value.zig` becomes the new `FeatureValue` type.

## Implementation Plan

### Story 1 — Fix Feature struct dead imports

**File:** `src/core/fingerprint/feature.zig`

Replace broken imports with correct ones:

```
../features/id.zig  →  ../features/model.zig (FeatureID lives in model.zig)
value.zig           →  ./. (FeatureValue defined in same file or sibling)
```

The `Feature` struct stays as:

```zig
pub const Feature = struct {
    id: FeatureID,
    value: FeatureValue,
};
```

**Tests:** Verify Feature compiles and holds correct types.

---

### Story 2 — Implement FeatureValue tagged union

**New file:** `src/core/fingerprint/value.zig`

Define `FeatureValue` as a `union(FeatureType)` with all 9 variants matching `FeatureType` enum. Include:

- `valueType()` accessor
- Equality check for testing
- Format/display helper (optional, for debugging)

**Tests:**

- Each variant round-trips its type tag
- Boolean gets boolean, string gets string, etc.
- Equality check works
- Size is reasonable (no worse than largest variant + tag)

---

### Story 3 — Implement FingerprintMetadata completion

**File:** `src/core/fingerprint/metadata.zig`

Verify the existing metadata struct is complete:

```zig
pub const FingerprintMetadata = struct {
    schema_version: u16,
    sdk_version: []const u8,
    collection_timestamp: i64,
};
```

Add validation helpers if needed (e.g., `isValid()` that checks schema version is non-zero).

**Tests:**

- Metadata fields are correct types
- Struct size is stable (ABI)
- Default/zero values work

---

### Story 4 — Rebuild Fingerprint struct

**File:** `src/core/fingerprint/fingerprint.zig`

Update to use the corrected imports:

```zig
pub const Fingerprint = struct {
    metadata: FingerprintMetadata,
    features: []const Feature,
};
```

This is likely already correct structurally — just needs the fixed imports to compile.

---

### Story 5 — Create fingerprint root and wire into core root

**File:** `src/core/fingerprint/root.zig`

Export all public types:

```zig
pub const Feature = @import("feature.zig").Feature;
pub const FeatureValue = @import("value.zig").FeatureValue;
pub const Fingerprint = @import("fingerprint.zig").Fingerprint;
pub const FingerprintMetadata = @import("metadata.zig").FingerprintMetadata;
pub const FeatureCollection = []const Feature;
```

**File:** `src/core/root.zig`

Add fingerprint export alongside features:

```zig
pub const features = @import("features/root.zig");
pub const fingerprint = @import("fingerprint/root.zig");
```

---

### Story 6 — Add fingerprint tests

**New files:**

- `tests/fingerprint/feature_test.zig`
- `tests/fingerprint/value_test.zig`
- `tests/fingerprint/metadata_test.zig`
- `tests/fingerprint/fingerprint_test.zig`
- `tests/fingerprint/root.zig`

**Test coverage:**

- FeatureValue: each variant, type tag, equality
- Feature: construction, field access
- FingerprintMetadata: valid/invalid states, field access
- Fingerprint: full construction with metadata + features
- Public API: import through `root.zig` only

**New build step:** Wire `tests/fingerprint/root.zig` into `build.zig` so `zig build test` includes fingerprint tests.

---

### Story 7 — Preflight: verify `zig build test` passes

Run the full test suite and confirm green. Any discovered defects go through fix-or-log per CONVENTIONS.md.

## File Changes Summary

| File | Action |
| ------ | -------- |
| `src/core/fingerprint/feature.zig` | Edit — fix imports |
| `src/core/fingerprint/value.zig` | **Create** — FeatureValue tagged union |
| `src/core/fingerprint/fingerprint.zig` | Edit — fix imports if needed |
| `src/core/fingerprint/metadata.zig` | Review — add helpers if needed |
| `src/core/fingerprint/root.zig` | Edit — add FeatureValue/FeatureCollection exports |
| `src/core/root.zig` | Edit — add fingerprint module |
| `tests/fingerprint/feature_test.zig` | **Create** |
| `tests/fingerprint/value_test.zig` | **Create** |
| `tests/fingerprint/metadata_test.zig` | **Create** |
| `tests/fingerprint/fingerprint_test.zig` | **Create** |
| `tests/fingerprint/root.zig` | **Create** |
| `build.zig` | Edit — add fingerprint test target |

## Success Criteria

1. `zig build test` passes with all tests green
2. `FeatureValue` correctly holds and returns all 9 variant types
3. `Feature` struct compiles with no broken imports
4. `Fingerprint` struct bundles metadata + features correctly
5. Core root exports `fingerprint` namespace
6. Tests cover public API only (through `root.zig`)
7. Zero runtime allocation in value creation
8. No dead imports in the fingerprint module

## Key Constraints

- Zig 0.16.0 only (std library, no external deps)
- No heap allocation in value construction
- FeatureType tag on union must match FeatureType enum values 1:1
- FeatureID must still come from `model.zig` (not duplicated)
- All tests go in `tests/` not `src/`
- Public API through `root.zig` only
