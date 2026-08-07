# Phase 3 — Migration Plan (Fingerprint Engine Rework)

Status: Draft for approval (2026-08-07)
Principle: every commit compiles and passes `zig build test` on **Zig 0.14.1**.
Migration stays bisectable: structural moves are pure renames in their own
commits; behavior changes land behind them one layer at a time.

## 1. Old → new mapping

### Moves (pure renames, no logic change)

| From | To |
|------|-----|
| `src/core/features/model.zig` | `src/model/feature.zig` (types) |
| `src/core/features/definitions.zig` | `src/model/definitions.zig` |
| `src/core/features/registry.zig` | `src/model/registry.zig` |
| `src/core/features/root.zig` | `src/model/root.zig` (merged with fingerprint exports) |
| `src/core/fingerprint/value.zig` | `src/model/value.zig` |
| `src/core/fingerprint/feature.zig` | `src/model/feature_binding.zig` (name: avoid clash with types file) |
| `src/core/fingerprint/metadata.zig` | `src/model/metadata.zig` |
| `src/core/fingerprint/fingerprint.zig` | `src/model/fingerprint.zig` |
| `src/core/fingerprint/root.zig` | folded into `src/model/root.zig` |
| `src/core/hashing/*` | `src/core/hashing/*` |
| `src/core/entropy/*` | `src/core/entropy/*` |
| `src/core/similarity/*` | `src/core/similarity/*` |
| `src/core/risk/*` | `src/core/risk/*` |
| `src/core/normalization/*` | `src/core/normalization/*` |
| `src/core/validation/*` | `src/core/validation/*` |
| `src/core/root.zig` | `src/core/root.zig` (imports adjusted: features/fingerprint → model) |
| `src/core/serialization/*` | `src/serialization/*` |
| `tests/features/*`, `tests/fingerprint/*` | `tests/model/*` |
| `tests/hashing/*`, `tests/entropy/*`, `tests/similarity/*`, `tests/risk/*`, `tests/normalization/*`, `tests/validation/*` | `tests/core/*` |
| `tests/serialization/*` | `tests/serialization/*` |
| `tests/data/*`, `tests/fixtures/*`, `tests/utils/*`, `tests/fuzz/*` | unchanged location |
| `benchmark/` | `src/bench/` (via `tools/bench/`, commit 2) |
| `packages/browser/` | `src/clients/browser/` (via `sdk/browser/`, commit 2; D13 move in commit 3) |
| `sdk/browser/` | `src/clients/browser/` (D13; fixes the `../../..` ROOT depth bug) |
| `tools/bench/` | `src/bench/` (D13) |

### Deleted (D10 — no native SDK)

| Path | Why |
|------|-----|
| `src/server/` (native/root.zig, api/c/fingerprint.h, rust/) | no native library; workers ship in Docker |
| `tests/server/` (native_test.zig, cheader_test.zig, root.zig) | C ABI surface gone |
| CI `native-build` job | same |

### New modules

| Path | First appears |
|------|---------------|
| `src/io/` (message, ring_buffer, channel, completion, executor, frame, reader, writer, dispatcher) | commit 5 |
| `src/engine/` (operation, request, response, engine, ops/*) | commit 6 |
| `src/adapter/` (transport, loopback) | commit 8 |
| `src/adapter/amqp/codec.zig` | commit 10 |
| `src/worker/main.zig` | commit 9 |
| `deploy/Dockerfile.worker` | commit 9 |
| `src/scripts.zig` (dispatcher) + `src/scripts/` | commit 4 |
| `src/build/browser_package.zig` (dist generator) | commit 4 |
| `src/docs_website/` (nested build, `zig build docs`) | commit 4 |
| `tests/build/*` (generator tests) | commit 4 |
| `tests/io/*`, `tests/engine/*`, `tests/adapter/*`, `tests/worker/*` | with their modules |

## 2. Rewritten files

| File | Rewrite |
|------|---------|
| `build.zig` | O(1): top-level step tuple (test, wasm, bench, clients:browser, docs, scripts, scripts:build); helper fns; modules model, core, serialization, browser, browser_package, test_utils, test_core_module, bench_module; nested docs_website build |
| `build.zig.zon` | version 0.2.0 (major: breaking API), `minimum_zig_version = "0.14.1"` |
| `.github/workflows/ci.yml` | `ZIG_VERSION: 0.14.1`; jobs: test, wasm-build, worker-build (+ docker build); drop native-build |
| `src/browser/wasm/root.zig` | stateless exports (fp_version, fp_process, fp_alloc, fp_free); remove init/add_*/compute/scratch |
| `src/browser/bindings/engine.ts` | package-builder flow (collect → package → bytes); remove compute()/collectAndCompute() |
| `src/serialization/binary.zig` | v2 body + v1 compat decode; anytype writer/reader; FPKG integrity helper |
| `src/serialization/json.zig` | match v2 body; anytype |
| `src/clients/browser/package.json` | zig-only build (`zig build clients:browser -Doptimize=ReleaseSmall`); drop build.mjs + typescript devDep |
| `src/clients/browser/scripts/fingerprint-umd-template.js` | FeatureID/FeatureType blocks replaced by generator markers |
| `.github/workflows/release.yml` | publish job builds via `zig build clients:browser` (no node build) |
| `docs/architecture.md`, `docs/api.md` | new architecture; drop canonical-in-browser + native SDK |
| `CLAUDE.md`, `CONVENTIONS.md` (commands tables) | `zig build native` → `zig build worker`; Docker story |

## 3. Commit sequence (each green on 0.14.1)

1. **chore: downgrade to Zig 0.14.1 baseline** (DONE)
   `build.zig` → 0.14 API; `std.Io` → `std.io` in serialization; zon min
   version; CI pin. All existing tests green. No architecture change.
2. **refactor: relocate modules into layered tree** (DONE)
   Pure renames/moves per §1 (model, core, serialization, tests, tools, sdk).
   No logic change. Import paths updated mechanically.
3. **refactor: relocate browser SDK and bench to src/clients, src/bench**
   D13 moves: `sdk/browser/` → `src/clients/browser/` (fixes `../../..`
   ROOT depth bug in build.mjs/package.json), `tools/bench/` → `src/bench/`;
   `release.yml` path update. Pure renames; gates stay green.
4. **build: build-system unification**
   O(1) build.zig (step tuple + helpers, preferred ReleaseSafe);
   `src/scripts.zig` dispatcher (help-only) + `scripts:build`;
   `src/build/browser_package.zig` Zig generator (wasm base64-inlined UMD,
   ESM, `.d.ts` with FeatureID/FeatureType derived from model) replacing
   `build.mjs`; template markers; zig-only `package.json` build;
   `src/docs_website/` nested build (`zig build docs`); `tests/build/*`;
   release.yml uses `zig build clients:browser`.
5. **feat(io): async IO primitives**
   message, ring_buffer, channel, completion, executor, reader, writer, frame,
   dispatcher + `tests/io/`.
6. **feat(engine): Request/Response/Operation/process**
   operation, request, response, engine with comptime dispatch, ops/* over the
   existing core algorithms + `tests/engine/` (dispatch, determinism, replay
   goldens, unknown-version).
7. **feat(serialization): FPKG envelope + v2 body + integrity + codec interface**
   Envelope framing in `io/frame.zig`; binary v2 + v1 compat; json; codec
   interface; integrity SHA-256; `tests/serialization/` extended. Old fixtures
   converted to compat goldens.
8. **feat(adapter): transport interface + loopback**
   comptime Transport contract, loopback transport (in-memory + stdin/stdout
   framing) + `tests/adapter/`.
9. **feat(worker): executable + Docker**
   `worker/main.zig` with `--transport=loopback`, e2e pipe tests
   (`tests/worker/`), `deploy/Dockerfile.worker`, worker CI job.
10. **feat(adapter): AMQP 0-9-1 codec (v1)**
    `adapter/amqp/codec.zig` framing + byte-fixture tests. No broker needed.
11. **feat(browser): stateless WASM + TS package builder**
    Rewrite wasm exports and bindings; drop canonical digest; keep collectors;
    `tests/browser/` updated. WASM used for bench + test containers.
12. **docs: final docs + spec cleanup**
    `docs/{Architecture,Engine,IO,Worker,AMQP,Serialization,Migration,Design}.md`;
    update CLAUDE.md/CONVENTIONS.md; remove stale `specs/tech-architecture/*`
    or mark superseded.

Each commit keeps `zig build test` green; wasm/worker artifacts build from
commit 1 onward (targets adjusted as modules appear). The rework is never a
single big-bang rewrite — behavior changes are confined to commits 5–11, each
with its own tests.

## 4. Gate checklist per commit

- [ ] `zig build test --summary all` green (0.14.1)
- [ ] `zig build wasm` green (from commit 1; updated surface from commit 11)
- [ ] `zig build worker` green (from commit 9)
- [ ] `zig build bench` compiles (from commit 2, relocated to src/bench in commit 3)
- [ ] `zig build clients:browser` green (from commit 4; npm package dist/ produced by Zig)
- [ ] `zig build docs` green (from commit 4)
- [ ] `zig build scripts -- help` green (from commit 4)
- [ ] No new warnings; files under 300 lines; no dead imports (CONVENTIONS)

Note: the sandbox terminal is broken (libasound.so.2) — gates must be run by
the user locally until the sandbox is fixed; the migration plan is sequenced so
each commit is independently verifiable.

## 5. Risks

| Risk | Mitigation |
|------|------------|
| 0.14.1 std.io differences break serialization mid-flight | commit 1 isolates all downgrade work; serialization rewritten to anytype in commit 7, removing std.io dependency |
| Envelope/version churn invalidates stored fixtures | fixtures kept as v1 compat goldens; new v2 fixtures generated by the codec itself (round-trip) |
| Async-first io scope creep | v1 ships exactly the primitives in DESIGN §6; Pipeline/Command deferred |
| AMQP client scope (v2) stalls the rework | v1 = codec only, tested without broker; client is a separate story after the engine lands |
| Dropping native SDK breaks documented consumers | SemVer major (0.2.0); Migration.md + docs make the Docker story the replacement |
| WASM regression (canonical digest sneaks back in) | `hash` op not exported by wasm root; `tests/browser/` asserts the export surface |

## 6. Success criteria

- All commits bisectable and green on Zig 0.14.1.
- Browser emits only `SignalPackage` (validated, normalized, integrity-hashed);
  canonical digest produced exclusively by workers.
- Engine has zero imports of io/adapter/transport std networking.
- `tests/engine`, `tests/io`, `tests/adapter`, `tests/worker` exist and pass.
- `src/server/` gone; `deploy/Dockerfile.worker` present; CI builds worker.
- Docs: 8 deliverables in `docs/`.
