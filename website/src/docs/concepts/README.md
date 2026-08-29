---
title: "Concepts"
description: "The core ideas behind the Fingerprint Engine: determinism, signals, trust and privacy, and scoring."
category: "concepts"
order: 1
crumbs: ["concepts"]
---

# Concepts

The Fingerprint Engine is a deterministic, distributed browser
fingerprinting engine. It is not a library that runs in the page, and it is
not a black-box SaaS endpoint either. It is a deliberately architected
pipeline with a clean, uncompromising separation of responsibilities:

> **The browser collects. The engine computes. The platform decides.**

Every page in this section explains one of the ideas that makes that
sentence true and, more importantly, *safe to rely on at scale*.

## What you will learn

By the end of this section you should be able to answer, precisely and
defensibly, the following questions:

- What is browser fingerprinting, why does the industry use it, and what
  are the unavoidable trade-offs?
- Why is *determinism* the engine's core architectural invariant, and how
  does it make distributed scaling and replay safe?
- What are the 102 signals, across 21 categories, and how are they
  collected non-identifyingly and hashed deterministically?
- What is explicitly **never** collected, and how do consent and
  degradation work?
- How do risk, entropy, and similarity turn a pile of raw signals into a
  decision-relevant score?

The pages are intended to be read in order, but each stands alone and links
to its neighbours.

## The pages

| Page | What it covers |
| ---- | --------------- |
| [Fingerprinting](./fingerprinting.md) | What fingerprinting is, why it is used for fraud and bot detection, the trade-offs, and how the engine approaches them. The core philosophy: *browser collects, engine computes, platform decides.* |
| [Determinism](./determinism.md) | Why same input → same output is the architectural invariant: golden-fixture replay tests, no clock and no randomness inside the engine, and the scaling and replay guarantees that follow. |
| [Signals](./signals.md) | The 102 signals across 21 categories — navigator, screen, canvas, WebGL, audio, fonts, battery, media codecs, speech, input, permissions, storage, network and more — and how they are collected non-identifyingly and hashed deterministically. |
| [Trust & Privacy](./trust-privacy.md) | Privacy by design: what is never collected, consent and graceful degradation, and why the SDK only surfaces blocking decisions as UX gating while the application enforces them authoritatively. |
| [Scoring](./scoring.md) | The model that turns signals into judgement: weighted per-feature similarity (0.0–1.0), Shannon entropy, and the risk assessment that combines missing features, bound violations, coverage, and entropy deficit into a score and flags. |

## The thread that runs through all of them

Each page arrives at the same conclusion from a different angle: **the
browser is a hostile, noisy, unreplayable environment, but the engine must
be a calm, deterministic one.**

- [Fingerprinting](./fingerprinting.md) explains *why* we cannot trust the
  browser to do the deciding.
- [Determinism](./determinism.md) explains *how* we guarantee the engine
  never betrays that trust.
- [Signals](./signals.md) explains *what* the engine is given to work with.
- [Trust & Privacy](./trust-privacy.md) explains *where* the boundary
  between what is collected and what is computed is drawn.
- [Scoring](./scoring.md) explains *how* the computed output becomes a
  decision.

## A worked example: a single authentication event

To see the ideas connect, trace one visitor through the whole system. A
person opens a browser, navigates to an application, and the application
asks the SDK to begin a session:

1. **The browser collects.** The SDK reads the 102 signals — navigator,
   screen, canvas digest, WebGL digest, fonts digest, audio digest, and the
   rest — and packages them into a versioned `SignalPackage` v2
   ([Signals](./signals.md)).
2. **The browser stays out of the decision.** It does not compute a
   fingerprint. It POSTs the package to the ingress and waits for events
   ([Fingerprinting](./fingerprinting.md)).
3. **The engine computes.** A stateless worker validates, normalizes, and
   hashes the package to the canonical SHA-256 digest, then computes
   entropy, risk, and similarity inputs. Because the worker is
   deterministic, the same package would yield identical bytes anywhere
   ([Determinism](./determinism.md)).
4. **The platform decides.** The worker publishes results over AMQP. The
   fraud platform maps the digest to known devices, weighs the similarity and
   risk, and decides whether to trust the session
   ([Scoring](./scoring.md)).
5. **The app enforces, the SDK informs.** A `session.blocked` event reaches
   the SDK; it updates the UI, while the application itself is what actually
   stops the offending action, server-side
   ([Trust & Privacy](./trust-privacy.md)).

Every page in this section is a perspective on a single, coherent contract,
and this flow is one concrete rendering of it.

## A short glossary

A few terms recur across the concepts and are worth fixing precisely:

- **Signal** — a single, typed, observed value (one of the 102). The
  atomic unit collected by the browser.
- **Category** — one of the 21 groupings of signals by browser surface.
- **Fingerprint** — the canonical SHA-256 digest derived from the ordered,
  canonicalised signal set. Computed only by the engine.
- **SignalPackage** — the versioned (v2) serialization of a collection of
  signals that the browser transmits. The engine's atomic input.
- **Ingress** — the HTTP endpoint that receives `SignalPackage`s and relays
  them to a worker.
- **Worker** — the stateless, deterministic Zig process that computes the
  fingerprint and its scores server-side.
- **Fraud platform** — the separate system that receives results over AMQP
  and owns all business decisioning.
- **Determinism** — same input bytes yield same output bytes on any
  platform; the core architectural invariant (see
  [Determinism](./determinism.md)).
- **Replay** — re-feeding a previously captured package to any worker to
  recover the exact computed result for audit or dispute resolution.

## Where next

- [Start](../start.md) — install the SDK and collect a first package in
  under five minutes.
- [Architecture](../architecture.md) — the layered module graph and the
  event flow through ingress, worker, and AMQP.
- [Reference: API](../reference/api.md) — engine operations, the SDK
  surface, and the worker CLI.
- [Reference: Signals](../reference/api.md) — the full 102-signal registry
  with types and weights.
