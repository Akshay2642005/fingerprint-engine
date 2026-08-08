# ADR-007 — Tiny stateless worker executable in Docker

- **Status:** Adopted (2026-08-07)
- **Rework decision:** D9 (+ D10 for the Docker delivery)

## Context

The rework needed a small, deployable unit that runs `engine.process()`. With
the native SDK dropped (D10), the worker is the only place canonical
fingerprints are computed.

## Decision

- `src/worker/main.zig` — tiny executable, transport injected at runtime:
  - `--transport=loopback` — framed messages over stdin/stdout (repl-style;
    enables pipe e2e tests).
  - `--transport=tcp` — FPKG-framed request/response server for the ingress
    path (one client at a time).
  - `--publish=none|amqp` — outbound event sink; `amqp` routes every reply
    frame to the broker via the AMQP adapter.
  - `version`, `help` subcommands.
- Worker logic: receive frame → deserialize → `engine.process()` → serialize →
  publish. **No business logic.**
- Shipped as a Docker container: `deploy/Dockerfile.worker` (thin alpine,
  tini as PID 1, non-root, binary built by `zig build worker --release=safe`
  — nothing compiles inside the image), built/pushed via `zig build docker:worker`
  and the release pipeline to GHCR (`ghcr.io/akshay2642005/fingerprint-engine/fingerprint-worker`).
- Stateless: the arena is reset per frame in `serve()`, so any worker can
  process any package — this is what makes the ingress worker pool and
  round-robin retry safe.

## Consequences

- No native SDK, no C ABI — consumers deploy containers.
- The worker is the single place the canonical digest can be produced.
- Known gaps (audit H-1/H-2/H-3): no socket idle timeout on tcp (a short
  write then silence wedges the accept loop), no graceful shutdown, no health
  probe — tracked in `specs/quality/audits/2026-08-08.md`, fixed in S1.
