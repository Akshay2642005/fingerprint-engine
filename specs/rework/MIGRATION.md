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
| `src/io/` (message, ring_buffer, channel, completion, executor, frame, reader, writer, dispatcher) | commit 8 |
| `src/engine/` (operation, request, response, engine, ops/*) | commit 9 |
| `src/adapter/` (transport, loopback, tcp) | commit 11 |
| `src/adapter/amqp/codec.zig` | commit 13 |
| `src/worker/main.zig` | commit 12 |
| `deploy/Dockerfile.worker` | commit 12 |
| `src/scripts.zig` (dispatcher) + `src/scripts/` | commit 5 |
| `src/build/browser_package.zig` (dist generator) | commit 5 |
| `src/docs_website/` (nested build, `zig build docs`) | commit 5 |
| `tests/build/*` (generator tests) | commit 5 |
| `src/integration_tests.zig`, `src/testing/shell.zig` (e2e harness) | commit 7 |
| `src/clients/browser/src/*` (TS SDK: index, collectors, package, transport) | commit 14 |
| `tests/io/*`, `tests/engine/*`, `tests/adapter/*`, `tests/worker/*` | with their modules |

## 2. Rewritten files

| File | Rewrite |
|------|---------|
| `build.zig` | O(1): top-level step tuple (test, wasm, bench, clients:browser, docs, scripts, scripts:build); helper fns; modules model, core, serialization, browser, browser_package, test_utils, test_core_module, bench_module; nested docs_website build |
| `build.zig.zon` | version 0.2.0 (major: breaking API), `minimum_zig_version = "0.14.1"` |
| `.github/workflows/ci.yml` | `ZIG_VERSION: 0.14.1`; jobs: test, wasm-build, worker-build (+ docker build); drop native-build |
| `src/browser/wasm/root.zig` | stateless exports (fp_version, fp_process, fp_alloc, fp_free); infra-only artifact (bench + wasmtime test containers); remove init/add_*/compute/scratch |
| `src/clients/browser/src/*` | hand-written TS SDK (D14/D17): index.ts, collectors/, package.ts (SignalPackage v2 serializer), transport.ts (POST to ingress + WS), middleware.ts (assertAllowed/onSessionBlocked) — replaces the UMD template |
| `src/clients/browser/index.d.ts` | hand-written declarations |
| `src/clients/browser/scripts/fingerprint-umd-template.js` | **deleted** — superseded by the hand-written TS SDK (D14); no more base64-wasm-inlined bundle |
| `src/serialization/binary.zig` | v2 body + v1 compat decode; anytype writer/reader; FPKG integrity helper |
| `src/serialization/json.zig` | match v2 body; anytype |
| `src/clients/browser/package.json` | zig-only build (`zig build clients:browser`); drop build.mjs + typescript devDep; TS compile step is the documented exception (D13/D14) |
| `tests/data/fixtures/*` | shared golden vectors consumed by BOTH the Zig codec tests and the TS package.ts tests (cross-language parity, D14) |
| `.github/workflows/release.yml` | publish job builds via `zig build clients:browser` (no node build) |
| `docs/architecture.md`, `docs/api.md` | new architecture; drop canonical-in-browser + native SDK; document inbound request/response + outbound AMQP events + blocking surface (D16/D17) |
| `CLAUDE.md`, `CONVENTIONS.md` (commands tables) | `zig build native` → `zig build worker`; Docker story |

## 3. Commit sequence (each green on 0.14.1)

1. **chore: downgrade to Zig 0.14.1 baseline** (DONE)
   `build.zig` → 0.14 API; `std.Io` → `std.io` in serialization; zon min
   version; CI pin. All existing tests green. No architecture change.
2. **refactor: relocate modules into layered tree** (DONE)
   Pure renames/moves per §1 (model, core, serialization, tests, tools, sdk).
   No logic change. Import paths updated mechanically.
3. **docs(specs): adopt build and layout convention (D13)** (DONE)
   Locks the repository layout and zig-only build pipeline.
4. **refactor: move browser SDK and bench to src/clients, src/bench** (DONE)
   D13 moves: `sdk/browser/` → `src/clients/browser/` (fixes `../../..`
   ROOT depth bug in build.mjs/package.json), `tools/bench/` → `src/bench/`;
   `release.yml` path update. Pure renames; gates stay green.
5. **build: build-system unification** (DONE)
   O(1) build.zig (step tuple + helpers, preferred ReleaseSafe);
   `src/scripts.zig` dispatcher (help-only) + `scripts:build`;
   `src/build/browser_package.zig` Zig generator (wasm base64-inlined UMD,
   ESM, `.d.ts` with FeatureID/FeatureType derived from model) replacing
   `build.mjs`; template markers; zig-only `package.json` build;
   `src/docs_website/` nested build (`zig build docs`); `tests/build/*`;
   release.yml uses `zig build clients:browser`. The base64-wasm-inlined
   UMD approach is superseded by the D14 TS SDK in commit 14.
6. **test: adopt self-verifying test registry** (DONE)
   `tests/root.zig` self-verifying quine registry discovers and imports every
   test file under `tests/`; `SNAP_UPDATE=1` regenerates the import list.
   `zig build test -- <filter>` runs only matching tests.
7. **test: integration and e2e smoke tests**
   `src/integration_tests.zig` (test binary contains no engine code,
   drives pre-built executables as subprocesses), `src/testing/shell.zig`
   helper, steps `test-integration` /
   `test-integration-build` with exe paths injected via build options;
   scripts/bench e2e smokes. `zig build test` runs the integration suite when
   no filter is given. The worker pipe e2e lands in commit 12.
8. **feat(io): async IO primitives**
   message, ring_buffer, channel, completion, executor, reader, writer, frame,
   dispatcher + `tests/io/`.
9. **feat(engine): Request/Response/Operation/process**
   operation, request, response, engine with comptime dispatch, ops/* over the
   existing core algorithms + `tests/engine/` (dispatch, determinism, replay
   goldens, unknown-version).
10. **feat(serialization): FPKG envelope + v2 body + integrity + codec interface**
    Envelope framing in `io/frame.zig`; binary v2 + v1 compat; json; codec
    interface; integrity SHA-256; `tests/serialization/` extended. Old fixtures
    converted to compat goldens.
11. **feat(adapter): transport interface + loopback + tcp**
    comptime Transport contract, loopback transport (in-memory + stdin/stdout
    framing), FPKG-framed TCP request/response server (ingress→worker path,
    D16) + `tests/adapter/`.
12. **feat(worker): executable + Docker**
    `worker/main.zig` with `--transport=loopback|tcp` and
    `--publish=amqp|none` (D16), e2e pipe test in `src/integration_tests.zig`
    (spawn worker, feed SignalPackage over stdin, assert canonical
    fingerprint on stdout) + tcp request/response e2e,
    `deploy/Dockerfile.worker`, worker CI job.
13. **feat(adapter): AMQP 0-9-1 codec (v1)**
    `adapter/amqp/codec.zig` framing + byte-fixture tests, generated from
    the official AMQP 0-9-1 spec XML (D20 — TigerBeetle CDC reference).
    No broker needed.
14. **feat(browser): hand-written TS SDK (D14/D17)**
    `src/clients/browser/src/` — index.ts, types.ts, collectors/
    (plain `Signal[]`, no engine buffer), package.ts (SignalPackage v2
    serializer mirroring `serialization/binary.zig`, contract DESIGN §9.4.4),
    transport.ts (POST to the ingress URL — `--ingress-url` option /
    `FINGERPRINT_INGRESS_URL` env / default, headers §9.4.5 — plus a WS
    client for `session.blocked`), middleware.ts (`assertAllowed`/
    `onSessionBlocked`). The generator writes `generated/{tables,config}.ts`
    (FeatureID/FeatureType + version + ingress URL) and `tsc` compiles ESM +
    version + ingress URL) and `tsc` compiles ESM into `dist/` (documented
    Node exception, D13; single ESM emit, `exports` map with `types`/
    `default` conditions). Delete the UMD
    template + base64 wasm inlining; drop wasm from the package (wasm stays
    in-repo for bench + wasmtime test containers). Cross-language golden
    tests: TS serializer vs Zig fixtures via the signals manifest (DESIGN
    §9.4.6); Zig guard run by `clients:browser` asserts the dist surface has
    no wasm/hash. `tests/browser/`
    + TS test suite updated.
15. **docs: final docs + spec cleanup**
    `docs/{Architecture,Engine,IO,Worker,AMQP,Serialization,Migration,Design}.md`;
    Architecture/Worker docs cover the transport split and blocking surface
    (D16/D17); update CLAUDE.md/CONVENTIONS.md; remove stale
    `specs/tech-architecture/*` or mark superseded.

Each commit keeps `zig build test` green; wasm/worker artifacts build from
commit 1 onward (targets adjusted as modules appear). The rework is never a
single big-bang rewrite — behavior changes are confined to commits 5–11, each
with its own tests.

## 4. Gate checklist per commit

- [ ] `zig build test --summary all` green (0.14.1)
- [ ] `zig build test-integration` green (from commit 7)
- [ ] `zig build wasm` green (from commit 1; updated surface from commit 14)
- [ ] `zig build worker` green (from commit 12)
- [ ] `zig build bench` compiles (from commit 2, relocated to src/bench in commit 4)
- [ ] `zig build clients:browser` green (from commit 5; npm package dist/ produced by Zig)
- [ ] `zig build docs` green (from commit 5)
- [ ] `zig build scripts -- help` green (from commit 5)
- [ ] No new warnings; files under 300 lines; no dead imports (CONVENTIONS)

Gates run in the sandbox terminal; `zig build test -- <filter>` must stay
unit-only (integration is excluded when a filter is given).

## 5. Risks

| Risk | Mitigation |
|------|------------|
| 0.14.1 std.io differences break serialization mid-flight | commit 1 isolates all downgrade work; serialization rewritten to anytype in commit 7, removing std.io dependency |
| Envelope/version churn invalidates stored fixtures | fixtures kept as v1 compat goldens; new v2 fixtures generated by the codec itself (round-trip) |
| Async-first io scope creep | v1 ships exactly the primitives in DESIGN §6; Pipeline/Command deferred |
| AMQP client scope (v2) stalls the rework | v1 = codec only, tested without broker; client is a separate story after the engine lands |
| Dropping native SDK breaks documented consumers | SemVer major (0.2.0); Migration.md + docs make the Docker story the replacement |
| WASM regression (canonical digest sneaks back into the browser) | no wasm shipped in the SDK; `hash` op not exported; SDK has no compute path; `tests/browser/` + TS tests assert the surface |
| TS package.ts serializer drifts from the Zig codec | shared golden fixtures run against both implementations (cross-language parity tests, D14) |

## 6. Success criteria

- All commits bisectable and green on Zig 0.14.1.
- Browser SDK is hand-written TS emitting only a versioned `SignalPackage`
  (with integrity); canonical digest produced exclusively by workers; no
  wasm/base64 inside the npm package.
- Fraud-platform boundary documented: engine publishes typed events; Go
  repo owns Postgres rules, admin workspace, AI agents (D15).
- Engine has zero imports of io/adapter/transport std networking.
- `tests/engine`, `tests/io`, `tests/adapter`, `tests/worker` exist and pass.
- `src/server/` gone; `deploy/Dockerfile.worker` present; CI builds worker.
- Docs: 8 deliverables in `docs/`.
