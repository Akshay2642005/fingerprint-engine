---
title: "Signals"
description: "The 102 signals across 21 categories, how they are collected non-identifyingly, and hashed deterministically."
category: "concepts"
order: 4
crumbs: ["concepts", "signals"]
---

# Signals

The fingerprints the engine produces are built from **102 individual
browser signals**, organised into **21 categories**. A *signal* is a single,
typed, observed value — the screen width, the canvas digest, the set of
supported codecs, the battery level. A *fingerprint* is the deterministic
digest derived from the ordered, canonicalised concatenation of those
signal hashes.

This page describes what those signals are, how they are grouped, and the
two properties that make the collection safe and the computation
deterministic: signals are collected **non-identifyingly**, and they are
hashed **deterministically**.

## The 21 categories

Each signal belongs to exactly one category. Categories group signals by
the browser surface they come from, not by how they are used; the engine
consumes category metadata to reason about coverage and weighting, but the
hashing contract is per-signal and category-independent.

| Category | Signals | What it captures |
| -------- | :-----: | ----------------- |
| Navigator | 10 | `userAgent`, language, vendor, product, app name/version, cookie and Do Not Track settings, PDF viewer |
| Screen | 12 | Width/height, available geometry, colour and pixel depth, device-pixel ratio, viewport and outer dimensions, orientation |
| Hardware | 6 | CPU class/cores/architecture, platform architecture, hardware acceleration, touch support, device RAM |
| Canvas | 1 | SHA-256 digest of a rendered canvas (single high-weight digest) |
| WebGL | 7 | Vendor, renderer, version, extensions, parameters, shader precision, and a hashed WebGL fingerprint |
| Audio | 1 | SHA-256 digest of rendered audio (oscillator fingerprint) |
| Fonts | 1 | SHA-256 digest of an installed-fonts enumeration |
| Platform | 10 | OS identifier/version plus CSS, service-worker, input, and feature-support flags |
| Storage | 5 | Availability of `localStorage`, `sessionStorage`, IndexedDB, Cache API, cookies |
| Permissions | 4 | Notification, geolocation, camera, microphone permission *status* |
| Media | 6 | Audio/video input/output device lists, supported codecs, media and audio formats |
| Network | 5 | Connection type, downlink, effective type, RTT, save-data preference |
| Locale | 2 | Browser locale, default date/time format locale |
| Timezone | 2 | IANA timezone identifier, UTC offset |
| Battery | 3 | Charge level, charging flag, time-to-full |
| MediaCapabilities | 3 | Decode and encode capability, HDR support |
| Crypto | 2 | Web Crypto and SubtleCrypto availability |
| Speech | 1 | Available speech-synthesis voices |
| GPU | 3 | Vendor, renderer, driver version |
| Performance | 3 | Concurrency and device-memory via the performance API, timer precision |
| Metadata | 3 | Schema version, SDK version, collection timestamp |

The full per-signal registry (IDs, types, weights, flags) is defined once in
the Zig model (`src/model/`) and is the **single source of truth**: the
TypeScript SDK's `FeatureID`/`FeatureType` tables are generated from it, so
browser and engine always agree on the shape of a package.

## Collecting non-identifyingly

The principle governing collection is: **a signal should be a derived,
capability-oriented observation, never a store of personal data.** Three
rules make this concrete.

### 1. Capability and configuration, not content

The engine collects *what the device can do* and *how it is configured*, not
*what it contains*. It reads the list of speech voices, not recordings; the
set of supported codecs, not media streams; the presence of cameras and
microphones as permission status, not as live streams. This is the line
between a fingerprint and surveillance, and it is non-negotiable (see
[Trust & Privacy](./trust-privacy.md) for the full explicit list of what is
never collected).

### 2. Digest-in-the-client for render-derived signals

A handful of signals derive from *rendering outputs* — canvas, WebGL, audio,
and font enumeration. The raw rendering output would be voluminous, and in
the case of font enumeration it would reveal the fine-grained set of
installed fonts. Rather than transmit that raw expression, the **collector
hashes it in the browser** to a fixed-size digest and ships only the digest:

```ts
// Collector pattern — render, then reduce to a digest client-side.
const digest = await hashRenderedOutput(securityToken, () => {
  const ctx = canvas.getContext('2d')!;
  drawProbe(ctx);
  return ctx.getImageData(0, 0, probeWidth, probeHeight).data;
});

signals.push({ id: FeatureID.CanvasHash, type: FeatureType.Bytes, value: digest });
```

Sending the render hash instead of the pixels keeps the transmitted payload
small and removes the most sensitive raw artefact from the wire. The change
from "give the server the image" to "give the server a digest of the image"
is what makes these signals defensible.

### 3. Honest failure and degradation

Modern browsers increasingly reduce or block values for sensitive APIs,
and lightweight environments (private windows, headless agents) simply hide
them. The collectors treat this as a first-class outcome: a signal that
could not be obtained is reported as *missing* or *degraded*, never as a
fabricated value, and the package marks the reduced coverage. This honesty
is what lets the engine's risk model see a *genuinely minimal device*
through the lens of *missing features and entropy deficit* rather than being
fooled by a forged normal value.

## Hashing deterministically

The browser does **not** compute the fingerprint — it only provides
signal *values*. The digest is produced by the deterministic engine. The
hashing procedure is fixed and canonical:

1. **Hash metadata** — schema version, SDK version, collection timestamp.
2. **Sort features** by `FeatureID` — the byte order is canonical
   regardless of collection or arrival order.
3. **Hash each feature** — type tag + feature ID + value hash, using the
   type-correct encoding (Boolean as `u8`, Integer as `i64`, Float as a
   `u64` bitcast, String/Bytes as length-prefixed bytes, arrays as
   count-prefixed elements).
4. **Combine** — concatenate the individual hashes in sorted order and
   compute the final SHA-256.

```zig
var hasher = core.hashing.Hasher.init(schema_version, sdk_version, collected_at);
const sorted = sortById(features);          // canonical order
for (sorted) |f| try hasher.add(f.id, f.value);
hasher.final(&digest);
```

Because hashing consumes a canonical byte stream with no clock and no
randomness, the same signal package yields the same digest on any platform —
the determinism invariant described in [Determinism](./determinism.md). The
browser-side serializer mirrors this encoding byte-for-byte (verified by a
TS↔Zig golden parity test), so the bytes the browser POSTs are exactly the
bytes the engine hashes.

## How the engine uses signals

- **Hashing** — produces the canonical fingerprint digest from all signals
  (see above).
- **Similarity** — compares fingerprints feature-by-feature, weighting each
  signal by its metadata weight (see [Scoring](./scoring.md)).
- **Risk** — reasons over signal coverage: which signals are missing, which
  violate expected bounds, and how much entropy the overall package carries
  (see [Scoring](./scoring.md)).
- **Validation/normalization** — checks each signal's type and bounds
  against its `FeatureDefinition` before any computation proceeds.

The signal set is versioned with the schema. Changing what is collected,
renaming a signal, or altering a value type is a **breaking change** to the
byte-level contract, gated by the versioning and the golden-fixture replay
tests.

## A note on weights

Each signal carries a metadata *weight*. Rendering-derived signals (canvas,
WebGL, audio, fonts) carry the highest weights because they are the most
discriminating and the hardest to spoof; configuration signals (screen,
language, OS) are lighter; metadata signals (schema/SDK version, timestamp)
carry weight zero because they describe the package, not the device. These
weights drive similarity and entropy but are **not** part of the hash input —
two otherwise-identical packages always hash identically regardless of
weight changes, which keeps digest stability independent of scoring tuning.

See [Scoring](./scoring.md) for how these signals and weights become risk,
entropy, and similarity scores, or
[Trust & Privacy](./trust-privacy.md) for the boundary around what signals
are permitted to exist at all.
