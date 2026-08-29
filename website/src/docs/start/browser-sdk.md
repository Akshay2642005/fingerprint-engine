---
title: "Browser SDK"
description: "Install and configure the TypeScript browser SDK, collect the 102 signals, read the WorkerReply, and enforce fraud-platform decisions."
category: "start"
order: 2
crumbs: ["start", "browser-sdk"]
---

# Browser SDK

The browser SDK (`@akshay2642005/fingerprint-sdk`) is a hand-written,
dependency-free, ESM-only TypeScript package. Its only job is to **collect
evidence on the browser and ship it to the ingress**. It never computes the
canonical fingerprint — that happens once, server-side, on a stateless Zig
worker.

This page is the practical getting-started path. For the full field tables and
the byte-level contract, see [Guides: Browser SDK](../guides/browser-sdk.md).

## Install

```bash
npm install @akshay2642005/fingerprint-sdk
```

## Configure the ingress URL

Call `configure()` exactly once at application startup. The `ingressUrl` is
resolved, in precedence order, from:

1. The explicit `ingressUrl` passed to `configure()`;
2. The `FINGERPRINT_INGRESS_URL` environment variable (used at build time);
3. The built-in default injected during `zig build clients:browser`.

```ts
import { configure, collect } from '@akshay2642005/fingerprint-sdk';

configure({ ingressUrl: 'http://localhost:8080/v1/fingerprints' });
```

When the stack runs locally (see [Local quickstart](./quickstart.md)), the
ingress is on `http://localhost:8080/v1/fingerprints`. In production, point this
at your deployed ingress host.

## Collect a package

Call `collect()` to sweep the 102 browser signals, serialize them into a
versioned SignalPackage v2 body, and POST the result to the ingress:

```ts
const result = await collect();

console.log('package id :', result.packageId); // 16-byte replay identity
console.log('signals    :', result.signalCount); // how many of the 102 collected
console.log('sent       :', result.sent); // ingress accepted (HTTP 2xx)
console.log('reply      :', result.reply); // worker digest, when relayed
```

The returned shape is stable:

| Field | Type | Description |
| ----- | ---- | ----------- |
| `packageId` | `Uint8Array` | 16-byte replay identity used to deduplicate and trace a package. |
| `bytes` | `Uint8Array` | The exact serialized SignalPackage v2 body that was POSTed. |
| `hex` | `string` | Hex-encoded form of `bytes`, for logging or replay. |
| `signalCount` | `number` | Number of signals collected (at most 102). |
| `sent` | `boolean` | Whether the ingress accepted the package (HTTP 2xx). |
| `reply` | `WorkerReply?` | The worker's reply, present when the ingress relays it. |

`packageId` is the **replay identity**: because workers are stateless and the
engine is deterministic, re-processing the same package id (and the same bytes)
must yield the same digest. Use it to deduplicate retries and to correlate a
package with audit logs or the AMQP result events emitted downstream.

## Read the worker reply

When the ingress relays the worker's reply, `result.reply` is populated:

```ts
type WorkerReply = {
  status: number;            // engine Status value (0 = ok)
  digestHex?: string;        // canonical SHA-256 fingerprint, hex-encoded
  schemaVersion?: number;    // SignalPackage schema version processed
  featureCount?: number;     // number of features present in the package
};
```

```ts
if (result.reply) {
  if (result.reply.status === 0) {
    console.log('fingerprint :', result.reply.digestHex);
    console.log('schema      :', result.reply.schemaVersion);
    console.log('features    :', result.reply.featureCount);
  } else {
    console.warn('worker rejected package with status', result.reply.status);
  }
}
```

The `status` byte is the engine `Status` value; `0` means success and
`digestHex` carries the server-computed fingerprint. A non-zero status means the
package was rejected upstream (e.g. unsupported schema version).

## Enforce fraud decisions

The engine computes; the platform decides. Two client-side primitives expose the
blocking state to your application:

### `onSessionBlocked` — push callback

```ts
import { configure, collect, onSessionBlocked } from '@akshay2642005/fingerprint-sdk';

configure({ ingressUrl: 'http://localhost:8080/v1/fingerprints' });

onSessionBlocked((decision) => {
  UI.notify(`session blocked: ${decision.reason}`);
});

await collect();
```

### `assertAllowed` — pull gate

`assertAllowed()` is a **client-side UX gate only** — your server is still
responsible for enforcing the decision:

```ts
import { configure, collect, assertAllowed } from '@akshay2642005/fingerprint-sdk';

configure({ ingressUrl: 'http://localhost:8080/v1/fingerprints' });

if (assertAllowed().blocked) {
  renderBlockedPage();
  return; // gate the UI; server must also enforce
}

await collect();
renderApp();
```

## Next steps

- [Local quickstart](./quickstart.md) — run the stack and send your first package.
- [Ingress](./ingress.md) — where this POST actually lands.
- [Guides: Browser SDK](../guides/browser-sdk.md) — full integration example and middleware reference.
- [Guides: Serialization](../guides/serialization.md) — the exact bytes `collect()` sends.
