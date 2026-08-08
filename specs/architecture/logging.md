# Application logging design — F-2

## Problem

Logging today is ad-hoc and inconsistent:

- `src/worker/main.zig` and `src/scripts.zig` print with `std.debug.print`
  (unconditional, no levels, no scopes).
- The AMQP client logs through `std.log.scoped(.amqp)` — which routes to
  Zig's default stderr logger unless an executable opts in with a custom
  `std_options.logFn`.
- There is no way to raise/lower verbosity at runtime, no structured output
  for machines, and no way to silence the `info(amqp)` connection dump (the
  noise seen in `amqp get`).
- A production deployment (worker + ingress containers) needs: levels,
  scopes, timestamped/structure parseable lines, and a consistent default.

## Design

### `src/log.zig` — leaf module, zero dependencies

Imports `std` only, so every module (model, core, engine, io, adapter,
worker, ingress, scripts) can use it without creating cycles.

API sketch:

```zig
pub const Level = enum(u8) { debug, info, warn, err };

pub const Scope = enum {
    worker, ingress, amqp, engine, pool, scripts,
};

/// Compile-time-fixed, runtime-settable level (default .info).
pub var level: Level = .info;

/// Structured fields are written as `key=value` in text mode, as a JSON
/// object in json mode.
pub const Format = enum { text, json };

pub fn init(level: Level, format: Format) void;

pub fn log(scope: Scope, lvl: Level, comptime fmt: []const u8, args: anytype) void;
pub const info  = ...; // scope-bounded convenience wrappers
pub const debug = ...;
pub const warn  = ...;
pub const err   = ...;
```

Properties:

- **Levels**: `debug | info | warn | err`; a message below `level` is a no-op.
- **Scopes**: `worker: listening on ...`, `amqp: connection start`, etc. —
  the category is a first-class field, not a prefix string.
- **Formats**:
  - `text`: `2026-08-08T12:00:00Z [info] (amqp) message key=value` — the
    familiar style, greppable.
  - `json`: `{"ts":"...","level":"info","scope":"amqp","msg":"...","k":"v"}` —
    for log aggregators. Escaping follows JSON rules.
- **Determinism note**: the logger is transport-adjacent (it writes to
  stderr), so it lives at the leaf edge of the dependency graph. Core
  algorithms never log — only executables and adapters do.
- **Buffering**: a fixed buffer per line (no heap per message); the
  caller-owned buffer pattern the codebase already uses.

### Wiring the std log

`std.log` calls from the AMQP client are routed through the same levels by
declaring a custom log function in the **executable root modules**
(`src/worker/main.zig`, future `src/ingress/main.zig`, `src/scripts.zig`):

```zig
pub const std_options = std.Options{
    .logFn = myLogFn, // maps std.log.Level/scope → log.zig
};
```

This keeps library code untouched while giving every executable one
consistent pipeline. `amqp get --quiet` sets `level = .err`, silencing the
`info(amqp)` connection dump.

### CLI surface

| Executable | Flags |
|------------|-------|
| `worker` | `--log-level=debug\|info\|warn\|err` (default `info`), `--log-format=text\|json` (default `text`) |
| `ingress` (future) | same, plus per-request access lines at `debug` |
| `scripts amqp get` | `--quiet` (→ `err`) |

Env override (containers): `FPKG_LOG_LEVEL` / `FPKG_LOG_FORMAT` — CLI wins
over env, env wins over default. This matches how the ingress URL is already
resolved in `build.zig` (option → env → default).

### Migration

- Replace every `std.debug.print` in `src/worker/main.zig` and
  `src/scripts.zig` with `log.zig` calls at the appropriate level
  (announcements → `info`, dropped frames → `warn`, CLI errors → `err`).
- Wire `std_options.logFn` in the worker, scripts, and later ingress
  executables so the AMQP client's `std.log.scoped(.amqp)` honors
  `--log-level`.
- Keep the integration-test output contract intact: the worker's
  `worker: listening on host:port` line (parsed by `src/integration_tests.zig`)
  and the bench's `Completed 12 benchmarks.` line must still be emitted
  verbatim at the default level.

### Tests

- Unit: level filtering, scope rendering, text/JSON escaping, `--quiet`.
- Integration: run `worker start --log-level=err` and assert the listening
  announcement is suppressed while the process still serves frames.
