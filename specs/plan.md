# Phase 7 — Similarity

> Builds on Phases 1-6 to compute feature-level and fingerprint-level similarity scores.

## Scope

### In Scope

1. **Feature value similarity** — Compare two FeatureValues of the same type, return score 0.0–1.0
2. **Weighted fingerprint similarity** — Compare two Fingerprints with per-feature weights from FeatureDefinition
3. **Wire module** + tests
4. **Preflight**

### Design

- Boolean: exact match (1.0) or mismatch (0.0)
- Integer: normalized inverse difference capped at [0, 1]
- Float: normalized inverse difference capped at [0, 1]
- String: normalized edit distance (Levenshtein-based)
- Bytes: Jaccard similarity on n-grams
- Arrays: Jaccard similarity on elements
- Fingerprint: weighted average of feature similarities, using FeatureDefinition.weight

### Stories

1. FeatureValue similarity (all 9 types)
2. Weighted fingerprint similarity
