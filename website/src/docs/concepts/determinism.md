---
title: "Determinism"
description: "Why same input bytes always yield same output bytes on any platform, and how this makes scaling and replay safe."
category: "concepts"
order: 3
crumbs: ["concepts", "determinism"]
---

# Determinism

The Fingerprint Engine's single most important architectural invariant is
**determinism**: for the same input bytes, the engine produces the same
output bytes, on any platform, at any time, no matter how many times it
runs. This is not an aspiration or a convention — it is a hard, enforced
property of the core. Every design decision in this project either serves
determinism or is moderated by it.

This page explains what determinism means concretely in this codebase, the
mechanisms that guarantee it, and — most importantly — the distributed
operational guarantees it unlocks.

## What determinism means here

Determinism is commonly conflated with mere *reproducibility within a run*
or *same machine, same result*. Both are weaker than what the engine
requires. The engine's contract is stronger:

```
input bytes  ──►  engine.process  ──►  output bytes
                (identical byte-for-byte
                 on any platform, any build mode)
```

Concretely, two instances of the engine — one running in a Linux Docker
container, one running in a developer's macOS build, one running under a
WASM harness — must produce **byte-identical** results for the same input
package. There is no tolerance for endianness drift, floating-point
rounding variation, hash-iteration order, hash-map traversal order, or any
other source of incidental nondeterminism.

The core algorithms live in `src/core/` — hashing, normalization,
validation, similarity, entropy, and risk — and they are written under a
strict rule: **no clock, no randomness, no hidden state**. Each operation
is a pure function of its inputs.

## The three sources of nondeterminism the engine removes

### 1. No clock inside the core

A fingerprint is *supposed* to vary over time in one well-defined way: the
collection timestamp is a real, captured artefact of the browser session.
But that timestamp is **an input**, not a computation. The core never calls
the wall clock. Time enters only as a field of the incoming signal package
(`collected_at`), is hashed deterministically like any other field, and is
never re-read or re-derived during processing.

The engine computes *from* the timestamp; it does not compute *with the
time*. This is what makes replay possible — a package captured yesterday
and replayed today still hashes to the same digest, because nothing inside
the engine consults today's clock.

### 2. No randomness inside the core

There is no RNG in the core. There is no UUID generation, no
randomised initialisation, no hash seed with per-run entropy, no
bulk-allocator allocation-order dependence that changes results. Anything
that needs a nonce — a package identifier, for example — is produced at
the *collection* boundary in the SDK, not in the computation.

Deterministic algorithms consume deterministic metadata. This is also what
keeps the public facade honest: an operation like `hashFingerprint` is a
fixed function, and no amount of stochastic behaviour can leak into it.

### 3. No iteration-order dependence

Zig's `std.AutoHashMap` and similar structures do not promise a stable
iteration order. The core never hashes a set by iterating a hash map.
Instead, feature hashing is explicitly **ordered**: the hasher sorts
features by `FeatureID` before hashing (see
[architecture](/docs/architecture/) — Hashing Algorithm), so the byte stream
fed to SHA-256 is canonical regardless of how the features arrived or in
what order they were collected. SHA-256 over a canonical, ordered byte
stream is deterministic; SHA-256 over an unstable iteration order would not
be.

This design principle — *explicit ordering, canonical byte streams, pure
functions* — applies to serialization, entropy, similarity, and risk
exactly as it applies to hashing.

## Enforcing determinism: golden-fixture replay tests

Determinism as a stated goal is meaningless without enforcement. The
engine's primary enforcement mechanism is the **golden-fixture replay
test**:

- A canonical `signal-package-v2.bin` fixture lives in
  `tests/fixtures/`, together with a signals manifest describing each
  feature.
- The engine's digest for that fixture is computed once and **pinned as a
  compile-time constant** in the worker e2e tests.
- Every test run re-drives the fixture through the worker (over the real
  loopback/tcp FPKG wire protocol) and asserts the digest matches the
  pinned constant **byte-for-byte**.
- The TypeScript SDK's serializer is cross-checked against the same golden
  fixture by a parity test (`node --test`), guaranteeing that the browser
  produces exactly the bytes the Zig engine expects.

A change that alters the digest of the golden fixture — even by one byte —
fails the test suite. This is what makes the contract enforceable rather
than aspirational: **if any platform produces different bytes for the same
input, the gate is red and the change is rejected** (per the repository's
Preflight/CI mandate).

The fuzz targets in `tests/fuzz/` (decode, normalize, hashing) extend this
further: for arbitrary inputs, hashing is asserted to be stable across
repeated invocations.

## Why this makes distributed scaling safe

The worker binaries are designed to be **stateless**. A stateless worker
holds the `signal_package → hash/entropy/risk` computation as a pure
function, and determinism is what makes stateless scaling correct:

- **Any worker, any package.** Because the result depends only on the
  input bytes, any idle worker can pick up any package. There is no cache
  to warm, no partition to own, no per-device affinity, and no hot
  standbys that must see the same history to agree.
- **Horizontal and elastic scaling.** Operator adds a replica → new
  workers immediately produce identical results for identical inputs, so
  sharding, autoscaling, and capacity changes never change the output.
- **Consistency under concurrency.** Multiple workers racing on the same
  package produce the same answer, so downstream consumers (the fraud
  platform) never observe disagreement about what a package "means."
- **No shared mutable state.** When workers store nothing, they cannot
  corrupt a shared store, and they can be destroyed and recreated freely.
  The async `Executor` lives only at the transport boundary and never leaks
  state into the core.

Because the core has no clock and no randomness, a fleet of workers all
processing the same package not only *can* produce identical answers — they
*provably* do.

## Why this makes replay safe

Determinism turns replay from a debugging nicety into an operational
guarantee:

- **Disputed decisions are reproducible.** Fraud platforms invariably need
  to re-examine a block decision weeks later. Given the original
  `SignalPackage` (identifiable by its 16-byte package id), an operator can
  re-feed it to any worker and recover the exact digest, risk, and entropy
  that underpinned the original decision.
- **Forensic replay is exact, not approximate.** Because the engine is a
  pure function with no time or randomness, a replayed package produces the
  *same* byte stream, not a "close" one. This matters when a decision hangs
  on a single flag or a marginal entropy value.
- **Upgrade safety via versioning.** The engine is versioned end-to-end
  (`Operation`/`Status`, `SchemaVersion`, SDK version). Replaying an old
  package against a new engine is explicit and predictable: either the
  version is compatible and the digest is reproduced exactly, or the schema
  maps to `unsupported_version` at the boundary — never silently different.
- **Audit and compliance.** If a regulator or auditor asks "what did this
  device actually produce and what did you compute?", the answer is
  byte-exact, demonstrable, and repeatable by anyone with the fixture.

## Determinism is a boundary, not everywhere

It is important to be precise about *where* determinism holds. The **core
engine** is deterministic. The transport layer around it — network arrival
order, AMQP publish timing, the ingress's choice of which worker to relay
to — is naturally nondeterministic, and that is fine, because it does not
influence the computed result. The SDK's *collection* is also not
deterministic in the strict sense: browsers report values under real,
ever-changing conditions, and the captured timestamp is a moment in time.
The engine's guarantee is narrower and more powerful: **whatever bytes the
browser actually collects, the engine maps them to a fixed, reproducible
output.** Determinism at the computation layer, not at the observation
layer.

## Design rules that fall out of it

- Core code never imports clock, RNG, or dynamic-dispatch libraries.
- Feature hashing sorts by `FeatureID` before producing bytes.
- Integer sizes in the ABI are intentional and breaking if changed — they
  are part of the byte-level contract.
- Any new core algorithm must be covered by a golden/replay assertion
  before it is considered complete.
- Any change that shifts a golden digest must be reviewed as a
  **breaking contract change**, not a routine tweak.

See [Fingerprinting](/docs/concepts/fingerprinting/) for why computation being
server-side is what makes a deterministic engine trustworthy, and
[Signals](/docs/reference/signals/) for what the engine is being deterministic *about*.
