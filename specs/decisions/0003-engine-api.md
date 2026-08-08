# ADR-003 — Single deterministic `Engine.process` entry point

- **Status:** Adopted (2026-08-07)
- **Rework decisions:** D3, D5, D6

## Context

The pre-rework engine exposed many ad-hoc entry points (wasm exports, native
handle API) that each re-implemented the pipeline. The rework needs one
transport-free, replayable entry point that any executable (worker, bench,
scripts) can call identically.

## Decision

```
Engine.process(request: *const Request, response: *Response, arena: Allocator) !void
```

- `Request = { operation: Operation, codec: CodecID, payload: []const u8 }` —
  payload is serialized bytes in and out.
- `Operation` is a versioned `enum(u8)`: validate, normalize, serialize,
  deserialize, hash, entropy, similarity, risk, package.
- `Response = { operation, status, payload, payload_len }` — caller-owned.
- `process()` is a **comptime dispatch table** over `Operation`; each op is an
  independent handler (`engine/ops/*.zig`). Adding an op = new file + one table
  row. No runtime registration, no vtable.
- The engine never reads the clock and never uses randomness. `collected_at`
  and `package_id` arrive inside the payload as input data (D6).
- Integrity = SHA-256 of the canonical serialized payload, carried in the FPKG
  frame header (D5). Not HMAC — the engine must never know keys (authenticity
  is the ingress/adapter's job).

## Consequences

- Determinism is enforceable by golden-fixture replay tests at every layer
  (engine, worker loopback e2e, HTTP→FPKG e2e).
- Async lives only at the transport boundary; the engine stays synchronous.
- Any future consumer (CLI, bench, test container) gets the same semantics by
  calling one function.
