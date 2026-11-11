<!-- // story: m8-observability -->

# ADR-016 — Publish-failure and dead-letter path for outbound events

- **Status:** Adopted (2026-11-04)
- **Source:** `src/adapter/amqp/publisher.zig`, `src/adapter/amqp/client.zig`
  (`publish`, `basic_return`, `publish_confirms`), `src/cmd/worker/worker.zig`,
  `tests/adapter/amqp_test.zig`
- **Extends:** ADR-006 (outbound AMQP events), ADR-007 (stateless worker),
  ADR-009 (platform owns durability), D9/D-v1-4 (no Zig store),
  ADR-014 (failure counters). Does not supersede any of them.

## Context

The dead-letter **topology** already exists. `Publisher.init` declares the
`fingerprint` exchange, the `fingerprint.dlx` exchange, the durable
`fingerprint.dlq` queue, and binds it under the `dead-letter` routing key; an
`amqp dlq` inspector and a live-broker consumer e2e exist. What does not exist
is a path that ever *uses* it:

1. `publish_reply` sets **`mandatory = false`**
   (`src/adapter/amqp/publisher.zig`). An unroutable message is therefore
   discarded by the broker and the publisher is never told.
2. `basic_return` is handled as **`fatal()`**
   (`src/adapter/amqp/client.zig`). Flipping `mandatory` to true without fixing
   this would abort the worker on the first unroutable message.
3. Publish failures in the worker are **log-and-drop**, and the log is
   **misleading**: `p.publish_reply(reply) catch |err| { log.warn("publish
   dropped: …") };` is immediately followed by an unconditional
   `log.info("publish confirmed")`, so an operator sees a success line for
   every failed publish (`src/cmd/worker/worker.zig`). Poison *inbound* frames
   are acked and dropped with the comment "v1 has no dead-letter queue".

There is also a subtlety that shapes the decision: **broker dead-lettering
covers rejected/nacked/expired messages on a queue, not unroutable ones.** A
message published to an exchange with no bound queue is returned to the
*publisher*. A DLX therefore cannot catch the case the engine actually has —
and since the engine declares no result queues (consumers do), the engine's
own failure mode is unroutable/failed publishes, not consumer rejections.

## Decision

### 1. The reply is never at risk — publish happens after it

Ordering is a hard invariant and stays: the digest reply is written to the
client first, the event is published second. A broker failure may cost the
event; it may never cost the reply. This is already true and is asserted by a
test rather than left implicit.

### 2. `mandatory = true`, and `basic_return` is an error, not a fatal

- `publish_reply` sets `mandatory = true`.
- The client records a `basic_return` during a publish and returns
  `error.Unroutable` from `publish` instead of calling `fatal()`. The confirm
  is still awaited, so state stays consistent; the return is surfaced on the
  call that caused it.
- The worker treats `error.Unroutable` like any other publish failure: it is
  counted, logged once, and the serving loop continues.
- **The "publish confirmed" line is made truthful as part of this change.** It
  currently logs unconditionally after the `catch`, so it reports success on
  failure. It moves inside the success path; the failure path keeps its own
  `warn`. A log that lies is worse than a missing log, and this is the exact
  signal an operator would use during an outage.

### 3. Unroutable and failed events are republished to the DLX once

Because the broker will not dead-letter an unroutable message for us, the
publisher does it explicitly:

- On `error.Unroutable`, republish the same frame to `fingerprint.dlx` with
  routing key `dead-letter` — **exactly once**, no retry loop.
- If that republish also fails, count it (`publish_total{result="dlq_failed"}`)
  and log. There is no third attempt and no buffering.
- The worker stays **stateless** (ADR-007): the DLQ is a broker-side queue, not
  an in-process buffer, so nothing survives in the worker and D9 is untouched.

### 4. Broker unreachable is an honest, bounded failure

A broker-side dead-letter path cannot help when the broker is down. The
decision is explicit rather than optimistic:

- Reply is served (invariant §1). The event is **lost**.
- `publish_total{result="failed"}` increments; the log line is emitted once per
  outage transition, not once per collection, so an outage cannot flood stdout.
- `/readyz` reports not-ready while the link is down (ADR-014 §5).
- The publisher is dropped and **one** reconnect is attempted on the next
  collection. Success resumes publishing; repeated failure keeps the component
  unready and keeps serving replies.

Recovering events lost during an outage is platform-side (D-v1-4). The engine
does not queue and does not replay.

### 5. Poison inbound frames are counted, not dead-lettered

An inbound poison frame is a *request*, not a broker message: there is no queue
holding it and no message to move. The worker keeps acking and dropping it and
now counts it by reason (`frames_dropped_total{reason}`). The DLQ is
exclusively for **outbound events**. Conflating the two would put unrelated
payloads in one queue and make the platform's consumer parse garbage.

### 6. The engine does not impose retention on the DLQ

The queue stays durable with **no engine-imposed length cap or TTL**. A TTL
silently deletes exactly the evidence the DLQ exists to collect, and a cap
invented by the engine could discard evidence the platform wanted. The engine
publishes the queue depth as a metric and documents an alert on growth; the
platform owns draining, retention, and any cap when it owns the topology.

**Rejected alternatives:** (a) leave `mandatory = false` — unroutable events
vanish with no trace, which is the defect; (b) a worker-side retry buffer —
makes the worker stateful and contradicts D9; (c) `basic_return` → `fatal()`
with `mandatory = true` — turns a lost event into a lost worker; (d) an
engine-set TTL/cap on the DLQ — silently destroys evidence.

## Consequences

**Positive**

- No outbound event vanishes silently: unroutable → DLQ, failed → counted,
  broker down → counted + unready.
- The reply path is provably independent of the broker.
- Statelessness and the no-storage decision survive intact.

**Negative / costs**

- `mandatory = true` + a DLX republish makes the failure path a second publish,
  which costs a round trip on a rare path.
- Events are still lost during a full broker outage; that is now documented and
  observable instead of invisible.
- The DLQ has no bound, so an unconsumed DLQ grows. Deliberate: growth is an
  alert, not a silent drop.

**Revisit when:** the platform asks the engine to own DLQ retention (that
reopens D-v1-4), or if publish latency at p99 shows the republish path
mattering (then it moves off the request path).

## Notes

- Topology constants already present: `exchange_name`, `dlx_name`, `dlq_name`,
  `dlq_routing_key` in `src/adapter/amqp/publisher.zig`.
- Counters: `fpkg_worker_publish_total{result}`, 
  `fpkg_worker_frames_dropped_total{reason}` (`specs/architecture/observability.md`).
- Chaos scenario for broker outage: Week 11-D3 in the M8 plan.
