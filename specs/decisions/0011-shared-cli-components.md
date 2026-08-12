# ADR-011 — Shared CLI folder with combined + component binaries

- **Status:** Adopted (2026-08-12)
- **Source:** `specs/architecture/ingress.md`
- **Amends:** ADR-010 (HTTP ingress as a separate executable)

## Context

ADR-010 placed the ingress in its own executable (`src/ingress/main.zig`) and
explicitly rejected a combined `fingerprint-edge` binary. Building the ingress
highlighted that worker and ingress share the same concerns at the source
level — the same CLI conventions (`start`/`version`/`help`), the same
shutdown handling, the same build plumbing, and the same framing helpers —
while remaining distinct *processes* at runtime (the ingress must never run
engine code; the worker must never speak HTTP).

The product version lives in `build.zig.zon`; `build.zig` parses it at
comptime (`package_version`) and injects it as the `version` build-options
module — the TigerBeetle pattern — so app code can never drift from the
release. Earlier iterations carried "0.0.0-dev" fallback stubs
(`src/build_options.zig`, `src/worker/build_options.zig`) for standalone
editor analysis; those are gone.

## Decision

- **One folder, three build targets.** `src/cmd/` holds the entire CLI layer:
  - `main.zig` — combined `fingerprint` binary: dispatches `worker|ingress`
    subcommands plus top-level `version`/`help`. This is the single-binary
    distribution (TigerBeetle-style: one artifact, subcommands).
  - `worker.zig` — the worker app + CLI (moved from `src/worker/main.zig`),
    with its own `pub fn main` so it also builds standalone.
  - `ingress.zig` — the HTTP ingress app + CLI (S4), standalone-buildable.
  - no version source file — the version is injected as the `version`
    build-options module (TigerBeetle pattern, ADR-011 single source of
    truth), so there is nothing to drift or maintain.
- **Three `zig build` steps, three installed executables:**
  - `zig build fingerprint` → `zig-out/bin/fingerprint` (combined)
  - `zig build worker` → `zig-out/bin/worker` (standalone)
  - `zig build ingress` → `zig-out/bin/ingress` (standalone)
  - `zig build` (default) installs all three.
- **argv contract.** Each app's `parse(args)` skips `args[0]` and reads
  `args[1]` as its subcommand. `main.zig` dispatches on `argv[1]` and passes
  `args[1..]` down, so the standalone and combined invocations share one
  parser and the existing worker unit tests and integration tests keep their
  `start --transport=tcp ...` shape unchanged.
- **Dependency rule preserved.** `worker.zig` imports `engine`+`adapter`+`io`;
  `ingress.zig` imports `adapter`+`io` only — `engine` is *not* registered in
  the ingress module's import map, so the "no engine code in the ingress"
  rule (design §7, D16) is structurally enforced.
- **Distribution, both ways.** Docker images use the component binaries
  (`deploy/Dockerfile.worker` → `worker`, `deploy/Dockerfile.ingress` →
  `ingress`), so each container runs exactly one process with the least
  possible surface. Binary releases publish the single `fingerprint` artifact
  and/or the individual `worker`/`ingress` artifacts.
- **Version single source of truth.** `build.zig` derives `package_version`
  at comptime from `build.zig.zon` (`@embedFile` + parse of `.version`) and
  injects it via `b.addOptions()` as the `version` module in every
  consumer's import map (worker CLI, AMQP properties, wasm metadata,
  scripts image tag). CI reads the same value from `build.zig.zon`; the
  BUG-002 regression tests compare the injected value against CLI output,
  so a drift fails loudly.

## Consequences

- The runtime topology is unchanged from ADR-010: the ingress is a separate
  process with its own scaling (few replicas, long-lived connections), and
  the worker stays single-client-at-a-time per connection; the ingress pools
  connections per worker (H-1 keeps stalled connections self-healing).
- One shared CLI module removes the duplicated parse/usage/shutdown
  plumbing and makes `zig build` targets the single description of what
  ships (aliases + individual + combined).
- `fingerprint worker start ...` and standalone `worker start ...` are
  byte-compatible; Dockerfiles, compose, and integration tests that invoke
  `worker start` keep working without edits.
- Moving `src/worker/main.zig` → `src/cmd/worker.zig` keeps git history via
  `git mv`; the `worker` module import name for unit tests is unchanged.
