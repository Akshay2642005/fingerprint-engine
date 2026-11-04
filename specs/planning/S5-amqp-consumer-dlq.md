# S5 — AMQP Push Consumer + Dead-Letter Queue

Status: **partial** — the client push-consumer surface and the DLQ topology
shipped in v0.4.0 (`qos`, `consume`, `consume_next`, `consume_body`,
`consumer_ack`, `consumer_nack`, `basic_deliver` dispatch in
`src/adapter/amqp/client.zig`; `fingerprint.dlx` → `fingerprint.dlq` declared on
publisher connect; `amqp dlq` inspector; live-broker e2e in
`tests/adapter/amqp_test.zig`).
What was **not** delivered is the engine's own publish failure path:
`publish_reply` sends `mandatory = false`, so an unroutable message is
discarded by the broker without a trace; `basic_return` is handled as
`fatal()` (`client.zig`), so enabling `mandatory` today would abort the
process; and the worker still acks-and-drops poison frames
(`src/cmd/worker/worker.zig`: "v1 has no dead-letter queue"). That residual is
re-scoped into M8 as ADR-016. No worker-side queue consumer is planned — the
worker's inbound path stays FPKG request/response (ADR-006).
Corrected 2026-11-04 during the M8 bookkeeping sync (an earlier revision of
this note understated S5; the delivery above is verified against `904cf81`).
Depends: S3 (logging), S4 (ingress)
Spec: specs/architecture/amqp-adapter.md (existing adapter surface)

## Problem

The AMQP adapter only supports polling via `basic.get`. The fraud platform
(Go) consumes results, but the Zig side needs:

1. **Push consumption** (`basic.consume` + QoS) for any worker↔broker
   command/control path.
2. **Dead-letter queue** for poison frames and failed publishes — the worker
   currently log-and-drops on `--publish` failures and `mandatory=false`
   unroutable messages.

## Scope

### Push consumer (`basic.consume` + QoS)

The protocol encoding/decoding for `basic_qos`, `basic_consume`,
`basic_deliver`, `basic_ack`, and `basic_nack` already exist in
`spec.zig`. The `Client` struct needs:

1. `qos(prefetch_count)` — sends `basic.qos`, waits for `basic.qos_ok`.
2. `consume(queue, consumer_tag, no_local, no_ack, exclusive, arguments)`
   — sends `basic.consume`, waits for `basic.consume_ok`.
3. `basic_deliver` handling — currently calls `fatal("AMQP operation not
   supported")`. Must dispatch to a caller-provided callback with the
   delivery tag, redelivered flag, exchange, routing key, properties, and
   body.
4. Consumer-side `basic_ack(delivery_tag, multiple)` and
   `basic_nack(delivery_tag, requeue, multiple)` — separate from
   publisher confirm acks. The broker pushes deliveries; the consumer
   pushes acks back.

### Dead-letter queue (DLQ)

- Result queues (`fingerprint-result`) declare with `x-dead-letter-exchange`
  and `x-dead-letter-routing-key` arguments (already modeled in
  `types.zig QueueDeclareArguments`).
- A dedicated `fingerprint.dlq` queue binds to the DLX with routing key
  `dead-letter`.
- The `zig build scripts -- amqp` inspector is extended with a
  `dlq` subcommand that reads from the DLQ without acking.

### Consumer e2e test

- A test against a live broker that publishes a frame, consumes via push,
  and verifies delivery. Skips cleanly when no broker is reachable.
- Target: `tests/adapter/amqp_test.zig` (extend existing tests).

## Not in scope

- Consumer cancellation (`basic.cancel`) — add when needed.
- Channel flow control — out of scope for v1.
- Competing consumers (shared queues) — single consumer per queue for now.

## Verification

- `zig build test --summary all` green.
- `zig build scripts -- amqp dlq` reads from the DLQ.
- Consumer e2e test passes when a broker is reachable; skips cleanly otherwise.
- `docker compose up` with the new services (S6) shows the DLQ receiving
  a deliberately poison frame.
