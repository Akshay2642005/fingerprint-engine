# Phase 5 — Hashing

> Builds on Phases 1-4 to produce cryptographic digests of features and fingerprints using SHA-256.

## Scope

### In Scope

1. **Feature hashing** — Hash any FeatureValue to a 32-byte SHA-256 digest
2. **Fingerprint digest** — Hash all features (sorted by FeatureID) into a single fingerprint digest
3. **Incremental hasher** — Stateful hasher that absorbs features one at atime, yields final digest
4. **Wire module** into `core/root.zig` + tests
5. **Preflight** — `zig build test` must pass green

### Out of Scope

- Validation (Phase 6)
- Similarity/Entropy/Scoring (Phases 7–9)
- Browser/Server SDK (Phases 10–11)

## Design Decisions

### Decision 1: Deterministic Hashing

All hashing must be deterministic (same input → same digest) regardless of platform, architecture, or Zig compiler version. SHA-256 provides this guarantee.

### Decision 2: Feature Order Determinism

When hashing an entire fingerprint, features are sorted by FeatureID before hashing. This ensures the same fingerprint always produces the same digest regardless of insertion order.

### Decision 3: Zero-Allocation API

All hashing functions accept an output buffer `*[32]u8` to write the digest into. No heap allocation in the hashing path.

### Decision 4: SHA-256 from std.crypto

Use `std.crypto.hash.sha2.Sha256` from the Zig standard library — no external dependencies, audited implementation.

## Module Structure

```
src/core/hashing/
├── root.zig      — Public exports
├── feature.zig   — Per-feature hashing
├── fingerprint.zig — Fingerprint digest
└── hasher.zig    — Incremental hasher

tests/hashing/
├── feature_test.zig
├── fingerprint_test.zig
├── hasher_test.zig
└── root.zig
```
