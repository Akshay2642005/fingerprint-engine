---
title: "Testing"
description: "The layered strategy: 376+ unit tests, a self-verifying registry, golden-fixture replay, e2e, TS parity, and fuzzing that enforces determinism."
category: "internals"
order: 4
crumbs: ["internals", "testing"]
---

# Testing

Testing is how determinism stops being an aspiration and becomes an enforced
property. The suite is layered so that every byte of the immutable contract
is pinned: unit tests prove the algorithms, the self-verifying registry keeps
the suite honest, golden fixtures pin real bytes cross-language, e2e tests
drive real executables over the real wire protocol, and fuzzing probes the
decode/normalize/hashing paths with arbitrary inputs.

The entry point is `zig build test` (Preflight). Integration/e2e tests that
need compiled executables are run via `zig build test-integration`, and the
TypeScript parity suite via `node --test tests/clients/browser/`.

## Unit tests

**376+ unit tests** across `tests/{model,core,serialization,engine,io,adapter,worker,build}`:

| Directory | Focus |
| --------- | ----- |
| `model` | Feature definitions, values, metadata, registry integrity, bindings. Largest group (~147). |
| `core` | Types, bounds, normalization, validation, hashing, entropy, similarity, risk. |
| `serialization` | Binary encode/decode, JSON, codec tags, integrity digest. |
| `engine` | Dispatch, determinism, replay, round-trip, unknown-version handling, integration. |
| `io` | Frame, reader/writer, ring buffer, channel, message pool, executor, dispatcher. |
| `adapter` | Loopback, TCP, transport contract, client, AMQP. |
| `worker` | CLI parsing, operation↔message mapping, end-to-end `processFrame`. |
| `build` | Dist surface, browser package. |

The engine tests are notable for what they pin directly: `determinism_test`
asserts the digest for the same payload is byte-identical across runs and
across feature-order permutations; `replay_test` deserializes a package and
asserts the replayed digest matches the original.

## The self-verifying registry (`tests/root.zig`)

`tests/root.zig` is a **quine**: it contains the comptime import block of
every test file and, at test time, regenerates that block by walking the
`tests/` tree and compares the regeneration against the file on disk,
byte-for-byte. If a test file is added or removed and the import list is
not updated, `zig build test` fails with `tests/root.zig needs updating.`
Rerunning with `SNAP_UPDATE=1` regenerates it automatically.

This keeps the registry permanently fresh: you cannot add a test and forget
to wire it in, and you cannot delete one and leave a dangling import. The
self-check excludes `root.zig` itself and `tests/utils/` (the named helper
module wired in from `build.zig`).

## Integration / e2e: real executables as subprocesses

`src/integration_tests.zig` contains **no engine code**. Everything is
driven through pre-built executables (`fingerprint`, `worker`, `ingress`,
`fingerprint-bench`, `scripts`) **spawned as subprocesses**, with stdout,
stderr, and exit status asserted. Executable paths are injected at build
time via `test_options`, so `zig build test-integration` always exercises the
binaries it just built.

The test binary re-duplicates the FPKG framing by hand — exactly as an
external client would — rather than importing `src/io/frame.zig`, so the e2e
tests prove the wire protocol is actually parseable by someone who does not
share the engine's framing code.

## Worker e2e over the FPKG wire protocol

The worker e2e tests spawn the `worker` executable and **speak the FPKG
wire protocol**:

- **Loopback**: pipe the canonical fixture into `worker start
  --transport=loopback` via stdin, and assert the reply frame carries the
  pinned digest.
- **TCP**: spawn `worker start --transport=tcp --listen=127.0.0.1:0` (which
  announces its ephemeral port on stderr), connect a raw client, POST an FPKG
  request frame, and read the FPKG reply.
- **Adversarial**: a protocol-violating TCP client must be survived without
  crashing the worker.

Reply frames are validated byte-for-byte against a **pinned fixture digest
as a compile-time constant**.

## The golden fixture & replay property

`tests/fixtures/fingerprints/signal-package-v2.bin` is the canonical v2
signal package — a pinned byte vector (the sibling
`signal-package-v2.signals.json` is its human-readable manifest). Its engine
**hash is pinned as a compile-time constant** in `src/integration_tests.zig`:

```
db29fc13d8dad5dc0bd7b1f997155cff411f3da88a597619f5e0d67a251e6c75
features = 3, schema = 2
```

Every test run re-drives the fixture through the engine and the worker and
asserts the digest matches this constant **byte-for-byte**. A change that
shifts the digest by even one byte fails the gate, so determinism is
contractual. The fixture is **never regenerated once pinned**; any change
that would alter it is a breaking contract change and must be reviewed as
such.

The **replay property** is tested explicitly: re-running a package (or
feeding the canonical fixture) produces the identical digest every time.
This is what makes distributed scaling and forensic replay safe — any
stateless worker reproduces the exact bytes that underpinned a prior
decision.

## TS SDK parity (`node --test`)

`tests/clients/browser/package_parity.test.mjs` is a cross-language proof
that the TypeScript serializer mirrors `serialization/binary.zig` exactly:

- It rebuilds SignalPackage v2 bytes **from the JSON manifest via the
  browser serializer** and asserts byte equality with the Zig-produced
  `signal-package-v2.bin`.
- A second test asserts the exact wire layout: `FNGR` magic, schema version,
  header field positions, and TLV framing byte-for-byte.

This guarantees the browser produces exactly the bytes the Zig engine
expects — the two implementations cannot silently disagree. (The suite is
run with `node --test` after `zig build clients:browser` builds `dist/`.)

## Fuzz targets

Randomized fuzz harnesses over the deterministic paths, three targets in
`tests/fuzz/` run as part of the suite:

- **`fuzz_decode`** — binary decode with arbitrary bytes; must never crash
  and must map every failure to a classified error.
- **`fuzz_normalize`** — normalization with arbitrary feature values.
- **`fuzz_hashing`** — hashing with arbitrary values; asserts stability
  across repeated invocations.

Fuzzing extends the golden-fixture guarantee to inputs that no human wrote:
for arbitrary input bytes, the decode/hash/normalize paths are asserted to be
stable and leak-free.

## Layer summary

| Layer | Runs under | What it pins |
| ----- | ---------- | ------------ |
| Unit (376+) | `zig build test` | Algorithm correctness, isolation |
| Self-verifying registry | `zig build test` | The test suite is always in sync |
| Integration/e2e | `zig build test-integration` | Real binaries as subprocesses |
| Worker FPKG e2e | `zig build test-integration` | Wire protocol + pinned digest |
| Golden replay | `zig build test` + e2e + TS | Determinism across languages |
| TS parity | `node --test` | TS serializer == Zig codec |
| Fuzz | `zig build test` | Arbitrary-input robustness |
