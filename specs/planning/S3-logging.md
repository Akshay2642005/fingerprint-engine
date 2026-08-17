# S3 — Application logging implementation plan

Status: done
Spec: specs/architecture/logging.md (F-2)
Slice: S3 of e12-audit-backlog (specs/planning/STATUS.yaml)
Reference: TigerBeetle logging pattern (tigerbeetle/src/tigerbeetle/main.zig
`std_options.logFn` + runtime level filter; tigerbeetle/src/stdx/stdx.zig
`log_with_timestamp`; `std.log.scoped(...)` throughout). TB does not build a
custom logging module — the executable root declares a `logFn` that prepends a
UTC timestamp and filters by a runtime-settable level. We follow that shape but
add the module the spec requires (levels, scopes, text/json formats) so every
executable shares one pipeline.

## Deliverables

### 1. `src/log.zig` — leaf module, std-only

- `Level = enum(u8) { err, warn, info, debug }` (ordered err=0…debug=3).
- `Scope = enum { worker, ingress, amqp, engine, pool, scripts }`.
- `Format = enum { text, json }`.
- `pub var level: Level = .info;` / `pub var format: Format = .text;`
- `init(level, format)`, `parseLevel([]const u8) ?Level`,
  `parseFormat([]const u8) ?Format`, `shouldLog(Level) bool`.
- `initFromEnv(alloc, cli_level: ?Level, cli_format: ?Format)` — resolution
  order CLI > env (`FPKG_LOG_LEVEL`/`FPKG_LOG_FORMAT`) > default; invalid env
  falls back to default; CLI values are pre-validated by the arg parsers.
- Scope-bounded convenience wrappers (TB `std.log.scoped` shape):
  `of(comptime Scope) type` returning `struct { err, warn, info, debug }`, plus
  exported `worker`, `ingress`, `amqp`, `engine`, `pool`, `scripts` constants.
- `log(scope, lvl, comptime fmt, args)` — filter then render.
- `logFn(comptime message_level: std.log.Level, comptime scope: @Type(.enum_literal),
  comptime fmt, args)` — for `std_options.logFn`; routes `std.log` (the AMQP
  client's `std.log.scoped(.amqp)`) through the same filter/format.
- Render into a fixed `[4096]u8` buffer (no heap per message), single stderr
  write; text `YYYY-MM-DDTHH:MM:SSZ [level] (scope) msg\n` (UTC via
  `std.time.epoch`), json `{"ts":"…","level":"…","scope":"…","msg":"…"}\n` with
  full JSON string escaping (reuse the escaping rules of
  src/scripts.zig `writeJsonString`).
- Header comment: `// story: s3-logging`.

### 2. Executable wiring (`std_options.logFn`, spec §wiring)

Root modules each declare:

```zig
pub const std_options = std.Options{
    .log_level = .debug, // comptime: keep messages compiled in (TB pattern)
    .logFn = log.logFn,  // runtime filter handled by log.zig
};
```

- `src/cmd/worker/worker.zig` — add `log` import, `std_options`, CLI flags
  `--log-level=`, `--log-format=` (validated in `parse`, stored as
  `?log.Level`/`?log.Format`), `log.initFromEnv` at top of `start()`, and
  replace every `std.debug.print`:
  - frame dropped / publish dropped → `.warn`
  - invalid --amqp-address / publisher failed / invalid --listen / parse
    diagnostics → `.err`
  - publisher ready / `worker: listening on {s}:{d}` → `.info` (the
    `worker: listening on ` substring contract is preserved — the integration
    tests match it inside the line).
- `src/cmd/ingress/ingress.zig` — same, on the already-parsed
  `--log-level`/`--log-format` (StartOptions switches from `[]const u8` to
  `?log.Level`/`?log.Format`); `ingress: listening on …` → `.info`,
  diagnostics → `.err`, client dropped → `.warn`.
- `src/cmd/ingress/http.zig` — `ingress: worker request failed` → `.warn`.
- `src/cmd/main.zig` (combined `fingerprint` binary) — `log` import +
  `std_options` so the AMQP client honors the level in the combined binary.
  The dispatch-error print stays a plain stderr print (spec migration scope is
  worker + scripts).
- `src/scripts.zig` — `log` import, `std_options`, `log.initFromEnv` in
  `main()`, every diagnostic `std.debug.print` → `log.scripts.err` (success
  `stdout.print` output is command output and stays). `amqp get` gains
  `--quiet` (→ `log.level = .err` before the broker connection), silencing the
  `info(amqp)` connection dump while keeping the inspector's own stdout output.
- `src/bench/main.zig` — untouched (output contract
  `Completed 12 benchmarks.` must stay verbatim; bench is out of migration
  scope).

### 3. `build.zig`

- `const log_module = b.createModule(.{ .root_source_file = b.path("src/log.zig"), … });`
  (std-only leaf, placed with the other leaf modules).
- Add `.{ .name = "log", .module = log_module }` to the import maps of
  `worker`, `ingress`, `cmd`, `test_core_module`, and to `build_scripts`
  (new `log: *std.Build.Module` option param).

## Tests (TDD order)

1. `tests/log/log_test.zig` (register in tests/root.zig):
   - `parseLevel`/`parseFormat` accept all four/two values, reject garbage.
   - `shouldLog` filters: level `.err` suppresses `.info`; `.info` shows
     `.err`/`.warn`/`.info` and hides `.debug`.
   - text render: exact `ts [info] (worker) …` shape (level text, scope
     parens, trailing newline).
   - json render: `{"ts":"…","level":"info","scope":"amqp","msg":"…"}\n` with
     escaping of `"`, `\`, `\n`, and a control char.
   - `of(.worker).info` routes to the worker scope.
   - `initFromEnv`: env overrides default, CLI overrides env.
2. `tests/worker/worker_test.zig`: parse accepts `--log-level=debug
   --log-format=json`; rejects `--log-level=loud` and `--log-format=xml`
   (`InvalidOption`); defaults are null.
3. `tests/cmd/ingress_test.zig`: update the two `log_level`/`log_format`
   assertions to the enum types; add invalid-value rejection.
4. `src/integration_tests.zig`:
   - worker default level still emits `worker: listening on …` (existing
     spawnWorker tests already pin this — no change).
   - new: `worker start --log-level=err` suppresses the listening
     announcement while still serving a valid frame: reserve a port by binding
     `127.0.0.1:0` and closing, spawn on that port, poll TCP connect, send the
     fixture frame, expect a hash reply, SIGTERM, wait exit 0, then assert the
     captured stderr contains no `worker: listening on ` line.

## Verification

1. `zig build test --summary all` green (unit + integration).
2. Manual: `zig build worker && ./zig-out/bin/worker start --transport=tcp
   --listen=127.0.0.1:0` shows the timestamped text line;
   `--log-level=err` suppresses it; `--log-format=json` emits JSON;
   `FPKG_LOG_LEVEL=err` suppresses without the flag.
3. `zig build scripts -- amqp get --quiet` suppresses the info(amqp) dump
   (requires a broker) — manual, per repo convention.
4. Update specs/planning/STATUS.yaml (S3 → done) and refresh SESSION.yaml.
