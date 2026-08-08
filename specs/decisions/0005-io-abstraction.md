# ADR-005 — Async-first, minimal, completion-based IO layer

- **Status:** Adopted (2026-08-07)
- **Rework decision:** D7

## Context

The transport boundary (adapter/worker) needs a shared vocabulary for
messages, buffers, frames, and event handling. The engine itself must stay
synchronous and deterministic.

## Decision

- **Async-first** from day one, inspired by (not copied from) well-established
  completion-based IO designs.
- `src/io/` ships: `Message`/`MessagePool` (arena-backed), `RingBuffer`
  (comptime-generic FIFO), typed `Channel` (SPSC), `Completion`, deterministic
  single-threaded `Executor`, FPKG `Frame`, fixed-buffer `Reader`/`Writer`,
  comptime `Dispatcher`. Zero dependencies.
- Explicit message ownership; no runtime registration/reflection; no io_uring
  dependency; portable across Linux/macOS/Windows.
- `Pipeline` and `Command` are **deferred** — add only when a consumer needs
  them (avoids scope creep).

## Consequences

- The engine never imports `io/`; async concerns stop at the adapter boundary.
- New transports reuse the same framing/ownership primitives (loopback, tcp,
  and the AMQP client all do).
- The AMQP client builds on these primitives rather than inventing a parallel
  buffer/state machine (D20).
