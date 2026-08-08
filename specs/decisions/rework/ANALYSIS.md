# Phase 1 — Repository Analysis

Status: Complete (2026-08-07)
Scope: Entire repository as of the rework kickoff. No code was changed.

## 1. Repository inventory

### Root

| Path | Purpose | Rework disposition |
|------|---------|--------------------|
| `build.zig` | 0.16-style build (createModule, addExecutable(root_module), addLibrary, addTest) | Rewrite for 0.14.1 + new targets |
| `build.zig.zon` | 0.1.1, `minimum_zig_version = 0.16.0` | Bump version, pin 0.14.1 |
| `.github/workflows/ci.yml` | test + wasm-build + native-build, `ZIG_VERSION: 0.16.0` | Drop native job, pin 0.14.1, add worker |
| `benchmark/` | bench harness (`zig build bench`), imports `core` | Move to `tools/bench` |
| `scripts/` | empty | Move to `tools/scripts` |
| `packages/browser/` | npm package (`@fingerprint/sdk`) | Move to `sdk/browser` |
| `docs/` | index.md, architecture.md, api.md (document the deprecated browser-computes-canonical flow) | Rewrite in Phase 4 |

### `src/` — 32 Zig files, 14 TypeScript files

```
src/core/                    (all platform-independent — survives, re-layered)
├── features/    model.zig (FeatureID ×102, FeatureType, FeatureDefinition,
│                          FeatureFlags, FeatureCategory), definitions.zig
│                (comptime table), registry.zig (comptime O(1) lookup, compile
│                errors on duplicate/missing)
├── fingerprint/ value.zig (FeatureValue tagged union), feature.zig (id+value),
│                fingerprint.zig (metadata + features), metadata.zig
│                (schema_version, sdk_version, collected_at)
├── hashing/     hasher.zig (incremental SHA-256), feature.zig, fingerprint.zig
├── serialization/ binary.zig (FNGR TLV, std.Io — 0.16 only), json.zig
├── normalization/ types.zig, bounds.zig, normalize.zig
├── validation/  required.zig (static bitset presence check)
├── similarity/  feature.zig, fingerprint.zig (weighted score of two fingerprints)
├── entropy/     entropy.zig (Shannon entropy)
└── risk/        risk.zig (score + flags, consumes validation + normalization + entropy)

src/browser/
├── wasm/root.zig         stateful global-buffer exports:
│                         fingerprint_init/add_*/compute/normalize/risk/entropy,
│                         global feature_buffer + scratch_buffer + initialized flag
├── bindings/ engine.ts (FingerprintEngine class → collectAndCompute()),
│            types.ts, index.ts
└── collectors/ collector.ts, canvas, webgl, audio, fonts, battery, media,
                permissions, speech, input (TS signal gatherers)

src/server/
├── native/root.zig       C ABI: FingerprintEngine opaque handle,
│                         create/destroy/add_*/compute/normalize/risk/entropy
├── api/c/fingerprint.h   C header mirroring FeatureIDs and the handle API
└── rust/                 empty
```

### `tests/` — 51 Zig files

Mirrors the module tree (`tests/features`, `tests/fingerprint`, `tests/hashing`,
`tests/serialization`, `tests/normalization`, `tests/validation`,
`tests/similarity`, `tests/entropy`, `tests/risk`, `tests/browser`,
`tests/server`, `tests/data`, `tests/fixtures`, `tests/utils`, `tests/fuzz`),
wired through `tests/root.zig` into a single `zig build test`. Fuzz targets:
decode, hashing, normalize.

## 2. Dependency graph (current)

```
browser/wasm/root.zig ──> core
server/native/root.zig ──> core
core/risk ──> validation, normalization, entropy, features, fingerprint
core/serialization ──> fingerprint, features (std.Io)
core/hashing ──> features, fingerprint
core/normalization ──> fingerprint, features
core/similarity ──> features, fingerprint
core/validation ──> features, fingerprint
core/features ──> std only
core/fingerprint ──> features (model), std only
```

Acyclic today. **Core never touches transport.** This is the foundation the
rework preserves.

## 3. Findings

### F1 — Canonical fingerprint is computed in the browser (the core assumption to invert)

Three coupled places:

| Location | Mechanism |
|----------|-----------|
| `src/browser/wasm/root.zig` | `fingerprint_compute()` → SHA-256 digest over client-held features |
| `src/server/native/root.zig` | `fingerprint_engine_compute()` — same canonical digest, server-side handle |
| `src/browser/bindings/engine.ts` | `collectAndCompute()` returns digest to app code |

REWORK.md mandates the browser produce a **SignalPackage**, never the canonical
fingerprint. All three must change; the engine keeps `hash` but only the
server-side worker may call it for canonicalization.

### F2 — Orchestration lives in platform layers, not a shared place

Both `wasm/root.zig` and `native/root.zig` hand-roll the same pipeline
(build fingerprint → normalize → risk → entropy) against `core`. That
orchestration is what `engine/` will own once.

### F3 — Duplicated and hardcoded provenance

`buildFingerprint()` in both roots hardcodes `sdk_version = "0.1.0"` and
`collected_at = 0`. Single source of truth (registry-level constant) plus
lossless serialization are needed.

### F4 — Binary serialization is lossy

`binary.encode` writes magic + schema_version + feature count + feature TLVs;
it **drops `sdk_version` and `collected_at`**. `decode` fabricates empty
metadata. A versioned, replayable message design cannot tolerate this.

### F5 — No frame, envelope, integrity, or operation dispatch

Serialization is raw TLV/JSON. There is no message-type tag, no payload
integrity, no request/response, no operation enum, no replay identity. All of
these are new `engine/`, `io/`, `serialization/` responsibilities.

### F6 — Zig 0.16-only APIs (downgrade surface)

- `std.Io.Writer` / `std.Io.Reader` (incl. `.fixed`, `takeArray`,
  `readSliceAll`, `writeInt` methods) — used by `serialization/binary.zig` and
  `serialization/json.zig`.
- `build.zig` module API: `b.createModule`, `addExecutable(.{ .root_module })`,
  `addLibrary`, `resolveTargetQuery` — 0.15/0.16 style.
- `wasm.entry = .disabled` / `rdynamic` handling differs on 0.14.
- `build.zig.zon` `minimum_zig_version` and CI `ZIG_VERSION` pin 0.16.0.

**Already 0.14-compatible:** `std.ArrayList` usage (`.empty`,
allocator-passing), `std.sort.block`, `std.mem.writeInt`, `@enumFromInt`,
`std.StaticBitSet`, `std.crypto.hash.sha2.Sha256`.

### F7 — Platform artifacts that outlive the rework

- Browser npm package (`packages/browser`) — keep, relocate to `sdk/`.
- `benchmark/` — keep, relocate to `tools/`.
- Python/Rust server packages referenced by `specs/plan.md` **do not exist** in
  the tree; with D10 (no native SDK) they are permanently out of scope.

### F8 — Stale specs

`specs/tech-architecture/*` (tech-stack.md, DESIGN_PLAN_LATEST.md,
IMPACT_LATEST.md, SECURITY_PLAN_LATEST.md, REFACTOR_LATEST.md,
TEST_PLAN_LATEST.md) describe a pre-0.16 skeleton (dead imports that no longer
exist, empty tests/, placeholder SDKs). Several are empty files. Not trusted;
the rework supersedes them.

## 4. Transport / browser assumptions audit

| Assumption | Found in | Verdict |
|------------|----------|---------|
| Core knows RabbitMQ/Kafka/HTTP/gRPC/DBs/auth | nowhere in `src/core` | ✅ already clean |
| Browser generates canonical digest | wasm root, engine.ts, docs | ❌ remove (D10) |
| Server links a static lib for other languages | native root, fingerprint.h, ci native-build | ❌ remove (D10), workers in Docker |
| WASM is stateful (init/add/scratch) | wasm root + bindings | ❌ replace with stateless process |
| `std.io` (0.16) is safe to use | serialization | ❌ 0.14 downgrade (D1) |

## 5. Test inventory (survives the rework)

`tests/features`, `tests/fingerprint` → move to `tests/model/`; `tests/hashing`,
`tests/entropy`, `tests/similarity`, `tests/risk`, `tests/normalization`,
`tests/validation` → `tests/core/`; `tests/serialization` stays; `tests/browser`
rewritten with the new exports; `tests/server/*` **deleted** with native.
`tests/data`, `tests/fixtures`, `tests/utils`, `tests/fuzz` move to
`tests/{data,fixtures,utils,fuzz}` unchanged. New suites: `tests/engine/`,
`tests/io/`, `tests/adapter/`, `tests/worker/` (detailed in MIGRATION.md).

## 6. External reference

Design draws on well-established systems patterns: completion-based async IO,
message ownership/arenas, ring buffers, single entry point with operation
dispatch, framing. Per REWORK.md: inspired, not copied.
