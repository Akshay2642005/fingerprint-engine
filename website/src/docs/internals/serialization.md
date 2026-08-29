---
title: "Serialization"
description: "The SignalPackage v2 binary body and TLV encoding — little-endian layout, the schema-version gate, and unknown-version handling at the engine boundary."
category: "internals"
order: 3
crumbs: ["internals", "serialization"]
---

# Serialization

The SignalPackage is the versioned message that carries collected signals
plus metadata from the SDK to the engine. The binary codec lives in
`src/serialization/` (`binary.zig` is the encoder/decoder, `codec.zig` is
the wire-stable version constants). Every integer is **little-endian**.

There are two body schema versions. `v1` is the legacy layout; `v2` is the
current replay-identity layout:

| Constant | Value | Layout |
| -------- | ----- | ------ |
| `schema_version_v1` | `1` | magic + schema + feature count + features |
| `schema_version_v2` | `2` | magic + schema + SDK metadata + timestamp + package id + feature count + features |

## The v2 body

The complete v2 SignalPackage body:

```
<-- header →|
"FNGR"        [4]u8    magic
schema        u16      body schema version = 2
sdk_len       u16      sdk_version length (bytes)
sdk_version   sdk_len  SDK version string
collected_at  i64      collection timestamp (Unix ms)
package_id    [16]u8   replay identity
feature_count u16      number of features
features      TLV×N    TLV-encoded features
```

| Field | Size | Meaning |
| ----- | ---- | ------- |
| `"FNGR"` magic | 4 | Format identifier; `InvalidMagic` if absent. |
| `schema` | `u16` | Body schema version. |
| `sdk_len` / `sdk_version` | `u16` + N | SDK version — printable provenance, hashed into the digest. |
| `collected_at` | `i64` | Collection timestamp (an input, never re-derived). |
| `package_id` | `16` | Client-generated replay/correlation identity — makes retries and dedupe safe. |
| `feature_count` | `u16` | Number of TLV features that follow. |
| `features` | TLV×N | Each feature is a Tag-Length-Value record. |

The `package_id` is missing on the wire for `v1` bodies; a decoded `v1`
fabricates an empty SDK version, zero `collected_at`, and an all-zero package
id, so legacy constructions compile and round-trip unchanged.

## TLV feature encoding

Each feature is a Tag-Length-Value record:

```
u16 feature_id      (LE)   <- tag: which signal
u8  value_type      (LE)   <- the FeatureType
u32 payload_len     (LE)   <- length of the value payload
payload             (LE)   <- the value, canonically encoded
```

The `payload_len` is capped at **4 KiB per feature** (`R-3`), which covers
any practical browser fingerprint value (the longest being a StringArray
with many entries). A payload exceeding the cap fails the fixed-buffer write
rather than growing unbounded.

The value payloads mirror the hashing type-tags:

| `FeatureType` | Payload bytes |
| ------------- | ------------- |
| Boolean | `u8` `0`/`1` |
| Integer | `i64` LE |
| Float | `u64` LE (bit-cast of the `f64`) |
| String | `u32` len LE + bytes |
| Bytes | `u32` len LE + bytes |
| StringArray | `u32` count LE + per-item `u32` len + bytes |
| IntegerArray | `u32` count LE + per-item `i64` |
| FloatArray | `u32` count LE + per-item `u64` bit-cast |
| BytesArray | `u32` count LE + per-item `u32` len + bytes |

### Decode validation

Decoding is strict. On the wire, untrusted bytes can claim anything, so the
decoder validates before use:

- The `FeatureType` tag is `intToEnum`'d before any payload is read; an
  unknown tag is `InvalidPayload` (`BUG-009`).
- Booleans must be exactly one byte and exactly `0` or `1` — a non-canonical
  boolean is rejected (`R-4`).
- `feature_id` is validated through `intToEnum` as well.
- Truncated reads map to `Truncated`.

## The version gate at the engine boundary

`decode` accepts only the two known body versions. Any other schema version
is rejected with `UnsupportedVersion` — **before the codec parses anything**.
The engine boundary (`format.decodePayload`) additionally asserts that the
decoded schema is in its supported list; this is the boundary where an
unknown body schema maps to `Status.unsupported_version` on the response.

Crucially, **encoding is more permissive than decoding**: `encode` writes the
`v1` body for any unknown version, preserving the version number in the
header. The version gate — and the decision about which versions are valid —
lives at the decode/engine boundary, not in the encoder. This keeps encoding
a pure model→bytes function while the engine, which owns the versioning
policy, decides what it will accept.

The FPKG envelope (see [FPKG Frame](../reference/fpkp-frame.md)) adds a
separate, outer envelope-version gate; the two are independent.

## JSON codec

`serialization.jsonEncode` emits the model as JSON. JSON is `CodecID.json`
(`2`); binary is the default `CodecID.binary` (`1`). JSON *decoding* is not
yet available — the engine's `serialize` operation can emit JSON, but the
decode path accepts binary only until the serialization rewrite lands.

## Lifecycle of a v2 round-trip

```
collect (SDK)
  → encodeSignalPackage → FNGR v2 bytes
  → wrapped in FPKG frame (SHA-256 integrity)
  → worker: hash op decodes (schema gate → v2 accepted)
  → canonicalize + hash → digest
```

The decoded memory is caller/arena-owned; `decode` returns a
`DecodedFingerprint` that must be `deinit`'d (v2 frees `sdk_version`, all
feature values, and the feature slice).
