# ADR-006 — Inbound request/response, outbound AMQP events

- **Status:** Adopted (2026-08-07)
- **Rework decisions:** D8, D16, D20

## Context

The original rework plan put RabbitMQ between the browser and the workers.
Reviewing the reference architecture (TigerBeetle uses its own VSR protocol for
every inbound client request; AMQP appears only in CDC as an *outbound* event
publisher), a queue on the inbound path adds latency, reordering, and a broker
dependency to the one path that benefits most from synchronous semantics.

## Decision

- **Remove RabbitMQ from the inbound path.**
- Browser → ingress: HTTP POST of the SignalPackage (`transport.ts`).
- Ingress → worker: **FPKG-framed request/response** over pooled TCP
  connections. Any worker answers any request (stateless engine — no ordering,
  no affinity).
- Worker → Go fraud platform: **AMQP events** (FingerprintComputed, RiskResult,
  SimilarityResult, ValidationResult, Diagnostics) — the durable, at-least-once
  path (publisher confirms, DLQ planned in S5).
- Reliability split: inbound is at-most-once with idempotent client retries; a
  worker crash drops one request and the browser re-POSTs. Outbound is
  at-least-once — fraud events must not be lost.
- AMQP implementation (`src/adapter/amqp/`) follows the reference CDC module:
  generated-style wire tables from the official AMQP 0-9-1 spec, single channel,
  fixed buffers, publisher confirms, heartbeat, connect state machine.
  Reconnect/backoff/DLQ stay in the adapter (v2/S5).

## Consequences

- The engine and worker stay transport-free; RabbitMQ expertise lives in
  `src/adapter/amqp/`.
- The broker is an outbound fan-out point for the fraud platform, not a
  scaling bottleneck for ingestion.
- Live traffic inspection is possible today via
  `zig build scripts -- amqp get` (throwaway queue bound to all 9 result
  routing keys, polling `basic.get`, FPKG decode of each message).
