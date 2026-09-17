<!-- // story: m6-wire-versioning -->

# ADR-012 — Versioning and compatibility contract (wire ABI + SDK)

- **Status:** Adopted (2026-09-17)
- **Source:** `src/io/frame.zig`, `src/serialization/binary.zig`, `src/serialization/codec.zig`, `src/cmd/ingress/http.zig`, ADR-004
- **Extends:** ADR-004 (FPKG envelope + SignalPackage v2 + integrity). Does not supersede it.

## Context

v1.0.0 freezes the wire ABI: the FPKG envelope, the `CodecID` enum, and the
SignalPackage body are contracts between the browser SDK, the ingress, the
worker, and the AMQP consumer. Today every decoder is **strict**: it rejects
unknown envelope versions, message types, codecs, and non-zero reserved bits
loudly (`frame.zig` `decode`). Loud rejection is the right baseline — ADR-004
chose it over silent corruption — but it is only half of a versioning story.
This ADR answers the second half: once the wire is frozen at 1.0, how is a
future change made without breaking consumers that shipped against 1.0?

The project convention is a stable ABI where integer sizes are intentional and
breaking if changed. The design philosophy is compile-time/topology validation,
determinism, and enumerated (never runtime-discovered) behavior. The SemVer is
tiny; both sides of the wire ship from this repository, so compatibility is a
shipping decision, not a hope.

## Decision

### 1. Two version domains, strictly separated

- **Envelope version** (`frame.zig` `u16`, currently `1`) — identifies the
  framing layer: magic, header layout, integrity, message-type/codec enums.
- **SignalPackage schema version** (`binary.zig` `schema_version` `u16`,
  `1` legacy / `2` current) — identifies the body layout.

They bump and decode independently. An envelope version bump is a far rarer,
more costly event than a schema bump; the reserved bit/flag field exists
precisely so the envelope can grow flags without a version bump.

### 2. Current wire ABI (byte-for-byte reference)

Verified against source 2026-09-15; the companion ABI pin test
(`tests/serialization/abi_pin_test.zig`, story `m6-abi-pin`) locks this table as
compile-time constants so it cannot drift.

| Layer | Layout (all little-endian) |
|-------|----------------------------|
| FPKG header (48 B) | `FPKG` u8×4 @0 · version u16 @4 (=1) · message_type u8 @6 · codec u8 @7 · payload_len u32 @8 · reserved u32 @12 (must be 0; R-5 reserves it for future flags) · integrity SHA-256[32] @16 |
| `MessageType` (u8) | signal_package=1 … entropy_result=9 (`frame.zig`); 10+ reserved, append-only |
| `Codec` (u8) | binary=1, json=2; values fixed, append-only |
| SignalPackage v1 body | `FNGR` · schema u16 · feature_count u16 · features TLV×N |
| SignalPackage v2 body | `FNGR` · schema u16 · sdk_version_len u16 · sdk_version · collected_at i64 · package_id [16]u8 · feature_count u16 · features TLV×N |
| Feature TLV | id u16 · type u8 · payload_len u32 · payload (cap 4 KiB per feature, R-3) |
| `FeatureValue` payload | Boolean 1 B (strict 0/1, R-4) · Integer i64 · Float u64 bits · String/Bytes u32 len + bytes · arrays count-prefixed (u32), all LE |
| HTTP (ingress) | request head cap 16 KiB; request headers `x-fpkg-schema-version`, `x-fpkg-sdk-version`, `x-fpkg-package-id`, `x-fpkg-integrity` (CORS-allow-listed); reply = worker frame in body + `x-fpkg-message-type` response header |

### 3. Breaking vs additive table

Rules: **append-only everywhere; never repurpose; never renumber.** A change is
additive if an unmodified 1.0 consumer produces identical results on the bytes
it already understands.

| Change | Class | 1.0 consumers | New consumers |
|--------|-------|---------------|---------------|
| New `MessageType` value appended (10+) | Additive (producer-side) | reject loudly & correctly (`InvalidMessageType`); no misparse | must enumerate it before emitting |
| New `Codec` value appended | Additive | reject loudly (`InvalidCodec`) | encoder selects it per package |
| `signal_package` schema bump (v3) | Breaking (body) | must ship **dual-decode** v2+v3 in the same release; keep v2 persist format | select codec via feature-detect before encoding |
| Additive body extension inside current schema | Additive | skip-by-length; synthesized fields must be documented (v1-decode precedent, ADR-004) | read new fields only when present |
| Envelope reserved bit/flags (R-5 field) | Additive | non-zero → `InvalidReserved` until the flag is published with a fallback | define semantics + fallback in the release notes |
| New env. version (u16 ≠ 1) | Breaking | `UnsupportedVersion` (correct) | dual-decode both remember v1/v2 precedent |
| New `FeatureID` appended | Additive | tolerant lookup skips unknown ids (companion task: lookup returns null, never errors) | registry lock guarantees ids are never renumbered or reclaimed |
| Repurposing an existing `FeatureID` / codec value | Forbidden | — | — |
| Reordering fields of a fixed-layout result struct | Breaking | — | **append at tail only** (stable-prefix rule) |
| New HTTP request header | Additive | old ingress ignores unknown headers | parse + validate only what is known |

### 4. Introducing a future v3 (escape hatch)

1. **Additive first.** Extend within the current schema: append-only body
   fields, envelope flag bits (R-5), new `FeatureID`s with tolerant lookup, new
   message types/codecs emitted only producer-side.
2. **If the body must change incompatibly**, bump SignalPackage schema to v3
   with **dual-decode** in the same worker release: v2 and v3 decode into the
   same canonical `Fingerprint`, so the engine and the persist/ledger format
   never see two worlds. Old fixtures remain pinned goldens and are not
   regenerated.
3. **Feature-detect for the wire, never guess.** The SDK enumerates what the
   engine supports before encoding each collection and selects the codec/schema
   per package; an old SDK keeps v2 against an old worker, a new SDK negotiates
   v3. No runtime type discovery and no version sniffing on the wire.
4. Do not reuse a message type, codec value, feature id, or header name for a
   different meaning. Reclaiming is allowed only on a breaking schema bump, and
   then never inside a version 1.0 supports.

### 5. SemVer policy for the npm SDK (first cut)

Refined and frozen with the SDK freeze; this is the contractual baseline:

- **minor** — additive signal collectors/features, backwards-compatible
  signals, docs. Must keep producing bytes a 1.0 engine decodes.
- **patch** — bug fixes with no wire or type-shape change.
- **major** — any change requiring a new SignalPackage schema version, a raised
  minimum engine version, or a changed public API / default behavior; issued
  only together with the engine release that supports it.
- Compatibility claim: an SDK minor works with every engine speaking the same
  SignalPackage schema version; `sdk_version` (v2 body) records the claim per
  package.
- Pre-1.0, the SDK ships 0.x aligned to engine milestone cuts; the wire is
  frozen at engine 1.0.

## Consequences

- Strict decoding stays; additive changes never alter bytes a 1.0 consumer
  understands; breaking changes are impossible to ship by accident (dual-decode
  + coordinated SDK are the only legal paths).
- Reviewers get one enumerated table to check any future wire change against;
  changes that fit no row (or force a repurpose/renumber) are rejected.
- Body extensions surface as documented "skip-by-length" behavior, keeping the
  v1-decode precedent honest.
- The ABI table above must be kept true by the pin test; a drift fails loudly,
  same as the version-injection and golden regressions.
- npm consumers get a staircase: patch → minor never changes results, major is
  announced by schema change and engine support. Results stay deterministic
  across an upgrade.