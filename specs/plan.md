# Phase 8 — Entropy

> Computes per-feature and overall fingerprint entropy using Shannon entropy.

## Scope

1. **Shannon entropy** — Compute entropy of a byte slice (bits per byte, 0.0–8.0)
2. **Feature entropy** — Convert FeatureValue to bytes, compute Shannon entropy
3. **Fingerprint entropy** — Aggregate per-feature entropies weighted by feature weights
4. **Wire module** + tests
