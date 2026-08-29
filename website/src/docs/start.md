---
title: Start
description: Install the SDK and make your first fingerprint package in under five minutes.
category: start
order: 1
crumbs: ["start"]
---

Fingerprint Engine is a deterministic, distributed browser fingerprinting
engine. The **browser collects** signals, the **engine computes** the
canonical fingerprint, and the **platform decides**. You will learn why this
split matters in [Concepts](./concepts/), but first—let's collect a package.

## Install

The browser SDK is a single, small, dependency-free ESM package:

```bash
npm install @akshay2642005/fingerprint-sdk
```

The engine, worker, and ingress are written in Zig 0.14.1 and shipped as
Docker containers. There is no native SDK and no C ABI.

## Collect your first package

```ts
import { configure, collect } from '@akshay2642005/fingerprint-sdk';

configure({ ingressUrl: 'https://ingress.example.com/v1/fingerprints' });

const result = await collect();
console.log('package id :', result.packageId); // 16-byte replay identity
console.log('signals    :', result.signalCount); // how many of the 102 collected
console.log('sent       :', result.sent); // ingress accepted (HTTP 2xx)
console.log('reply      :', result.reply); // worker digest, when relayed
```

 `collect()` gathers the 102 browser signals, serializes a versioned
SignalPackage v2 body, and POSTs it to the ingress with integrity headers.
The browser **never computes the fingerprint**—that happens once on a
stateless worker.

## Start guides

These pages take you from zero to a running, scaled stack:

- [Local quickstart](./start/quickstart.md) — run RabbitMQ + worker + ingress with one command and send your first package.
- [Browser SDK](./start/browser-sdk.md) — install, configure, collect, and enforce fraud decisions.
- [Ingress setup](./start/ingress.md) — the HTTP gateway: flags, env vars, and the worker pool.
- [Worker setup](./start/worker.md) — transports, AMQP publishing, and running multiple workers.
- [Self-host](./start/self-host.md) — a full compose file with the ingress and three workers.

## Read the reply

When the ingress relays the worker's reply, `result.reply` carries the
fingerprint digest:

```ts
if (result.reply) {
  console.log('digest    :', result.reply.digestHex);
  console.log('schema    :', result.reply.schemaVersion);
  console.log('features  :', result.reply.featureCount);
}
```

The `status` byte is the engine `Status` value (0 = ok). See
[Reference: API](./reference/api/) for the full field table.

## Run the full stack locally

The complete pipeline—RabbitMQ + worker + ingress—runs with one command:

```bash
docker compose up
```

This starts a RabbitMQ broker, the stateless Zig worker (connected to
`rabbitmq:5672`), and the HTTP ingress (connected to `worker:8080`). See
[Operating: Deployment](./operating/deployment/) for details.

## Next steps

- [Concepts](./concepts/) — why the browser/engine/platform split exists
- [Guides](./guides/) — serialization, docker compose, worker CLI
- [Reference](./reference/signals/) — the full 102-signal registry
