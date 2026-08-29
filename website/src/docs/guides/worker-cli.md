---
title: "Worker CLI"
description: "Reference for the worker executable — transports, publish options, the combined fingerprint binary, and FPKG message-type to engine-operation mapping."
category: "guides"
order: 5
crumbs: ["guides", "worker-cli"]
---

# Worker CLI

The worker is the stateless, deterministic computation container of the
Fingerprint Engine. It receives FPKG-framed messages, runs
`engine.process()`, relays a reply, and optionally publishes result events
over AMQP. This guide is the complete reference for its command-line surface.

## The combined `fingerprint` binary

The worker and the ingress share a single codebase and are both built from a
combined executable: **`fingerprint`**. The combined binary dispatches to a
subcommand based on the first argument:

```
fingerprint worker    <subcommand and flags>
fingerprint ingress    <subcommand and flags>
```

So the worker's container entry point is most often spelled either as a direct
`worker` binary (built standalone via `zig build worker`, shipped in
`deploy/Dockerfile.worker`) or as the `fingerprint worker` subcommand of the
combined binary (built via `zig build fingerprint`). Both spellings are
equivalent: the worker is a thin shell that receives an FPKG frame, handles it
through `engine.process()`, and replies.

The `pointer`-free worker's job fits on one line: frame in → `engine.process()`
→ frame out, with an optional AMQP side effect. It contains no application
business logic.

## Usage

```
worker start --transport=loopback|tcp [--listen=host:port]
             [--publish=none|amqp]
             [--amqp-address=host:port] [--amqp-user=user]
             [--amqp-password=pass] [--amqp-vhost=vhost]
worker version
worker help
```

### Subcommands

| Subcommand | Description |
| ---------- | ----------- |
| `start` | Start the worker with the given transport and optional publish configuration. |
| `version` | Print the worker (and engine) version and exit. |
| `help` | Print usage for the available subcommands and flags, then exit. |

## start: transports

The `--transport` flag selects how the worker receives and replies to FPKG
messages:

| Transport | Value | Use case |
| --------- | ----- | -------- |
| Loopback | `--transport=loopback` | In-memory queues seen in tests, or stdin/stdout pipe framing between processes. Good for local, single-machine experimentation and for the deterministic e2e harness. |
| TCP | `--transport=tcp` | A network FPKG request/response server. This is the production transport used between the ingress and the worker container. |

### --listen

```
--listen=host:port
```

For the TCP transport, `--listen` sets the address the worker binds. The
default is appropriate for localhost operation; in a Docker deployment you
bind the container's external interface so the ingress can reach it — for
example `--listen=0.0.0.0:8080`. See [Docker Compose](./docker-compose.md)
for the container wiring.

For loopback, the listen address is not meaningful (the transport is
in-process or pipe-based), so it is omitted.

## start: publishing results

The `--publish` flag controls whether the worker emits result events after
computing a digest.

| Publish | Value | Behavior |
| ------- | ----- | -------- |
| None | `--publish=none` | Compute and reply only; emit no downstream events. |
| AMQP | `--publish=amqp` | Additionally publish a result event over AMQP 0-9-1 using the `--amqp-*` options. |

With `--publish=amqp`, the worker acts as a synchronous AMQP 0-9-1 client
with publisher confirms. It declares the durable `fingerprint` exchange and
its queue/binding, and publishes result events under routing keys of the form
`result.<message-type>`. Downstream consumers — most importantly the fraud
platform — subscribe to those keys to react to computed fingerprints.

### AMQP options

All of the `--amqp-*` options are only consulted when `--publish=amqp`:

| Flag | Meaning |
| ---- | ------- |
| `--amqp-address=host:port` | The broker host and port. In Compose, this is `rabbitmq:5672` (the service name — see [Docker Compose](./docker-compose.md)). |
| `--amqp-user=user` | The AMQP username. |
| `--amqp-password=pass` | The AMQP password. |
| `--amqp-vhost=vhost` | The virtual host on the broker (often `/`). |

## version and help

```
worker version
worker help
```

- `worker version` prints the build and engine version. This is useful for
  confirming which engine semantics a container ships and for correlating a
  container image with a documented schema version.
- `worker help` prints the full usage block above. Run it before wiring any
  non-default flags to confirm the exact flag names supported by the build you
  are running.

## How inbound FPKG message types map to engine operations

The worker is FPKG-typed: every inbound frame declares a **message type** in
its envelope header (see [Serialization](./serialization.md) for the frame
layout). The worker dispatches on that type at comptime, mapping each type to
a specific engine operation. The mapping is:

| FPKG message type | Engine operation | Description |
| ----------------- | ---------------- | ----------- |
| `signal_package` | `hash` | **The canonical path.** A collected SignalPackage body is deserialized, validated, and hashed to produce the canonical SHA-256 fingerprint. This is the operation the browser SDK's packages exercise by default. |

Other message types drive the remaining engine operations (`validate`,
`normalize`, `entropy`, `similarity`, `risk`, `package`, and the codec
`serialize`/`deserialize` pair), each surfacing through the same
`engine.process()` single entry point. Because the dispatcher is a comptime
dispatch table — never reflection or dynamic dispatch — the mapping from
message type to operation is fully resolved at build time, with no runtime
registration to go wrong.

## The reply payload

Every inbound request produces a reply FPKG frame. The reply payload is a
concatenation of a status byte followed by the engine result:

```
u8 status | engine result
```

| Fragment | Type | Description |
| -------- | ---- | ----------- |
| status | `u8` | The engine `Status` value. `0` means success; a non-zero value signals an error (for example, `unsupported_version` for an unknown schema). |
| engine result | varies | The operation's output — for `signal_package → hash`, the 32-byte SHA-256 digest; for other operations, their respective results. |

This is exactly the shape that surfaces to the browser SDK as a `WorkerReply`.
The `status` byte becomes `WorkerReply.status`, and the digest becomes
`digestHex`. See [Browser SDK](./browser-sdk.md) for how the client consumes
it. An unknown or unsupported schema version is rejected at the engine
boundary and surfaces as a non-zero `status` rather than a malformed digest.

## A complete worker invocation

Bringing it together — a production-style TCP worker that publishes to a
Compose-hosted RabbitMQ:

```
worker start \
  --transport=tcp \
  --listen=0.0.0.0:8080 \
  --publish=amqp \
  --amqp-address=rabbitmq:5672 \
  --amqp-user=guest \
  --amqp-password=guest \
  --amqp-vhost=/
```

This is the command the worker container in
[Docker Compose](./docker-compose.md) runs. To validate a new build of the
engine in isolation without a broker, use the loopback transport and
`--publish=none`.

## Key takeaways

- `fingerprint` is the combined binary; `worker`/`ingress` are subcommands
  that also build standalone.
- `--transport` is loopback (tests/pipes) or tcp (production). `--listen`
  selects the TCP bind address.
- `--publish` is `none` or `amqp`; the `--amqp-*` flags configure the broker.
- `signal_package → hash` is the canonical inbound path; every reply is
  `u8 status | engine result`.
- For the FPKG frame that carries these messages, and the SignalPackage v2
  body they wrap, see [Serialization](./serialization.md).
