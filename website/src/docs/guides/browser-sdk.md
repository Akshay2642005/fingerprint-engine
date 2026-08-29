---
title: "Browser SDK"
description: "Configure the TypeScript browser SDK, collect the 102 signals, read the WorkerReply, and enforce fraud decisions with middleware."
category: "guides"
order: 2
crumbs: ["guides", "browser-sdk"]
---

# Browser SDK

The browser SDK (`@akshay2642005/fingerprint-sdk`) is a hand-written,
dependency-free, ESM-only TypeScript package. Its only job is to **collect
evidence on the browser and ship it to the ingress**. It never computes the
canonical fingerprint: that happens once, server-side, on a stateless Zig
worker. Everything the SDK produces and consumes is documented here.

## Install and configure

Install the package with your package manager:

```bash
npm install @akshay2642005/fingerprint-sdk
```

The package ships a single entry point plus a `dist/` build produced by
`zig build clients:browser`. The build pipeline derives the `FeatureID` and
`FeatureType` tables from the Zig model (the single source of truth), injects
the package version and the configured ingress URL, and runs `tsc`. The
resulting surface is verified to contain no WebAssembly and no fingerprint
computation logic.

Before collecting anything you must tell the SDK where the ingress lives. Use
`configure()` exactly once at application startup:

```ts
import { configure, collect } from '@akshay2642005/fingerprint-sdk';

configure({ ingressUrl: 'https://ingress.example.com/v1/fingerprints' });
```

The `ingressUrl` is resolved, in precedence order, from:

1. The explicit `ingressUrl` passed to `configure()`;
2. The `FINGERPRINT_INGRESS_URL` environment variable (used at build time);
3. The built-in default injected during `zig build clients:browser` via the
   `--ingress-url` option.

The ingress is the HTTP gateway that validates the package, forwards it to a
worker over the FPKG transport, and returns the worker's reply.

## Collecting a package

Call `collect()` to sweep the 102 browser signals, serialize them into a
versioned SignalPackage v2 body, and POST the result to the ingress. The
browser performs **no computation** on the signal evidence beyond packing it;
the canonical fingerprint exists only after a worker has processed the
package.

```ts
import { configure, collect } from '@akshay2642005/fingerprint-sdk';

configure({ ingressUrl: 'https://ingress.example.com/v1/fingerprints' });

const result = await collect();

console.log('package id :', result.packageId); // 16-byte replay identity
console.log('signals    :', result.signalCount); // how many of the 102 collected
console.log('sent       :', result.sent); // ingress accepted (HTTP 2xx)
console.log('reply      :', result.reply); // worker digest, when relayed
```

The returned shape is stable and documented:

| Field | Type | Description |
| ----- | ---- | ----------- |
| `packageId` | `Uint8Array` | 16-byte replay identity used to deduplicate and trace a package. |
| `bytes` | `Uint8Array` | The exact serialized SignalPackage v2 body that was POSTed. |
| `hex` | `string` | Hex-encoded form of `bytes`, for logging or replay. |
| `signalCount` | `number` | Number of signals collected (at most the 102 defined). |
| `sent` | `boolean` | Whether the ingress accepted the package (HTTP 2xx). |
| `reply` | `WorkerReply?` | The worker's reply, present when the ingress relays it. |

The `packageId` matters for **replay identity**: because workers are
stateless and the engine is deterministic, re-processing the same package id
(and the same bytes) must yield the same digest. You can use the id to
deduplicate retries and to correlate a package with entries in your audit logs
or with the AMQP result events emitted downstream.

### Inspecting the bytes

If you need to log or reproduce a request, keep `bytes` and `hex` around:

```ts
const result = await collect();

// Send the raw bytes somewhere for offline analysis.
await fetch('https://analytics.example.com/raw', {
  method: 'POST',
  body: result.bytes,
});

// Or log a shorter, greppable form.
logger.info('collected fingerprint package', {
  packageId: Array.from(result.packageId).map(b => b.toString(16).padStart(2, '0')).join(''),
  hex: result.hex,
  signals: result.signalCount,
  sent: result.sent,
});
```

## Reading the worker reply

When the ingress relays the worker's reply, `result.reply` is populated. It is
a `WorkerReply` with the following fields:

```ts
type WorkerReply = {
  status: number;            // engine Status value (0 = ok)
  digestHex?: string;        // canonical SHA-256 fingerprint, hex-encoded
  schemaVersion?: number;    // SignalPackage schema version processed
  featureCount?: number;     // number of features present in the package
};
```

| Field | Type | Description |
| ----- | ---- | ----------- |
| `status` | `number` | The engine `Status` byte; `0` means success. Non-zero values are error conditions. |
| `digestHex` | `string?` | The canonical SHA-256 fingerprint digest as a hex string, present on success. |
| `schemaVersion` | `number?` | The schema version the worker accepted; useful if your collector has drifted. |
| `featureCount` | `number?` | How many features the worker decoded from the package. |

The `status` byte is the engine `Status` value. A non-zero status usually
indicates the package was rejected upstream (for example, an unsupported
schema version or a validation failure), and `digestHex` will be absent. In
normal operation `status` is `0` and `digestHex` carries the server-computed
fingerprint:

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

Remember: this digest is authoritative. It was computed by the worker's
`engine.process()`, not by the browser, and it is the value that downstream
fraud and similarity systems key on.

## Fraud-platform middleware

The engine computes; the platform decides. The decision surfaces back through
the SDK's middleware layer, which exposes the blocking state to your
application. Two primitives are available: a push-style callback and a
pull-style gate.

### onSessionBlocked

Register a callback that fires when the fraud platform pushes a
`session.blocked` decision for the current client (for example, over a
WebSocket to the middleware). Use this to react to a block the moment it
arrives:

```ts
import { configure, collect, onSessionBlocked } from '@akshay2642005/fingerprint-sdk';

configure({ ingressUrl: 'https://ingress.example.com/v1/fingerprints' });

onSessionBlocked((decision) => {
  // decision carries the platform's blocking reason.
  UI.notify(`session blocked: ${decision.reason}`);
  analytics.track('session_blocked', decision);
});

await collect();
```

The callback receives a decision object describing why the session was
blocked. Registering it is idempotent and safe to call before the first
`collect()`. Because the middleware maintains the connection to the fraud
platform independently of the collection pipeline, a blocked decision can
arrive at any time after the package is processed.

### assertAllowed

`assertAllowed()` is a synchronous, pull-style gate: it returns the current
blocking decision immediately. It is a **client-side UX gate only** — your
application is still responsible for enforcing the decision server-side. Use
it to short-circuit rendering or actions that should not run for a blocked
session:

```ts
import { configure, collect, assertAllowed } from '@akshay2642005/fingerprint-sdk';

configure({ ingressUrl: 'https://ingress.example.com/v1/fingerprints' });

if (assertAllowed().blocked) {
  renderBlockedPage();
  return; // gate the application flow on the client
}

await collect();
renderApp();
```

`assertAllowed().blocked` is `true` when the session has been blocked by the
fraud platform. Do **not** treat this as a security boundary: it merely keeps
a known-blocked client out of the UI. Authorization decisions must be made and
enforced by the server, never trusted from the browser.

## Full integration example

A complete, defensive integration that configures, collects, relays a reply,
and enforces the fraud decision:

```ts
import {
  configure,
  collect,
  onSessionBlocked,
  assertAllowed,
} from '@akshay2642005/fingerprint-sdk';

configure({ ingressUrl: 'https://ingress.example.com/v1/fingerprints' });

// Gate first: if already blocked, stop before collecting.
if (assertAllowed().blocked) {
  renderBlockedPage();
  // App logic still verifies the decision server-side.
  return;
}

// React to later blockers in real time.
onSessionBlocked((decision) => {
  renderBlockedPage(decision.reason);
});

// Collect and handle the full result shape.
const result = await collect();

logger.info('package collected', {
  id: result.packageId,          // Uint8Array replay identity
  bytes: result.bytes,           // exact wire bytes
  hex: result.hex,               // hex of those bytes
  signals: result.signalCount,   // collected feature count
});

if (!result.sent) {
  logger.warn('ingress did not accept the package');
  return;
}

if (result.reply) {
  logger.info('worker reply', {
    status: result.reply.status,
    digest: result.reply.digestHex,          // canonical fingerprint
    schema: result.reply.schemaVersion,
    features: result.reply.featureCount,
  });
}
```

## Key takeaways

- The SDK **collects and transmits only**; the worker computes the
  fingerprint. See [Concepts](../concepts/determinism.md) for why this split
  is fundamental to the project's guarantees.
- `packageId` is the 16-byte replay identity; `bytes`/`hex` are the exact
  serialized body; `reply` carries the authoritative digest.
- `status === 0` in `WorkerReply` indicates success; a non-zero status means
  the package was rejected upstream.
- `onSessionBlocked` is a push callback; `assertAllowed` is a pull gate.
  Neither is a substitute for server-side enforcement.
- For the byte-level format of what `collect()` sends, read
  [Serialization](./serialization.md). For the transport that carries the
  package to the worker, see [Worker CLI](./worker-cli.md).
