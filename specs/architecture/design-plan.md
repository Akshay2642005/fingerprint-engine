# Design plan — Fingerprint Engine (current)

Refreshed 2026-08-08. The definitive architecture documents are
`specs/decisions/rework/DESIGN.md` (rework) and `docs/architecture.md` (user-facing);
this file summarizes the current design state and points at the details.

## Current architecture (shipped, v0.4.0)

1. **Deterministic engine** — `engine.process()` over versioned
   `Operation`/`Status`, immutable `Request`, caller-owned `Response`,
   comptime dispatch; ops in `engine/ops/*`. No io/transport imports.
2. **FPKG envelope + SignalPackage v2** — framed messages with message type,
   codec, integrity; lossless metadata (package_id, sdk_version,
   collected_at); v1 compat.
3. **Async IO primitives** — Message/Pool, RingBuffer, Channel, Completion,
   Executor, Frame, Reader/Writer, Dispatcher (zero deps).
4. **Adapters** — comptime transport contract; loopback + FPKG tcp +
   AMQP 0-9-1 result publisher (outbound only).
5. **Worker** — stateless executable (loopback/tcp, publish none/amqp),
   Docker container; canonical digest computed only here.
6. **Browser SDK** — hand-written TS: collect → package → POST to ingress;
   middleware for fraud decisions. No WASM in the package.

## Planned additions (backlog, in order)

| # | Design | Doc |
|---|--------|-----|
| S1 | BUG-001 fix + tcp idle timeouts + graceful shutdown | `specs/quality/audits/2026-08-08.md` |
| S2 | Version single-source-of-truth via `b.addOptions()` | `specs/quality/audits/2026-08-08.md` |
| S3 | `src/log.zig` leaf logger, `--log-level`/`--log-format`, `--quiet` | `specs/architecture/logging.md` |
| S4 | HTTP ingress executable + Dockerfile + GHCR + compose + e2e | `specs/architecture/ingress.md` |
| S5 | AMQP push consumer + dead-letter queue | `specs/quality/audits/2026-08-08.md` |
| S6 | Full-stack compose + release surface for the ingress image | `specs/quality/audits/2026-08-08.md` |

## Design principles (unchanged from rework)

- Everything depends inward; adapters depend on the engine, never the reverse.
- Deterministic, replayable, stateless computation; zero runtime allocation in
  core algorithms; compile-time-first validation.
- The engine never knows transport, queues, databases, auth, or business
  logic; the Go fraud platform owns everything downstream of the AMQP events.
