# ADR-004 — FPKG envelope + SignalPackage v2 + integrity

- **Status:** Adopted (2026-08-07)
- **Rework decision:** D4

## Context

Pre-rework serialization was raw TLV/JSON: `encode` dropped `sdk_version` and
`collected_at`, `decode` fabricated empty metadata, and there was no message
type, no envelope version, no integrity, no replay identity.

## Decision

- **Extend, don't replace:** the feature TLV remains the signal package body;
  it gains a framed envelope ("FPKG") with version, message type, codec,
  payload length, and integrity digest.
- `schema_version` bumps 1 → 2. v1 bodies stay decodable via a compatibility
  path; old fixtures become compatibility goldens.
- The v2 body carries full metadata: `package_id` ([16]u8 replay identity),
  `sdk_version`, `collected_at`.
- Wire layout (implemented in `src/serialization/binary.zig` and mirrored
  byte-for-byte by the TS SDK's `package.ts`, cross-checked by a golden parity
  test).
- Message types (FPKG, `src/io/frame.zig`): signal_package=1 … entropy_result=9.

## Consequences

- Lossless, replayable round-trips.
- Unknown envelope/body versions produce explicit `unsupported_version`
  errors instead of silent corruption.
- The browser SDK's serializer can never drift from the Zig codec: both sides
  are pinned to the same golden fixture (`signal-package-v2.bin`, digest
  `db29fc13…e6c75`, features=3, schema=2 — compile-time constant in
  `src/integration_tests.zig`; never regenerate).
