# Phase 9 — Risk Engine

> Analyzes fingerprint risk level by integrating validation, normalization, entropy, and feature presence signals.

## Scope

1. **Risk scoring** — `computeRisk()` produces a risk score (0.0–1.0) with structured flags
2. **Anomaly detection** — flags suspicious/contradictory feature combinations
3. **Wire module** + tests

### Design

Risk score factors:

- Missing required features (from validation)
- Bound/type violations (from normalization)
- Low feature entropy (from entropy module)
- Low feature coverage (few features vs total registered)
- Anomalous combinations
- Overall entropy penalty

Output: `RiskAssessment` struct with score, flags enum, missing features list
