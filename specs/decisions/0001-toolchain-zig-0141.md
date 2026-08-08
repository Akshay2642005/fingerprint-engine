# ADR-001 — Toolchain pinned to Zig 0.14.1

- **Status:** Adopted (2026-08-07)
- **Rework decision:** D1

## Context

The project originally built on Zig 0.16.0 (in-development `std.Io`, new
`createModule`/`addExecutable(root_module)` build API). The rework required a
stable toolchain so that "every commit compiles and passes tests" stays
satisfiable and the migration remains bisectable. Downgrading last would have
produced two overlapping giant diffs.

## Decision

- Target **Zig 0.14.1** (`build.zig.zon` `minimum_zig_version = "0.14.1"`).
- Downgrade **first**, as its own commit, before any restructuring.
- Replace 0.16-only APIs: `std.Io.*` → `std.io.*`, build module API → 0.14
  style (`b.addModule`, `addExecutable` with `root_source_file`).
- CI pins `ZIG_VERSION: 0.14.1`.

## Consequences

- Local builds must use the 0.14.1 toolchain (`C:/Users/M S I/.zvm/0.14.1/zig.exe`),
  never a PATH-installed 0.16.0.
- No `-Doptimize` flag (0.14 rejects it) — use `--release=safe`.
- All future code must stay compatible with 0.14.1; new std APIs introduced
  after 0.14 are off-limits.
