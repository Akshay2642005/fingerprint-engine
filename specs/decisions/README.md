# Architecture Decision Records

Each ADR records a decision in context/decision/consequences form. The rework
series (D1–D20) was locked in `specs/decisions/rework/DECISIONS.md` (2026-08-07) and is
distilled here for long-lived reference; decisions made after the rework
(ingress executable, stateless worker pool, slice sequencing) appear as ADRs
first.

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](0001-toolchain-zig-0141.md) | Toolchain pinned to Zig 0.14.1 | Adopted |
| [ADR-002](0002-repository-layout.md) | Layered `src/` layout, everything depends inward | Adopted |
| [ADR-003](0003-engine-api.md) | Single deterministic `Engine.process` entry point | Adopted |
| [ADR-004](0004-message-envelope-serialization.md) | FPKG envelope + SignalPackage v2 + integrity | Adopted |
| [ADR-005](0005-io-abstraction.md) | Async-first, minimal, completion-based IO layer | Adopted |
| [ADR-006](0006-transport-split.md) | Inbound request/response, outbound AMQP events | Adopted |
| [ADR-007](0007-worker-shape.md) | Tiny stateless worker executable in Docker | Adopted |
| [ADR-008](0008-browser-sdk-wasm-native.md) | Hand-written TS SDK; WASM infra-only; no native SDK | Adopted |
| [ADR-009](0009-fraud-platform-boundary.md) | Go platform owns rules/matching/UI; engine publishes events | Adopted |
| [ADR-010](0010-ingress-executable.md) | HTTP ingress as a separate executable | Adopted (planned) |

## Rules

1. Statuses: `proposed` → `adopted` → (optionally) `superseded`/`replaced`.
2. To change an adopted decision, add a new ADR that supersedes it — never
   rewrite history silently.
3. The rework series D1–D20 maps onto ADR-001–ADR-009; new decisions start
   at ADR-010.
