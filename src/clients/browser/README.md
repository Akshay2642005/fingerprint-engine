# @akshay2642005/fingerprint-sdk

Browser signal collection SDK for [Fingerprint Engine](https://github.com/Akshay2642005/fingerprint-engine).

The browser **never computes the canonical fingerprint**. This SDK collects browser
signals, serializes them into a versioned `SignalPackage` v2 body, and ships them to
your fingerprint ingress. Distributed workers validate, normalize, hash, and score the
package server-side; the fraud platform decides, and this SDK can surface that decision
back to your UI via a WebSocket.

```
Browser → Collectors → SignalPackage v2 → Ingress → Workers → Fraud platform
```

## Features

- **102 signal collectors** — navigator, screen, canvas, WebGL, audio, fonts, storage,
  network, locale, battery, media, speech, permissions, capabilities, input, metadata.
- **Versioned wire format** — binary SignalPackage v2 body with replay identity
  (`package_id`), `sdk_version`, and `collected_at` preserved on the wire.
- **Deterministic packaging** — serializer mirrors the engine's binary codec byte-for-byte
  (cross-checked by a golden parity test in CI).
- **Integrity headers** — every request carries `x-fpkg-*` metadata plus a SHA-256
  integrity digest of the package body.
- **Session decision gate** — `assertAllowed()` / `onSessionBlocked()` surface the fraud
  platform's `session.blocked` push decisions as a client-side UX gate.
- **No dependencies** — zero runtime npm dependencies; ESM only.

## Install

```sh
npm install @akshay2642005/fingerprint-sdk
```

## Quick start

```ts
import { configure, collect } from "@akshay2642005/fingerprint-sdk";

// Point the SDK at your ingress (optional — see Configuration).
configure({ ingressUrl: "https://ingress.example.com" });

// Collect signals, package them, and ship them to the ingress.
const result = await collect();

console.log(result.sent); // true when the ingress accepted the package
console.log(result.signalCount); // number of signals collected
```

The ingress URL is injected at build time (`--ingress-url` / `FINGERPRINT_INGRESS_URL`)
and defaults to `http://127.0.0.1:8080`. Call `configure()` before `collect()` to
override it at runtime.

## Session decisions

When your fraud platform can reach the browser over WebSocket, it can push
`session.blocked` decisions to the SDK:

```ts
import { configure, onSessionBlocked, assertAllowed } from "@akshay2642005/fingerprint-sdk";

configure({ wsUrl: "wss://fraud.example.com/session" });

// Show a block screen when the platform flags the session.
const unsubscribe = onSessionBlocked((decision) => {
  console.log("blocked:", decision.reason);
});

// Read the last-known decision at any time.
if (assertAllowed().blocked) {
  // client-side UX gate — the application enforces the real policy.
}
```

> The decision gate is a UI convenience only. Server-side enforcement is the
> application's responsibility.

## Collect options

All signal groups are enabled by default. Disable noisy or permission-gated groups:

```ts
await collect({ enableCanvas: false, enablePermissions: false });
```

Available options: `enableCanvas`, `enableWebGL`, `enableAudio`, `enableFonts`,
`enableBattery`, `enableMedia`, `enableSpeech`, `enableInput`, `enablePermissions`.

## TypeScript

The package ships its own type declarations (`dist/index.d.ts`) and is ESM-only with
NodeNext-style resolution, so every import carries a `.js` extension.

## Development

The package is built by the Zig build system; do not hand-edit `dist/`:

```sh
zig build clients:browser   # tsc + generated tables + dist surface guard
npm test --prefix src/clients/browser
```

## License

MIT
