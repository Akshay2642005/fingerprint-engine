# Phase 4 — Normalization

> Builds on Phases 2 (Runtime Model) and 3 (Serialization) to validate and normalize fingerprint feature values.

## Scope

### In Scope

1. **Type validation** — Verify each FeatureValue's type matches its FeatureDefinition's declared `value_type`
2. **Value bounds validation** — Check integer/float values against expected ranges; trim strings; validate array membership
3. **Fingerprint normalization** — Run all validation/normalization passes on a full Fingerprint, producing a NormalizedFingerprint with warnings for any anomalies
4. **Wire normalization module** into `core/root.zig`
5. **Test suite** — Type mismatches, out-of-bounds values, edge cases
6. **Preflight** — `zig build test` must pass green

### Out of Scope

- Hashing (Phase 5)
- Validation (Phase 6) — structural/completeness checks
- Similarity/Entropy/Scoring (Phases 7–9)
- Browser SDK collectors (Phase 10)
- Server SDK wrappers (Phase 11)

## Design Decisions

### Decision 1: NormalizationResult as Tagged Union Per Feature

Each feature normalizes to a result that carries either the normalized value or a warning:

```zig
pub const NormalizedValue = struct {
    feature: Feature,
    warnings: []const NormalizationWarning,
};
```

Warnings are non-fatal — normalization produces a best-effort result even when issues are found.

### Decision 2: Validation-First, In-Place Not Required

Since core algorithms avoid heap allocation, normalization produces warnings without modifying the original data. The caller decides whether to act on warnings. The normalized fingerprint is the original with a warnings list attached.

### Decision 3: Bounds Are Per-Feature Constants

Validation bounds are defined as constants in the normalization module, not in FeatureDefinition, because:

- Bounds are implementation details, not metadata
- They may vary by platform or SDK version
- They don't need to be serialized

## Module Structure

```
src/core/normalization/
├── root.zig       — Public exports, top-level normalize()
├── types.zig      — Type validation
├── bounds.zig     — Value bounds checking
└── normalize.zig  — Full fingerprint normalization

tests/normalization/
├── types_test.zig
├── bounds_test.zig
├── normalize_test.zig
└── root.zig       — Test aggregator
```

## Implementation Plan

### Story 1 — Type validation

**New file:** `src/core/normalization/types.zig`

Implement `validateType(feature: Feature) bool` and `validateTypes(fingerprint: Fingerprint) []const TypeWarning` that checks every feature's value type matches its definition.

- Uses `Registry.get(feature.id).value_type`
- Returns a list of mismatches (or empty if all match)
- Zero allocation: return a comptime-known slice or use a fixed-size buffer

### Story 2 — Value bounds validation

**New file:** `src/core/normalization/bounds.zig`

Implement `checkBounds(feature: Feature) ?BoundWarning` and `checkAllBounds(fingerprint: Fingerprint) []const BoundWarning`

Per-feature checks:

- Integer: range validation (e.g., HardwareConcurrency: 1..256, ScreenWidth: 1..65536)
- Float: finite check, precision rounding
- String: empty check, max length
- Bytes: empty check, max length
- Arrays: empty check, max element count

### Story 3 — Fingerprint normalization

**New file:** `src/core/normalization/normalize.zig`

Implement `normalize(fingerprint: Fingerprint, allocator: Allocator) NormalizedFingerprint`

Runs all validation passes and returns:

- The original fingerprint (immutable)
- A list of all warnings (type + bounds)

### Story 4 — Wire module + tests

Export through `core.root`, add test target, verify all tests pass.

## Success Criteria

1. `zig build test` passes with all tests green
2. Type validation catches all 9 FeatureType mismatches
3. Bounds validation catches out-of-range integers and floats
4. Normalized fingerprint preserves original data
5. No heap allocation in validation-only paths
