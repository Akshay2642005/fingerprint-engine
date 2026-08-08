# Test plan — Fingerprint Engine

Refreshed 2026-08-08. Current: 383 tests (376 unit + 7 integration/e2e),
3 fuzz targets, 12 benchmarks. `zig build test --summary all` must stay green
on every commit (Zig 0.14.1).

## Test layers (current)

| Layer | Location | Covers |
|-------|----------|--------|
| Unit (Zig) | `tests/{model,core,serialization,engine,io,adapter,worker,build,browser}/` | algorithms, codecs, engine dispatch, io primitives, adapter framing, worker CLI parsing |
| Integration/e2e | `src/integration_tests.zig` (drives pre-built executables) | scripts/bench smokes, worker loopback pipe + tcp round-trip, protocol-violation handling, `amqp` round-trip |
| TS (node --test) | `tests/clients/browser/` | golden parity (TS serializer vs Zig fixture), wire-layout, middleware, mocked-fetch transport |
| Fuzz | `tests/fuzz/` | decode, normalize, hashing |
| Bench | `src/bench/` | 12 deterministic benchmarks |

## Pinned golden

`tests/fixtures/fingerprints/signal-package-v2.bin` — canonical digest
`db29fc13d8dad5dc0bd7b1f997155cff411f3da88a597619f5e0d67a251e6c75`
(features=3, schema=2), a compile-time constant in `src/integration_tests.zig`,
consumed by the TS parity test via the JSON manifest. **Never regenerate.**

## Planned additions

| Slice | New tests |
|-------|-----------|
| S1 | TS wire-layout corrected + pinned to the digest constant; worker tcp idle-timeout behavior; graceful-shutdown drain e2e |
| S2 | worker `version` == injected version; AMQP product version carries it |
| S3 | log level filtering, scope rendering, text/JSON escaping, `--quiet`, `--log-level=err` suppresses announcements while serving (integration) |
| S4 | ingress unit (header validation, frame wrapping, status→HTTP map) + e2e (spawn worker + ingress, POST the canonical fixture, assert pinned digest; dead-worker retry; SIGTERM clean exit) |
| S5 | AMQP consumer (basic.consume + QoS) and DLQ tests; broker e2e that skips cleanly when no broker is reachable |
| S6 | full-stack compose smoke; release-surface checks for the ingress image |

## Verification mandate

Every story ends with manual verification + UAT (see
`specs/quality/verifications/`). CI green is necessary but not sufficient — live
broker, real browser, and container runs are exercised per checklist.
