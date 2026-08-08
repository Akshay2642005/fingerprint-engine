# ADR-002 — Layered `src/` layout, everything depends inward

- **Status:** Adopted (2026-08-07)
- **Rework decisions:** D2, D13

## Context

The pre-rework tree mixed model data, algorithms, platform roots, and SDKs in
one flat `src/core/` with platform code (`src/browser/wasm`, `src/server/native`)
re-implementing the same pipeline. The rework mandate: a reusable deterministic
computation engine where nothing depends outward.

## Decision

Full reorganization into a layered tree:

```
model → core / serialization → engine        (deterministic computation)
io → adapter → worker                        (transport boundary)
clients/browser, bench, build, scripts, docs_website
```

- `model/` — pure data (FeatureID ×102, FeatureValue, registry). Zero deps.
- `core/` — algorithms (hashing, entropy, similarity, risk, normalization,
  validation). Deps: model.
- `serialization/` — codec interface + binary + json. Deps: model (+ io types).
- `engine/` — Operation/Status/Request/Response/process. Deps: core,
  serialization. **No io/transport imports.**
- `io/` — Message, RingBuffer, Channel, Completion, Executor, Frame,
  Reader, Writer, Dispatcher. Zero deps.
- `adapter/` — comptime transport contract + loopback, tcp, amqp. Deps: io (+
  stdx leaf utilities). No engine imports.
- `worker/` — deterministic worker executable. Deps: engine + adapter.
- No `src/native/` (D10) — workers ship as Docker containers.

## Consequences

- The dependency graph is enforced by module imports; violations are caught at
  compile time, not review time.
- The engine can never accidentally learn about HTTP, queues, or databases.
- Adding a transport = adding an adapter, never touching the engine.
