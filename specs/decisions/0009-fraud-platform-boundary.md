# ADR-009 — Fraud platform boundary: Go owns rules/matching/UI

- **Status:** Adopted (2026-08-07)
- **Rework decisions:** D15, D17, D18, D19

## Context

The engine produces deterministic computation results; it must never learn
about databases, auth, users, organizations, policies, or business logic
(REWORK.md absolute rules). Yet someone must store fingerprints, run fraud
rules, and give admins/AI agents a workspace.

## Decision

- **The fraud platform is a separate repository (Go), out of scope here.**
  This repo ends at the engine's published events.
- The engine (workers) publishes typed, schema-versioned events to AMQP:
  `FingerprintComputed`, `RiskResult`, `SimilarityResult`, `ValidationResult`,
  `Diagnostics`. The Go platform consumes them and owns everything downstream:
  **Postgres rule-based fraud detection**, the **admin workspace**, and
  **AI-agent tooling**.
- This repo defines the **event contracts**; the Go repo implements
  consumption.
- **Matching at scale (D18):** Go owns candidate selection; the engine only
  scores pairs (`similarity` op takes `{a, b}`). Ordered strategy: exact
  digest lookup (indexed Postgres) → coarse-bucket prefilter → engine pair
  scoring → LSH/embeddings later.
- **Rules-as-data (D19):** rules are versioned rows (conditions over engine
  signals → `allow/block/challenge/review` + priority + TTL), evaluated with
  audit trail and dry-run mode. The engine never sees rules.
- **Blocking surface (D17):** three levers, all owned by Go/app, surfaced by
  the SDK: sync decision API (`GET /v1/risk/session/:id`), WebSocket push
  (`session.blocked` → SDK raises event → app kills the session), and
  authoritative app-side enforcement (token revocation, denylist). The SDK
  middleware is a UX gate only.

## Consequences

- Repo boundary stays clean: no Zig code ever imports a DB/auth/client.
- When the Go platform lands it consumes the AMQP events defined here; no
  engine changes required.
- Blocking correctness depends on the app enforcing server-side — the WS push
  is a best-effort fast path.
