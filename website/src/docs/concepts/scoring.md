---
title: "Scoring"
description: "How risk, entropy, and similarity turn raw signals into decision-relevant numbers."
category: "concepts"
order: 6
crumbs: ["concepts", "scoring"]
---

# Scoring

The engine does not hand the fraud platform a bare digest and stop. For a
digest to be *actionable* — to tell "same device" from "similar device",
and to say how confident the picture is — the engine computes three
quantities over the signal package: **risk**, **entropy**, and
**similarity**. Each is itself deterministic, versioned, and derived from
the same canonical signal set and its metadata (see
[Signals](/docs/concepts/signals/)).

This page explains the three models and how they combine.

## The three models at a glance

| Model | Input | Output | Answers the question |
| ----- | ----- | ------ | -------------------- |
| Similarity | two fingerprints (or two feature values) | score in `[0.0, 1.0]` | "how alike are these two?" |
| Entropy | one fingerprint | Shannon bits | "how much information does this fingerprint carry?" |
| Risk | one fingerprint | score in `[0.0, 1.0]` + flags + label | "how likely is this package to be abnormal or abused?" |

All three consume the *same* per-feature metadata — the compile-time
registry of IDs, value types, weights, and flags — so they are always in
agreement about which features matter and how much.

## Similarity: weighted per-feature comparison

Similarity answers the question *"is this visitor on a device we have seen
before?"* It is computed at two levels.

### Feature-level similarity

Each feature type has a well-defined equivalence measure, returning `0.0`
(no match) to `1.0` (identical):

- **Boolean** — `1.0` if equal, else `0.0`.
- **Integer / Float** — a normalised closeness measure over the feature's
  declared bounds, so two nearby values score high without needing exact
  equality (robust to small drift like battery percentage or RTT).
- **String** — exact-match identity for canonical identifiers (language,
  timezone), with optional closeness for ordinal or bounded strings.
- **Bytes / arrays** — digest or set-based similarity; byte digests compare
  by identity, arrays by set overlap.

The key design choice is that similarity is **per-feature and
weighted**: no single feature can dominate a whole comparison, and features
with different discriminative power contribute proportionally.

### Fingerprint-level similarity

The fingerprint score aggregates feature-level scores using each feature's
metadata weight:

```
                     Σ ( weight[f] × featureScore[f] )
fingerprintScore  =  ──────────────────────────────────
                           Σ weight[f]  (over matched features)
```

Only features present in *both* fingerprints contribute to the numerator
(matching on missing data is meaningless), which is why the denominator is
over matched features. The result is a single `[0.0, 1.0]` figure that the
fraud platform can threshold or feed into its own decisioning — it is a
*continuous* measure, deliberately not a binary "match/no-match", so the
platform can reason about near-neighbours and fuzzy clusters of devices.

The similarity suite is validated by a fixture (a similarity matrix with
expected scores in `tests/fixtures/`), locking in the weights' behaviour as
deterministic test data.

## Entropy: Shannon information content

Entropy measures how much information a fingerprint actually carries. The
engine uses classic **Shannon entropy**:

```
H = − Σ p(x) log₂ p(x)      (bits)
```

- Over a raw byte stream (`shannonEntropy`) this reports bits per byte.
- Over a fingerprint (`fingerprintEntropy`) it reports a **weighted** bit
  total that reflects how much *unique, discriminating* information the set
  of signals provides, again using feature metadata.

Entropy is a confidence signal, not a verdict. Its role is to prevent a
false sense of precision:

- **A high-entropy fingerprint** is genuinely rich in distinguishing
  information, so a similarity match against it is credible.
- **A low-entropy fingerprint** (few features, repetitive values, an
  aggressive browser that yields little) carries little information, so a
  strong claim about identity should *not* be derived from it. Low entropy
  is itself a risk signal.

Critically, entropy and similarity are *not* redundant. Two sparse
fingerprints can be near-identical and therefore similar, yet still carry
almost no information. Similarity says "these two look alike"; entropy says
"how much is that worth believing". The fraud platform consumes both
together.

## Risk: the assessment model

Risk turns the qualitative signs of abuse or anomaly into a quantitative
score. The engine computes an assessment:

```zig
const assessment = core.risk.computeRisk(fingerprint, allocator);
// assessment.score : [0.0 (low risk) .. 1.0 (high risk)]
// assessment.label : .low | .medium | .high | .critical
// assessment.flags : e.g. missing_features, bound_violations, ...
```

The risk model is **data-driven**: it consumes the signal metadata and the
normalization/validation results, rather than hard-coding case-by-case
rules. Its components:

### 1. Missing features

The per-feature flags distinguish features that must be present
(`stable_required`, `critical`) from optional ones. When a *required or
critical* feature is absent — the browser reported no canvas/WebGL digest,
or the package simply lacks a mandatory signal — risk rises. Critically
weighted features contribute more. The model treats absence as evidence:
it is far more likely that an abusive agent strips or fails to produce a
feature than that an ordinary visitor's browser forgets its own user agent.

### 2. Bound violations

Every feature declares a type and expected bounds
(`FeatureDefinition`). Normalization checks each collected value against
these. Values outside the declared bounds — an impossible screen width, a
battery level above 1.0, a hardware-concurrency count beyond any real CPU —
are *bound violations* and are strong fraud indicators. They are surfaced
as warnings and feed directly into the risk score.

### 3. Coverage

Coverage is the fraction of the expected signal set actually present.
Aggressive blocking, private windows, and headless environments all shrink
coverage. Low coverage is incorporated into risk because it signals either a
hardened (legitimate) browser or a stripped (abusive) agent — the model
does not decide which, but it *does* reflect that confidence is reduced and
risk of evasion rises.

### 4. Entropy deficit

Low fingerprint entropy is penalised as a risk signal on its own. A package
that carries almost no discriminating information is either a genuinely
featureless environment or one deliberately engineered to be anonymous:
either way it is a weak basis for a *trusted* decision and deserves a risk
contribution. This is how the risk model closes the loop with the entropy
measure above.

### Combining into a score

The components are weighted and merged into `assessment.score` in
`[0.0, 1.0]`, and mapped to a label (`low`/`medium`/`high`/`critical`).
Individual concerns are also surfaced as discrete `flags` (for example
`missing_features`, `bound_violations`) so that downstream consumers can
react to *specific* signals rather than only the aggregate. The mapping
from component evidence to score is data-driven and versioned, so it can be
tuned and replayed without touching transport or hashing code.

## How the three models fit together

For any inbound `SignalPackage`, the worker produces all three:

```text
package ──► normalize/validate  (coverage, bound violations)
         │
         ├─► hash        → canonical digest
         ├─► entropy     → weighted Shannon bits   (confidence)
         ├─► risk        → score + flags + label   (anomaly)
         └─► similarity  → score vs. known devices (identity, platform-side)
```

The platform then composes them: similarity tells it *who this likely is*,
entropy tells it *how much to trust that*,
risk tells it *whether to trust it at all*, and the digest keys cross-session
matching. All three are deterministic and replayable, so a block decision can
be re-derived exactly (see [Determinism](/docs/concepts/determinism/)), and all three
are computed server-side, keeping the browser out of every
decision (see [Fingerprinting](/docs/concepts/fingerprinting/)).
