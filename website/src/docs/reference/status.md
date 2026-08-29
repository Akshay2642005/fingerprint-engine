---
title: "Status"
description: "The engine Status enum (u8): every failure mode folded onto the response, never thrown across the API boundary."
category: "reference"
order: 4
crumbs: ["reference", "status"]
---

# Status

The `Status` enum in `src/engine/status.zig` is the result status of an
engine operation. The engine **never throws across the API boundary**: every
failure folds into a `Status` carried on the `Response`, so callers always
get a structured outcome rather than an exception.

```zig
pub const Status = enum(u8) {
    ok = 0,
    invalid_request = 1,
    invalid_payload = 2,
    unsupported_version = 3,
    invalid_input = 4,
    buffer_overflow = 5,
    out_of_memory = 6,
    internal_error = 7,
};
```

The tags are explicit `u8` values. `Status.code()` returns the wire byte
(`@intFromEnum`); on the worker this is the first byte of the reply payload.
The TypeScript SDK reads this same byte to classify a worker reply (`0` is
`ok`).

## Status table

| Tag | Value | Meaning |
| --- | ----- | ------- |
| `ok` | `0` | The operation succeeded; the payload holds the result. |
| `invalid_request` | `1` | The request was malformed — unknown operation tag or unknown codec (e.g. an outbound-only message type, or a codec the engine does not implement). |
| `invalid_payload` | `2` | The input bytes failed to decode — bad magic, truncated data, or a non-canonical value (e.g. a boolean byte other than `0`/`1`, or an unknown feature type/id tag on the wire). |
| `unsupported_version` | `3` | A version mismatch: the FPKG envelope version or the SignalPackage body schema version is not one this build understands. |
| `invalid_input` | `4` | A validation/normalization failure that is severe enough to abort the operation rather than report warnings. |
| `buffer_overflow` | `5` | The caller's result buffer was too small to hold the encoded result. |
| `out_of_memory` | `6` | The engine could not allocate scratch memory to complete the operation. |
| `internal_error` | `7` | An unexpected, non-classified failure inside the engine. |

## How status is reached

- **Decode failures** (`InvalidMagic`, `InvalidPayload`, `Truncated`) map to
  `invalid_payload`.
- **Version mismatches** (`UnsupportedVersion` from the envelope or the body
  schema gate) map to `unsupported_version` **at the boundary before the
  codec parses anything**.
- **Operation/codec tags** that are unknown or not dispatched map to
  `invalid_request`.
- Capacity faults (`buffer_overflow`, `out_of_memory`) never corrupt state;
  they are reported on a fresh response.

## On the wire

The worker's reply frame is

```
u8 status | engine result
```

so the very first payload byte is the `Status` value. A successful
`hash` reply, for example, is `0` followed by the 32-byte digest, the
`u16` feature count, and the `u16` schema version. Downstream consumers
(fraud platform, SDK) branch on this byte before interpreting the rest of
the payload.
