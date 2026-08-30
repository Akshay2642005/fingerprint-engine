---
title: "AMQP Topology"
description: "The RabbitMQ topology: the durable fingerprint exchange, result.<message-type> routing keys, publisher confirms and persistent delivery, the dead-letter system, and draining the DLQ."
category: "operating"
order: 3
crumbs: ["operating", "amqp-topology"]
---

# AMQP Topology

The worker's outbound AMQP adapter (`src/adapter/amqp/`) owns the broker
topology end to end: the exchange name, the routing-key scheme, message
durability, and the dead-letter system. The worker itself stays
transport-agnostic—it hands whole FPKG reply frames to
`Publish.publish_reply`, and the adapter decides where they go. The fraud
platform is a consumer of this topology; everything described here is part
of the contract it consumes.

## The `fingerprint` exchange

Every worker publishes to one exchange:

- **Name:** `fingerprint`
- **Type:** `direct`
- **Durability:** durable — the exchange and its queues survive broker
  restarts (declared idempotently on every worker connect)
- **Declared by:** the worker publisher, on connect. Declaring is
  idempotent, so N workers racing to connect all converge on the same
  single exchange.

Because the exchange is `direct`, routing is exact-key: each binding matches
only its precise routing key. A consumer that wants every fingerprint result
binds the exact key `result.fingerprint-result`; a consumer that wants a
category binds each key it cares about individually.

## Routing keys: `result.<message-type>`

Every published message's routing key is the literal prefix `result.` plus
the kebab-case wire name of the FPKG frame's message type. The names are
generated at compile time from the `FrameHeader.MessageType` enum, so the
wire keys can never drift from the frames the worker sends.

| Message type | Routing key | Engine result payload |
| ------------ | ----------- | --------------------- |
| `signal_package` | `result.signal-package` | packaged/normalized body |
| `validation_result` | `result.validation-result` | validation warnings |
| `normalization_result` | `result.normalization-result` | normalized features and warnings |
| `fingerprint_result` | `result.fingerprint-result` | `status` + 32-byte digest + feature count + schema version |
| `risk_result` | `result.risk-result` | risk score and flags |
| `similarity_result` | `result.similarity-result` | 0.0–1.0 similarity score |
| `entropy_result` | `result.entropy-result` | Shannon entropy |
| `diagnostics` | `result.diagnostics` | engine diagnostics |
| `fingerprint_computed` | `result.fingerprint-computed` | computed-event payload |

In practice the keys you will see most are `result.fingerprint-result` (the
canonical hash path, produced for every `signal_package` request) alongside
`result.risk-result`, `result.entropy-result`, and `result.similarity-result`
when those operations are requested.

## Message shape

One worker reply frame becomes exactly one published message:

- **Body:** the complete FPKG frame—the fixed 48-byte little-endian header
  (`FPKG` magic, envelope version, message type, codec, payload length,
  SHA-256 integrity) followed by the raw payload. A consumer can verify
  frame integrity without sharing any framing code.
- **Content type:** `application/octet-stream` (an FPKG frame is opaque
  bytes).
- **Delivery mode:** `persistent` — the broker writes the message to disk
  and survives restarts.
- **Timestamp:** broker-side publish time.
- **Headers:**
  - `fpkg-message-type` — the kebab-case wire name (same value as the
    routing-key suffix).
  - `fpkg-envelope-version` — the FPKG envelope version (currently `1`).

A fraud-platform consumer therefore gets, per event: a stable routing key, a
self-describing envelope version, a message-type header, and a body whose
integrity it can check against its own SHA-256.

## Publisher confirms

On connect, the worker's client issues `confirm_select` and waits for
`confirm_select_ok`—publisher confirms are always enabled. (The client's
properties advertise this capability in the broker handshake.)

Every `publish_reply` is *synchronous*: the worker blocks until the broker
acknowledges the message with a delivery-tag-confirmed `basic_ack`, or the
connection errors. Consequences:

- A log line `worker: publish confirmed` means the broker accepted and
  persisted the message, not merely that it was written to a socket.
- Network failures surface as `publish dropped: <error>` warning lines and
  the frame is dropped—the v1 policy is to keep serving page traffic rather
  than block on an unavailable broker. The broker's durability plus the
  supervisor's restart policy cover the gap.
- Protocol violations (a broker that misbehaves at the framing layer) are
  treated as fatal and exit the worker process for the supervisor to
  restart. A worker container never half-serves with a broken publisher.

## Dead-lettering: `fingerprint.dlx` and `fingerprint.dlq`

The worker publisher declares the dead-letter topology on connect, beside
the result exchange:

| Object | Name | Type / attributes |
| ------ | ---- | ----------------- |
| Dead-letter exchange | `fingerprint.dlx` | `direct`, durable |
| Dead-letter queue | `fingerprint.dlq` | durable, bound to `fingerprint.dlx` under the routing key `dead-letter` |

Result queues declared *by consumers* opt into dead-lettering with the
queue argument `x-dead-letter-exchange=fingerprint.dlx`. When the broker
considers a message failed or rejected on such a queue—negative
acknowledgement without requeue, expiry, or queue overflow—it routes the
message through `fingerprint.dlx` into `fingerprint.dlq`.

The DLQ is a deliberate, durable graveyard, not a mystery drawer: messages
accumulate there until an operator drains them, which makes it the correct
place to look first when the fraud platform reports missing events.

## Inspecting the topology

Three `zig build scripts` subcommands use the real worker publisher
(literally the same connect + declare + confirm path the worker uses), so
what they report is what the worker would produce.

### Round-trip smoke test

```bash
zig build scripts -- amqp [--address=host:port]
```

Connects (default `127.0.0.1:5672`), declares the `fingerprint` exchange,
binds a throwaway queue to `result.fingerprint-result`, publishes a reply
frame through the worker publisher, and verifies it comes back
byte-identical. Prints `amqp: PASS` and exits 0. A fast answer to "is the
broker reachable and the topology intact?"

### Live traffic inspector

```bash
zig build scripts -- amqp get [--address=host:port] [--count=N] [--timeout-ms=N] [--quiet]
```

Binds a throwaway exclusive queue to **all** nine routing keys, then polls
the broker with `basic.get`. Each message is decoded as an FPKG frame and
printed: message type, codec, payload size, integrity verdict, and—for
fingerprint results—status, digest, feature count, and schema version.
Messages are consumed as read. Defaults to polling until a 10-second
timeout; `--count=N` stops after N messages, `--timeout-ms=0` polls forever,
and `--quiet` suppresses the AMQP client's connection chatter.

Use this to confirm a specific event actually crossed the wire, or to sample
the distribution of frame types in production.

## Draining the DLQ

Messages in `fingerprint.dlq` are consumed in read order by:

```bash
zig build scripts -- amqp dlq [--address=host:port] [--count=N] [--timeout-ms=N] [--quiet]
```

Each message is decoded and printed exactly like `amqp get` (message type,
integrity, status, digest), and **consumed as it is read**—draining the DLQ
is a destructive acknowledgement, not a peek. By default it drains whatever
is queued up to a 10-second window; bound it with `--count=N` to drain
exactly N messages, or `--timeout-ms=0` to run until the queue is empty.

When the stack is running under `docker compose`, RabbitMQ publishes port
5672 to the host, so the default address works from the repository root:

```bash
zig build scripts -- amqp dlq --address=127.0.0.1:5672
```

A drained message is lost—the command prints its full frame summary first,
so capture that output if you intend to replay the failed event. Any printed
`digest`, `status`, and integrity verdict is exactly what the worker
produced, which makes the DLQ both the failure signal and the reproduction
input. See [Concepts: Determinism](/docs/concepts/determinism/) for why that
makes DLQ events reproducible without the original browser.

## Operational summary

- One exchange, one durable boundary: `fingerprint` (direct).
- Exactly-once routing identity per event: `result.<message-type>`,
  kebab-case, compile-time-derived.
- No loss on publish: persistent delivery + publisher confirms that block
  until the broker acknowledges.
- No silent loss on final failure: `fingerprint.dlx` → `fingerprint.dlq`,
  drained with `zig build scripts -- amqp dlq`.
- The same code path says PASS in the smoke test that the production worker
  uses to publish.

Next: [Monitoring](/docs/operating/monitoring/) covers wiring the worker's log stream to
your observability stack and verifying each hop of the pipeline, including
the AMQP events described here.