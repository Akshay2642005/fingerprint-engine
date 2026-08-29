---
title: "Trust & Privacy"
description: "What is never collected, consent and graceful degradation, and why the SDK only gates UX while the app enforces."
category: "concepts"
order: 5
crumbs: ["concepts", "trust-privacy"]
---

# Trust & Privacy

A system that derives a persistent, hard-to-revoke identifier from a
visitor's browser carries a serious privacy responsibility. The Fingerprint
Engine treats this as an explicit design constraint, not an afterthought:
the collection surface is deliberately small, the sensitive derivation is
kept server-side, and the SDK's only "decisionive" surface — the blocking
UI — is explicitly non-authoritative.

The guiding stance throughout is **privacy by design**: privacy is not a
laundry list of features bolted on at the end, but is engineered into where
the boundaries are drawn, what bytes are allowed to exist, and who is
allowed to make a decision.

## What is explicitly never collected

There is a hard, enumerated boundary on what the SDK will read, transmit,
or store. These are categories the collectors never touch — by
construction, not by hope:

- **No personal identifying information (PII).** No name, email, phone
  number, username, or account identifier is ever read. The SDK has no
  concept of the user behind the device.
- **No IP address and no geolocation data.** The engine does not consume or
  store IP addresses, and geolocation is read only as a *permission status*
  (whether the user has granted, denied, or not yet decided), never as a
  position fix.
- **No camera or microphone streams.** Video and audio are observed only as
  *capability and permission* signals — the list of devices and the
  permission state. No frames, no samples, no recordings ever leave the
  device.
- **No browsing history.** Nothing about the pages visited, the links
  clicked, or the referrer chain is collected.
- **No cookie contents.** Only the coarse *availability* of cookies (and
  whether they are enabled) is recorded; the actual cookie jar is never
  read.
- **No file system access.** No local files are read, listed, or hashed.
- **No credentials.** No passwords, tokens, or authentication material is
  touched; the Crypto and storage signals are purely capability booleans.

```ts
// This is the shape of a privacy-conservative collector:
// a derived, capability-oriented observation, never content.
function collectCameraPermission(): Signal {
  // reads the permission STATUS, not a stream
  return { id: FeatureID.CameraPermission, type: FeatureType.String,
           value: navigator.permissions.query({ name: 'camera' }).state };
}
```

When a signal *would* require reading something sensitive (rendering pixels
or font enumeration), the collector reduces it to a fixed-size digest
client-side before transmission, so only a hash — not the raw expression —
ever leaves the device (see [Signals](./signals.md)).

## Why these boundaries exist

The collection surface is the part of the system that operates in the
visitor's environment, on their machine, reading their browser state. It is
therefore the part a privacy review, a regulator, or a cautious developer
will scrutinise first. Keeping it minimal and capability-oriented achieves
three things:

1. **Defensibility.** If the question is "is this surveillance?", the answer
   is credibly "no" because the collected data is derived configuration,
   not content — and the explicitly-non-collected list above is a
   guarantee, not an aspiration.
2. **Attack-surface reduction.** Less sensitive data collected means less
   sensitive data that can leak, be exfiltrated by a compromised page, or
   be demanded by an adversary.
3. **Portability.** Remaining a capability probe rather than a data
   collector keeps the SDK compliant across jurisdictions whose rules on
   personal data differ, because it is not handling personal data in the
   first place.

## Consent and degradation

The engine is designed to work without ever being *granted* fine-grained
permissions, which keeps consent obligations proportionate.

- **The SDK never requests access to camera, microphone, or location.**
  The permission *signals* it reads are the current, already-decided
  states; it never triggers a permission prompt and never accesses the
  underlying APIs. This keeps collection out of the "consent-required"
  tier for the most sensitive hardware.
- **Cookie-only / privacy browsers.** Where a browser blocks or
  significantly reduces the fingerprinting surfaces (canvas, WebGL, audio,
  battery), the SDK degrades gracefully: affected signals are reported as
  missing or degraded rather than fabricated, and the package records the
  reduced coverage. The system continues to function with fewer signals.
- **Derived, not personal, data.** Because the engine operates on derived
  characteristics rather than personal information, its consent posture is
  weaker than a system that processes PII. The remaining obligation is
  transparency and data minimisation, which this boundary delivers by
  construction.

Degradation is transparent to the *platform*: it sees the coverage, and the
risk model incorporates coverage and entropy deficits into its assessment
(see [Scoring](./scoring.md)). A visitor in a hardened browser should not
be penalised as a fraudster *because* they hardened the browser; rather,
the reduced coverage lowers the confidence of any decision, which is the
honest and privacy-respecting outcome.

## The SDK surfaces UX gating only; the app enforces authoritatively

A subtle but critical trust design is the status of the SDK's blocking
behaviour. The fraud platform, running apart from the engine, makes the
authoritative decision to block a session and pushes a `session.blocked`
event back to the SDK over WebSocket. The SDK exposes two helpers:

```ts
// 1. A passive notification channel:
onSessionBlocked((decision) => UI.notify(`blocked: ${decision.reason}`));

// 2. A convenient, but NON-authoritative gate:
if (assertAllowed().blocked) {
  // do NOT treat this as the actual enforcement point
}
```

The intent of `assertAllowed()` and `onSessionBlocked()` is **user-facing
UX**: informing the visitor, updating the UI, preventing them from wasting
their time on a flow that will fail. It is deliberately **not** the
security boundary.

- **The SDK is client-side and therefore untrustworthy.** Anything running
  in the page can be bypassed, patched, or spoofed by the visitor or an
  attacker. A client-side "block" is not enforcement.
- **The application is the authority.** The application owns the backend
  that enforces the platform's decision — denying the action, rejecting the
  request, closing the session — at the point where the action actually
  happens. The SDK's UX gate merely reflects a decision; it never *is* the
  decision.
- **This separation keeps decisions authoritative and ungameable.** Because
  enforcement happens server-side where it cannot be tampered with, the
  protection does not depend on the browser behaving.

The trust model is therefore layered and honest: **collect minimally
(client) → compute deterministically (engine) → decide authoritatively
(platform) → enforce on the server (application) → inform on the client
(SDK UX).** Every layer knows exactly which of those verbs it performs and
which it does not.

## Privacy and determinism together

These properties reinforce each other. Privacy limits what is collected;
determinism and centralised computation ensure the browser never has to
*trust* a digest it produced, and never has to decide anything sensitive
itself. Because the fingerprint is computed server-side from capability
signals, the visitor's device is never a privacy choke-point, and the
engine's computation is transparently auditable (see
[Determinism](./determinism.md)). This dual stance — minimal collection,
pure computation — is the whole of the engine's privacy contract.

For the mechanics of what signals *are* collected and how they are hashed,
see [Signals](./signals.md); for how the collected signals become scores,
see [Scoring](./scoring.md).
