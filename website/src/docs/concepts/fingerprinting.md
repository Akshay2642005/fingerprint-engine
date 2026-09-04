---
title: "Fingerprinting"
description: "What browser fingerprinting is, why it is used, the trade-offs, and how the Fingerprint Engine approaches it."
category: "concepts"
order: 2
crumbs: ["concepts", "fingerprinting"]
---

# Fingerprinting

Browser fingerprinting is the practice of assembling a set of
characteristics that a web browser and its host device expose to any
website that asks, into a signature that is stable enough to identify a
returning visitor or distinguish one visitor from another. Because those
characteristics are exposed as a matter of normal browser behaviour, a
fingerprint can be formed without installing anything, without a cookie,
and — in the general case — without the visitor doing anything
deliberate.

The Fingerprint Engine treats fingerprinting as an *engineering
discipline* with three responsibilities kept strictly apart. The browser
out of which the fingerprint is formed has no role in computing it, and no
server ever collects data by guessing.

## What a fingerprint actually is

A fingerprint is a *derived* identifier. It is not a device serial number
and it does not come from any single API. It is computed from dozens of
small, individually weak observations:

- what the browser claims about itself (`navigator`, `userAgent`,
  language, platform);
- how the device renders content (canvas, WebGL, audio, fonts);
- what capabilities the platform has (CPU count, memory, media codecs,
  storage APIs, permissions state);
- incidental configuration (timezone, screen geometry, battery state,
  connection characteristics).

None of these signals is identifying on its own. A language string or a
screen width names millions of devices. But the **combination** of many
such signals, especially the rendering-derived ones that depend on subtle
GPU and firmware differences, is remarkably discriminating. That
combination, reduced to a canonical digest, is the fingerprint.

Because the pieces are ordinary browser-provided values, a fingerprint is
resilient in a way a cookie is not: it survives clearing cookies, private
windows, and cross-site journeys, and it cannot be wiped by a `Clear
Site Data` call. That is precisely its value to fraud and bot prevention
— and precisely why it must be handled with care (see
[Trust & Privacy](/docs/concepts/trust-privacy/)).

## Why it is used

The dominant uses are abuse cases where a persistent, hard-to-forge marker
behaves better than any credential the visitor volunteers.

### Fraud detection

In account creation, checkout, payments, and identity verification, an
operator needs to know whether the device in front of them has been seen
before — especially whether it has been seen *failing* before. A
fingerprint lets the fraud platform link a new abusive session to a
previously flagged device even when the visitor has created a fresh
profile, a fresh email address, and cleared their cookies. This is central
to:

- **Synthetic identity** and account-takeover rings reusing a small pool of
  devices;
- **promotion abuse** and multi-accounting, where one person controls many
  accounts;
- **payment fraud**, where a compromised or shared device is cycled across
  many identities;
- **credential stuffing**, where automated tooling replays stolen
  credentials from a fixed set of machines.

### Bot prevention

Automated traffic — scrapers, credential-stuffing scripts, ticket bots,
and signup bots — is frequently run from headless browsers, cloud VM
fleets, and proxied infrastructure. Such environments deviate from ordinary
browser behaviour in measurable ways: GPU stacks are virtualised, fonts are
minimal, audio and canvas rendering differ, and timezone/language
combinations are incongruent. A well-constructed fingerprint makes these
deviations visible as *bound violations*, *missing features*, and
*entropy deficits*, which feed directly into the risk model described in
[Scoring](/docs/concepts/scoring/).

The same signals therefore serve both sides of the problem: they recognise
*known-bad* devices (fraud) and they recognise *abnormally configured*
devices (bots), while letting genuinely ordinary traffic through.

## The trade-offs

Fingerprinting is powerful precisely because it operates at the edge of the
privacy surface. Those trade-offs are real and must be handled explicitly,
not papered over.

- **Persistence vs. privacy.** A fingerprint is hard for the visitor to
  revoke. The more discriminating it is, the more it feels like a durable
  identifier. The design answer is to collect the *minimum minimorum* —
  only derived, non-identifying characteristics — and to never collect
  personal data (see [Trust & Privacy](/docs/concepts/trust-privacy/)).
- **Discrimination vs. stability.** Signals that are highly
  discriminating (canvas/WebGL rendering, fonts) can drift with driver
  updates or OS upgrades, while perfectly stable signals (language, screen
  size) are weakly discriminating. The engine weights features accordingly
  and separates stability from discrimination in its metadata.
- **Browser-specific consent gating.** Modern browsers increasingly
  report *degraded* or *blocked* values for sensitive APIs (battery,
  permissions, media devices) rather than simply the truth. The SDK must
  detect this and communicate it as reduced coverage, not as a lying
  device.
- **Adversarial noise.** An attacker can intentionally perturb signals to
  evade a fingerprint. Treating fingerprinting as a probabilistic, weighted
  signal — not a binary match — is what keeps it useful against evasion.
- **Regulatory exposure.** Because a fingerprint approaches an
  identifier, deploying it triggers consent, transparency, and data
  minimisation obligations. The engine's stance is to keep the sensitive
  derivation server-side and the collection surface minimal.

## How the Fingerprint Engine approaches it

The engine's position on fingerprinting is summarised in a single,
non-negotiable principle:

> **The browser collects. The engine computes. The platform decides.**

### 1. The browser collects

The TypeScript SDK runs in the page and gathers the 102 signals described
in [Signals](/docs/reference/signals/). Every collector emits a *plain* value with an
explicit type — it does **not** attempt to combine or score anything. The
browser has no fingerprinting algorithm, no digest logic, and no
decision-making. Where a raw signal would be too sensitive to transmit
(rendering output, font enumeration), the *collector* hashes it to a fixed
size locally so that only a digest leaves the device.

Even this collection is non-authoritative: the SDK reports what the
browser chooses to expose and transparently marks degraded or unavailable
features. It also surfaces — purely as a UX convenience — a blocking
decision inferred from platform events, but the application is the
authoritative enforcer (see [Trust & Privacy](/docs/concepts/trust-privacy/)).

### 2. The engine computes

The collected signals are packaged into a versioned `SignalPackage` (v2)
and POSTed to the HTTP ingress, which relays them to a stateless Zig
worker. The worker does the real work, entirely server-side:

- **validate** and **normalize** the package against the schema;
- **hash** the features into the canonical SHA-256 fingerprint;
- compute **entropy**,
  **similarity**, and **risk** over the package.

Because this happens in a deterministic, replay-safe worker, the same input
bytes always produce the same output bytes, on any platform. That is
fundamental to trusting the results — see
[Determinism](/docs/concepts/determinism/). The canonical fingerprint is computed
*only* here, never in the browser.

### 3. The platform decides

The worker publishes its results (fingerprint digest, risk, entropy,
similarity inputs) over AMQP to a separate fraud platform. The fraud
platform owns the `jump to the conclusion`: it maps the digest to a known
device, compares it against a similarity neighbourhood, consults its
decisioning rules, and — when a session should be stopped — pushes a
`session.blocked` event back to the SDK over WebSocket.

The engine deliberately does **not** decide. It computes facts; the fraud
platform applies policy. This keeps the engine pure, deterministic, and
_replayable_, while leaving all business judgement where it belongs —
upstream and evolving at the platform's pace, not frozen into the worker.

## The resulting guarantees

Because the responsibilities are split this way, the system gets properties
that a client-side fingerprinting library cannot offer:

- **The fingerprint cannot be forged or misreported by the page.** The
  browser never produces the digest; a malicious script has nothing to
  tamper with server-side.
- **The computation is audit-able and reproducible.** Given the same
  `SignalPackage`, any worker returns the same result, so a disputed
  decision can be replayed and re-examined.
- **Scaling is horizontal and stateless.** Any worker can process any
  package, because nothing depends on local state or a prior call.
- **The collection surface stays small and honest.** The browser's only job
  is faithful collection; everything clever happens where it can be
  controlled, instrumented, and trusted.

This philosophy — collect in the noisy client, compute in the deterministic
server, decide in the policy-owning platform — is the lens through which the
rest of the concepts should be read.
