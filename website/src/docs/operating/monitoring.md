---
title: "Monitoring"
description: "Observability runbook: structured and flow logging, verifying each hop of the ingestion pipeline, draining the DLQ, and reproducing issues on a deterministic engine."
category: "operating"
order: 4
crumbs: ["operating", "monitoring"]
---

# Monitoring

Every process in the stack—worker, ingress, the combined `fingerprint`
binary, and the automation scripts—logs through one application logger
(`src/log.zig`) to stderr with UTC timestamps. The core algorithms never
log. That single pipeline, plus the engine's determinism invariant, gives
you a complete answer to the three questions that matter in operations:

1. Did the package arrive at the ingress?
2. Did the worker compute and reply?
3. Did the AMQP event publish to the broker?

If all three are answered "yes" for an event and the fraud platform still
shows nothing, the failure is *outside the engine*—in the consumer—and the
deterministic engine gives you the data to prove it.

## Structured logging

Output is one line per event, written to stderr from a fixed-size buffer (no
per-message heap allocation). Two formats:

```text
# text (default) — greppable
2026-08-08T12:00:00Z [info] (worker) worker: job done status=ok

# json — log aggregators
{"ts":"2026-08-08T12:00:00Z","level":"info","scope":"worker","msg":"worker: job done status=ok"}
```

Each line carries a timestamp, a level, a scope, and the message:

| Field | Meaning |
| ----- | ------- |
| `ts` | UTC ISO-8601 (`YYYY-MM-DDTHH:MM:SSZ`) |
| `level` | `err` (0, most severe) through `debug` (3) |
| `scope` | `worker`, `ingress`, `amqp`, `engine`, `pool`, or `scripts` |
| `msg` | the formatted message (`key=value` fields in text mode) |

Levels are filtered at runtime, not compile time, so changing verbosity never
requires a rebuild or a redeploy.

### Configuring verbosity and format

Precedence is **CLI flag → environment → default** (defaults: `info`, text):

```bash
# env vars (containers)
FPKG_LOG_LEVEL=debug FPKG_LOG_FORMAT=json

# CLI flags (win over env)
worker start ... --log-level=debug --log-format=json
ingress start ... --log-level=info  --log-format=json
```

The AMQP client's own `std.log.scoped(.amqp)` output is routed through the
same filter and format via `std_options.logFn`, so a debug-level run shows
broker handshake traffic under the `amqp` scope in the same JSON stream as
everything else. For a production footprint, `info` plus `json` is the
recommended baseline: it includes all flow lines below without the
frame-detail noise.

## Flow logging: the pipeline as a trace

Each hop publishes lifecycle lines at `info` (visible at the default level),
with frame-level detail at `debug`. Reading them in order reconstructs one
request end to end.

### Hop 1 — the ingress: did the package arrive?

```text
(debug) ingress: connection accepted from <peer>
(debug) ingress: POST /v1/fingerprints (content-length 4821) from <peer>   # access line
(info)  ingress: signal received from client, forwarding to worker
```

The access line at `debug` (method + target + content length per peer)
identifies the request; `("signal received from client, forwarding to
worker")` at `info` is the signal that the package passed every boundary
check and entered the worker pool. Rejections never reach that line and log
their cause instead:

```text
warn: ingress: integrity mismatch from <peer>
warn: ingress: unsupported schema version N from <peer>
warn: ingress: request body 2097152 exceeds max 1048576 from <peer>
warn: ingress: chunked transfer from <peer>
warn: ingress: missing content-length from <peer>
```

Liveness probes land as `ingress: healthz probe from <peer>` at `info`, so a
healthy fleet produces a gentle background of healthz lines.

### Hop 2 — the worker: did it reply?

The worker logs one request as a pair of flow lines plus a publish line:

```text
(info) worker: got job type=signal_package
(info) worker: processing job
(info) worker: job done status=ok                 # engine Status name (ok = success)
(info) worker: reply sent to client (type=fingerprint_result)
```

Corruption arrives here as `worker: frame dropped: <error>` (with a warn
line attributing it) so a poisoned frame is visible, not silent. The ingress
closes the loop on the way back:

```text
(info) ingress: worker reply status 0 -> http 200
(info) ingress: reply relayed
```

Together, `worker: job done status=ok`, `worker: reply sent`, and
`ingress: reply relayed` prove the event completed computation and reached
the browser again.

### Hop 3 — the broker: did the event publish?

With `--publish=amqp`, every reply is also published, and the publisher
confirms synchronously before considering the job complete:

```text
(info) worker: publishing reply (type=fingerprint_result) to exchange 'fingerprint' key 'result.fingerprint-result'
(info) worker: publish confirmed
```

`publish confirmed` is the guarantee that the broker accepted and persisted
the message. Its absence, or a `warn: worker: publish dropped: <error>`
line, means that event never reached the exchange. See
[AMQP Topology](/docs/operating/amqp-topology/) for the routing-key and dead-letter
consequences.

### Verifying with the broker directly

The `amqp get` inspector observes the exchange independently of either
component:

```bash
zig build scripts -- amqp get --address=127.0.0.1:5672 --count=1
```

It binds a throwaway queue to all nine `result.*` routing keys, polls the
broker, and prints each event's frame summary (message type, codec, payload
size, integrity verdict, and for fingerprint results: status, digest,
feature count, schema version). Seeing an event here with `publish
confirmed` in the worker log and `reply relayed` in the ingress log is a
third-party confirmation that the full pipeline worked.

## Draining the dead-letter queue

Events that a consumer rejects, that expire, or that overflow a bound queue
route through `fingerprint.dlx` into `fingerprint.dlq` (queue argument
`x-dead-letter-exchange=fingerprint.dlx`). A non-zero DLQ is the first thing
to check when the fraud platform reports gaps:

```bash
zig build scripts -- amqp dlq --address=127.0.0.1:5672
```

Each drained message is printed with its full FPKG summary, then consumed.
Options: `--count=N` to bound the drain, `--timeout-ms=0` to run until the
queue is empty, and `--quiet` to silence connection chatter. Recall that the
RabbitMQ container publishes port 5672 to the host, so this works straight
from the repository root against a running `docker compose` stack. Full
semantics on the [AMQP Topology](/docs/operating/amqp-topology/) page.

## Reproducing issues on a deterministic engine

The engine's core invariant is **same input → same output**, on any platform,
any time: no clock, no randomness, no global state inside the engine. Two
consequences for incident response:

1. **A failure is a property of the input bytes, not the machine.** If your
   production worker produced a suspicious digest, a fresh worker fed the
   same bytes produces the same digest—or fails the same way, on a laptop.
2. **Every published event carries its own reproduction input.** The AMQP
   message body is the complete FPKG frame, and the ingress/worker logs let
   you capture the request side; the DLQ printout gives you both the
   summary and the identity of the failed event.

Concretely:

```bash
# replay the canonical fixture against a worker and cross-check the digest
# against an in-process engine call (mismatch means the worker drifted)
# --listen points at the worker host port (8081 under docker compose)
zig build scripts -- worker request --listen=127.0.0.1:8081

# verify a broker round-trip through the real publisher path
zig build scripts -- amqp --address=127.0.0.1:5672
```

For a production anomaly, capture the offending SignalPackage bytes (the
package ID in the SDK reply is the 16-byte replay identity), reproduce on a
local `docker compose` stack, and compare the digest with the golden fixture
(`tests/fixtures/fingerprints/signal-package-v2.bin`) and with the engine's
own hash of the same bytes. Because the worker e2e tests pin the fixture
digest as a compile-time constant, a division between "the worker agrees
with the engine" and "the engine disagrees with the manifest" tells you
instantly whether the anomaly is in the data, in a code version, or in the
consumer. See [Concepts: Determinism](/docs/concepts/determinism/).

## A monitoring baseline

For a production deployment:

- Run the worker and ingress with `--log-format=json` (or
  `FPKG_LOG_FORMAT=json`) and ship stderr to a log aggregator; `docker
  compose logs -f` is fine for development triage.
- Alert on `warn: publish dropped`, `warn: worker: frame dropped`,
  `warn: ingress: integrity mismatch`, and any worker exit (protocol
  violations are fatal by design, and the supervisor restarts the
  container—that restart should be visible).
- Grabber queue-depth: poll `fingerprint.dlq` depth in the RabbitMQ
  management API and alert on a sustained non-zero depth; then drain per the
  section above.
- Keep `zig build scripts -- amqp` and `zig build scripts -- worker request`
  as post-deploy smoke checks on every change to the message stream.

Return to [Operating](/docs/operating/) for the index, or
[Deployment](/docs/operating/deployment/) to rebuild and redeploy the stack.