# Refactor status — Fingerprint Engine

Refreshed 2026-08-08. Old→new mapping executed during the rework; anything
still outstanding is listed at the end.

## Executed (v0.2.0–v0.2.2)

| From | To | Status |
|------|-----|--------|
| `src/core/features/*`, `src/core/fingerprint/*` | `src/model/` | ✅ moved |
| `src/core/serialization/*` | `src/serialization/` | ✅ moved + v2 body |
| `src/browser/wasm/root.zig` (stateful) | `src/wasm.zig` (stateless infra) | ✅ rewritten |
| `src/browser/bindings/*`, `collectors/*` | `src/clients/browser/src/` (hand-written TS) | ✅ rewritten |
| `src/server/` (native + C header + rust) | deleted | ✅ removed (D10) |
| `packages/browser/` → `sdk/browser/` → `src/clients/browser/` | npm package at `src/clients/browser/` | ✅ moved |
| `benchmark/` → `tools/bench/` → `src/bench/` | `src/bench/` | ✅ moved |
| `build.mjs` package build | `zig build clients:browser` | ✅ removed |
| `scripts/` empty dir | `src/scripts.zig` dispatcher + subcommands | ✅ implemented |
| `std.Io` (0.16) serialization | `std.io` / anytype on 0.14.1 | ✅ rewritten |
| UMD base64-wasm template | hand-written TS SDK + dist surface guard | ✅ deleted template |
| `tests/features`, `tests/fingerprint` | `tests/model/` | ✅ moved |
| `tests/hashing`, `tests/entropy`, `tests/similarity`, `tests/risk`, `tests/normalization`, `tests/validation` | `tests/core/` | ✅ moved |
| `tests/server/` | deleted | ✅ removed |
| `tests/engine`, `tests/io`, `tests/adapter`, `tests/worker` | new suites | ✅ added |

## Outstanding refactors (backlog)

- **BUG-002:** six hardcoded version constants → single source injected via
  `b.addOptions()` (S2).
- **F-2:** replace `std.debug.print` in worker/scripts with `src/log.zig`
  (S3).
- **F-1:** add `src/ingress/` (S4) — the remaining planned module.
- **Docs:** `docs/` user docs are current for v0.4.0; refresh after S1–S6 as
  features land.

## Guardrails for future refactors

- Every commit compiles and passes `zig build test` on Zig 0.14.1
  (bisectable migration).
- Pure moves are their own commits; behavior changes land separately.
- Never regenerate `tests/fixtures/fingerprints/signal-package-v2.bin` (pins
  the canonical digest + `sdk_version "0.2.0"`).
- Never reintroduce hardcoded versions in CI/scripts (derive from
  `build.zig.zon`/`package_version`).
