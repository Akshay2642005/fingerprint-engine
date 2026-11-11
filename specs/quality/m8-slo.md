# M8 chaos and SLO verification

Status: **verified locally for v0.7.0; remote release checks pending**

This is the operational acceptance record for M8. The engine remains stateless
and the platform owns durable event recovery. These checks prove that the
reply path, readiness signal, metrics, and AMQP failure path behave honestly.

## SLOs

The production target for a single healthy ingress and worker pair is:

| SLO | Target | Evidence |
| --- | --- | --- |
| Successful HTTP collections | 99.9% over 30 days, excluding planned deploy windows | `fpkg_ingress_requests_total` |
| Ingress request latency | p99 ≤ 250 ms at the agreed load profile | `fpkg_ingress_request_duration_seconds` |
| Readiness recovery after broker restore | ready within 10 s of the next collection attempt | `fpkg_worker_ready`, `fpkg_worker_amqp_connected` |
| Primary reply during broker outage | no reply is lost because AMQP is unavailable | HTTP response log and client result |
| Unroutable outbound events | zero silent drops; every one is `unroutable` plus `dlq` or `dlq_failed` | `fpkg_worker_publish_total` |

The latency and availability targets are service objectives, not promises about
the browser or the platform ledger. TLS termination, rate limiting, tenancy,
and ledger durability remain outside this repository.

## Chaos scenarios

Run the stack with `docker compose up -d --build`, send a known-good package
through the ingress, and keep the request body and expected digest available
for comparison.

### Worker death

1. Start a request loop at the agreed load profile.
2. Run `docker compose kill worker`.
3. Confirm `/readyz` becomes non-ready and requests fail or retry during the
   restart window, rather than returning a fabricated success.
4. Confirm the restarted worker becomes ready and the same known-good package
   again produces the pinned digest.

Acceptance: the failure is bounded by the restart window, no process hangs,
and the digest is unchanged after recovery.

### Broker outage

1. Establish a healthy worker and publish one known-good collection event.
2. Run `docker compose stop rabbitmq`.
3. Confirm the worker metrics show `fpkg_worker_amqp_connected 0`, readiness is
   false, and the HTTP reply still completes without an AMQP success log.
4. Run `docker compose start rabbitmq`.
5. Send the next collection and confirm one reconnect attempt restores
   readiness and publishing.

Acceptance: the reply path remains independent of the broker, transport errors
are counted as `failed`, and the first post-restore collection reconnects
without an unbounded retry loop.

### Unroutable publish

With a live broker, publish to an exchange with no bound result queue or use a
test consumer topology that deliberately removes the binding. Confirm the
worker receives `basic.return`, keeps serving, and publishes the original
frame once to `fingerprint.dlx` with routing key `dead-letter`.

Acceptance: `unroutable` and `dlq` each increment once, `acked` does not
increment for the failed primary publish, and the DLQ inspector can read the
frame.

## Observed compose evidence (2026-11-11)

The live compose drill used `tests/fixtures/fingerprints/signal-package-v2.bin`.
During `docker compose stop rabbitmq`, the ingress still returned HTTP 200;
the worker reported `ready=0`, `amqp_connected=0`, and incremented `failed`.
After `docker compose start rabbitmq`, the next collection reconnected without
a worker restart, returned HTTP 200, and restored `ready=1` and
`amqp_connected=1`. With no result binding, RabbitMQ `basic.return` was handled
nonfatally; the worker recorded `unroutable=2`, `dlq=2`, `dlq_failed=0`, and the
management API reported two ready messages in `fingerprint.dlq`.

## Release gate

The deterministic code and unit/integration gates must be green before merge.
The live broker outage and unroutable scenarios must also be exercised in the
deployment environment, because a pure Zig test runner cannot faithfully
simulate broker behavior.
