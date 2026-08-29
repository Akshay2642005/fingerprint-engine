---
title: "Reference"
description: "Meticulous, versioned API surface of the Fingerprint Engine: signals, operations, status codes, and the FPKG wire envelope."
category: "reference"
order: 1
crumbs: ["reference"]
---

# Reference

This section is the authoritative, versioned API surface of the Fingerprint
Engine. Where prod code and prose disagree, the code in `src/` and the wire
layouts below win. Everything here is deterministic and stable: integer
sizes, enum tags, and byte layouts are part of the contract, and changing
any of them is a breaking change.

## Pages

| Page | Contents |
| ---- | -------- |
| [Signals](./signals.md) | The full 102-signal registry across 21 categories: feature ids, value types, weights, and flags. |
| [Operations](./operations.md) | The versioned `Operation` enum (`u8`): validate, normalize, serialize, deserialize, hash, entropy, similarity, risk, package. |
| [Status](./status.md) | The engine `Status` enum: every failure mode folded into a `u8` on the response. |
| [FPKG Frame](./fpkp-frame.md) | The FPKG envelope: 48-byte header, message types, codec selector, and SHA-256 integrity. |
| [API Reference](./api.md) | The engine, SDK, and worker CLI — end to end. |

## How the reference maps to code

- The signal registry is the comptime-ordered `definitions` array in
  `src/model/definitions.zig`, keyed by the `FeatureID` enum in
  `src/model/feature.zig`.
- Operations live as one file per op under `src/engine/ops/`, dispatched
  by a comptime table in `src/engine/engine.zig`.
- The FPKG envelope is implemented in `src/io/frame.zig` and the wire
  constants are mirrored in `src/engine/format.zig` and the serialization
  codecs.

The engine never throws across its API boundary: every computation
resolves to a `Status` on the response, and every byte laid out here is
little-endian.
