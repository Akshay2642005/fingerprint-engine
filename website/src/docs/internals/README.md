---
title: "Internals"
description: "How the engine actually works under the hood: deterministic hashing, the SignalPackage v2 binary layout, and the testing strategy."
category: "internals"
order: 1
crumbs: ["internals"]
---

# Internals

This section explains *how* the deterministic core is built and how it is
proven correct. These pages go one layer deeper than the
[reference](../reference/) — they describe the algorithms, the byte-level
layouts, and the verification machinery that turns determinism from an
aspiration into an enforced property.

## Pages

| Page | Contents |
| ---- | -------- |
| [Hashing](./hashing.md) | The deterministic SHA-256 algorithm: hash metadata, sort by `FeatureID`, type-tag each value, and combine. |
| [Serialization](./serialization.md) | The SignalPackage v2 binary body and its TLV encoding, little-endian, with the version gate. |
| [Testing](./testing.md) | The strategy: unit tests, the self-verifying registry, golden fixtures, e2e, TS parity, and fuzzing. |

## The through-line: byte-level determinism

Every internal mechanism serves one invariant: **same input bytes produce
the same output bytes on any platform, in any build mode.** Hashing is
explicitly ordered so SHA-256 sees a canonical stream. Serialization is
little-endian and TLV-framed so encoding is exact. Testing pins real byte
vectors so any drift fails the gate.
