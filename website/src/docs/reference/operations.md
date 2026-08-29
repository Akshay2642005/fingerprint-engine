---
title: "Operations"
description: "The versioned Operation enum (u8) that names every engine computation, with its input, output wire layout, and role."
category: "reference"
order: 3
crumbs: ["reference", "operations"]
---

# Operations

The `Operation` enum in `src/engine/operation.zig` names the set of
deterministic computations the engine can perform. It is a `enum(u8)` — tags
are explicit so requests survive serialization and versioning — and it is
**non-exhaustive**, so wire tags from newer peers degrade gracefully instead
of being coerced to a valid operation.

```zig
pub const Operation = enum(u8) {
    validate = 1,
    normalize = 2,
    serialize = 3,
    deserialize = 4,
    hash = 5,
    entropy = 6,
    similarity = 7,
    risk = 8,
    package = 9,
    _,
};
```

Dispatch happens through `engine.process()`, the single entry point. It takes
an immutable `Request` (operation + codec + payload slices) and produces a
`Response` owned by the caller. Dispatch is a **comptime table** — one row
per op in `src/engine/engine.zig` — with no reflection and no dynamic
dispatch. An unknown operation tag is caught at the dispatch boundary and
mapped to `invalid_request`.

## Operation table

| Tag | Operation | Input | Output |
| --- | --------- | ----- | ------ |
| 1 | `validate` | SignalPackage (binary) | `is_valid` flag, missing-required warnings, normalization warnings |
| 2 | `normalize` | SignalPackage (binary) | normalization warnings |
| 3 | `serialize` | SignalPackage (binary) | bytes in the requested codec |
| 4 | `deserialize` | bytes (binary) | re-encoded canonical package |
| 5 | `hash` | SignalPackage (canonicalized) | 32-byte digest + feature count + schema version |
| 6 | `entropy` | SignalPackage | `f64` entropy score |
| 7 | `similarity` | dual payload `(a, b)` | `f64` score + compared count |
| 8 | `risk` | SignalPackage | `f64` score + label + flags |
| 9 | `package` | SignalPackage | validation + normalization + serialized package |

## `validate` (1)

Runs the required-feature presence check and the normalization pass together,
returning an `is_valid` boolean (false if any required feature is missing or
any value fails bounds/type checks) along with warnings. Result layout:

```
u8 is_valid
u16 required_count | (u16 feature_id | u8 is_critical)×N
u16 norm_count     | (u8 kind | u16 feature_id)×N
```

The warning `kind` is `1` for a type mismatch, `2` for a bound violation.

## `normalize` (2)

Runs only the type + bounds normalization and reports the warnings. Result
layout:

```
u16 norm_count | (u8 kind | u16 feature_id)×N
```

## `serialize` (3)

Decodes the binary package and re-emits it in the codec selected by the
request (`binary` or `json`). Validation and normalization are **not** run;
this op only moves model ↔ bytes.

## `deserialize` (4)

Decodes binary bytes into the model and re-encodes them canonically — a
round-trip. JSON decode is not yet available (it lands with the
serialization rewrite); a JSON request is rejected.

## `hash` (5)

The **canonical path**. Decodes the package, sorts features by `FeatureID`
(`format.canonicalize`), and hashes. Result layout:

```
[32]u8 digest | u16 feature_count | u16 schema_version
```

This is the operation that produces the canonical fingerprint digest. It is
executed **only by workers** and is not exported to WASM — the browser SDK
never computes the digest. Because features are sorted first, the digest is
independent of collection order: same signals, same digest, on any platform.

## `entropy` (6)

Computes the Shannon fingerprint entropy. Result is the little-endian `u64`
bit-cast of an `f64` score.

## `similarity` (7)

Compares two packages. The input payload is a nested layout:

```
u32 a_len | a bytes | b bytes
```

and the result is:

```
f64 score | u16 compared_count
```

`compared_count` is the number of feature ids present in both `a` and `b`.
The score is `0.0`–`1.0` (weighted per-feature comparison).

## `risk` (8)

Runs the risk assessment over the package. Result layout:

```
f64 score | u8 label_len | label | u8 flag_count | u8× flags
```

Flags are the ordinal values of `core.risk.RiskFlag` (missing features,
bound violations, coverage deficit, entropy shortfall, etc.).

## `package` (9)

The browser's primary call: one request runs the whole
validate → normalize → serialize pipeline and returns diagnostics alongside
the package. Result layout:

```
[validation result block]          (as validate)
u32 package_len | package bytes    (v1/v2 binary encode of the input)
```

Because serialization is version-field-driven, a v1 input round-trips as v1
and a v2 input keeps its replay identity (the 16-byte package id).

## Worker mapping

The worker maps inbound FPKG message types to operations and replies with the
corresponding result type. `signal_package → hash` is the canonical path:

| FPKG in | Operation | FPKG reply |
| ------- | --------- | ---------- |
| `signal_package` (1) | `hash` | `fingerprint_result` (4) |
| `validation_result` (2) | `validate` | `validation_result` (2) |
| `normalization_result` (3) | `normalize` | `normalization_result` (3) |
| `fingerprint_result` (4) | `hash` | `fingerprint_result` (4) |
| `risk_result` (5) | `risk` | `risk_result` (5) |
| `similarity_result` (6) | `similarity` | `similarity_result` (6) |
| — (`diagnostics`, `fingerprint_computed`, `entropy_result`) | — | rejected `invalid_request` |

The outbound-only message types (`diagnostics`, `fingerprint_computed`,
`entropy_result`) are not dispatched as operations; a frame of that type is
answered with an empty `invalid_request` reply.
