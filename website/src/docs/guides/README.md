---
title: "Guides"
description: "Practical walkthroughs for the browser SDK, wire serialization, Docker Compose deployment, and the worker CLI."
category: "guides"
order: 1
crumbs: ["guides"]
---

# Guides

These guides walk through the concrete, day-to-day tasks of running the
Fingerprint Engine end to end: equipping a web app with the browser SDK,
understanding the exact bytes that cross the wire, launching the full stack
locally, and operating the stateless worker containers.

The engine follows a strict three-party split. The **browser collects** signal
evidence, the **worker computes** the canonical SHA-256 fingerprint, and the
**fraud platform decides** what to do with it. These guides assume you grasp
that division of labor; if you are new to the project, read
[Architecture](../architecture.md) and [Start](../start.md) first.

## How the guides fit together

Each guide answers a distinct operational question, and together they form a
single end-to-end thread that begins on a user's browser and ends in a
stateless worker container:

1. **Browser SDK** — how client-side code collects the 102 signals, ships them
   to the ingress, and surfaces the fraud platform's blocking decisions. This
   is the only surface a typical web application integrates directly.
2. **Serialization** — the exact wire formats underneath: the `FNGR`
   SignalPackage v2 body the SDK produces and the `FPKG` envelope that carries
   it between the ingress and the worker. Read this when you must debug bytes,
   implement a compatible client, or reason about replay identity.
3. **Docker Compose** — how to stand up RabbitMQ, the worker, and the ingress
   together and let them discover one another by container name. This is the
   fastest route to a working end to end deployment.
4. **Worker CLI** — the full flag surface of the worker executable and how
   inbound FPKG message types map to engine operations. Read this when you
   operate, tune, or debug worker containers.

The thread flows in order: a web app configured by the Browser SDK guide
POSTs a package that the Serialization guide describes, the package is
processed by a worker started with the flags in the Worker CLI guide, and the
whole thing is stood up by the Docker Compose guide. No guide depends on
another one being read first, but reading them in this order tracks the actual
runtime path of a fingerprint.

## The guides

| Guide | What you will learn |
| ----- | ------------------- |
| [Browser SDK](./browser-sdk.md) | Configure the TypeScript SDK, call `collect()`, and enforce fraud-platform decisions with the middleware. |
| [Serialization](./serialization.md) | The SignalPackage v2 body, the FPKG envelope frame, and the binary vs JSON codecs — byte for byte. |
| [Docker Compose](./docker-compose.md) | Bring up RabbitMQ, the worker, and the ingress with a single `docker compose up`. |
| [Worker CLI](./worker-cli.md) | Every flag of the `worker` executable, plus how the combined `fingerprint` binary dispatches subcommands. |

## Suggested reading order

If you want the fastest end-to-end result, start with
[Docker Compose](./docker-compose.md) to get the stack running, then return to
[Browser SDK](./browser-sdk.md) to send your first package. If you are
debugging a wire-level issue or implementing a compatible client, go straight
to [Serialization](./serialization.md). The [Worker CLI](./worker-cli.md)
guide is the reference for anyone operating or tuning stateless worker
containers.

## Related documentation

- [Concepts](../concepts/determinism.md) — why the browser never computes the
  fingerprint and how determinism is preserved across platforms.
- [Reference: API](../reference/api.md) — the full field tables and engine
  operations.
- [Start](../start.md) — a five-minute installation and first-collection
  walkthrough.
- [Architecture](../architecture.md) — the layered module graph that the
  guides' deployment steps stand up at runtime.

Each guide is self-contained, but they intentionally cross-reference one
another with relative links so you can follow the thread from collection to
computation to deployment without ever leaving the documentation. There is no
native SDK and no C ABI — everything described here flows through the HTTP
ingress and the FPKG-framed worker transport.

## A note on determinism

Every guide in this section operates under a single governing property: the
engine is deterministic. The same SignalPackage body, processed the same way,
yields the same SHA-256 digest on any platform and in any number of stateless
worker replicas. This is why the browser is never trusted to compute a
fingerprint, why the SDK and the Zig serializer are parity-tested to produce
identical bytes, and why the guides consistently point back to byte-exact
serialization and stable operation semantics. Anything in these guides that
appears to vary — transports, brokers, addresses — is infrastructure, not
algorithm. The computation it carries is invariant.
