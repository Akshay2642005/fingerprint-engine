# SDK Release Conventions (npm 1.0.0)

- **Status:** Adopted (W4-D4, M6)
- **Package:** `@akshay2642005/fingerprint-sdk`
- **Pipeline:** `.github/workflows/release.yml` → `publish-npm`
- **Related:** [`SDK_DEPRECATION_POLICY.md`](SDK_DEPRECATION_POLICY.md),
  [`SDK_API_SURFACE.md`](SDK_API_SURFACE.md), ADR-012.

---

## 1. Version source of truth

`src/clients/browser/package.json` is the only version input.

`zig build clients:browser` reads it and emits
`src/clients/browser/src/generated/config.ts`:

```ts
export const SDK_VERSION = "<package.json version>";
```

Consequences:

- **Bump, then build.** The generated `dist/` carries the version that was in
  `package.json` at build time. Changing `package.json` after a build produces
  an artifact whose `SDK_VERSION` disagrees with the tarball version.
- `tests/clients/browser/api_surface.test.mjs` asserts
  `SDK_VERSION === package.json.version`, so this fails locally and in CI.
- Never hand-edit `generated/config.ts`; it is regenerated.

## 2. Tag ↔ version contract

The release workflow derives the expected version from the tag
(`v1.0.0-rc.1` → `1.0.0-rc.1`). `publish-npm` now **fails** if the tag does not
match `package.json` (it previously would have published whatever version was
in the file while checking idempotency against the tag).

Rules:

- Tag format is `v<semver>`; the version must equal `package.json`.
- A tag pushes the engine *and* SDK release together. If the change is
  SDK-only, still bump and tag — the pipeline is idempotent for unchanged
  artifacts.
- The engine release version and the SDK version are independent numbers. A
  `v0.5.0` engine cut may ship SDK `1.0.0-rc.N`; record both in the release
  notes.

## 3. Dist-tags

| Version shape | npm dist-tag | Example |
|---|---|---|
| Stable (`x.y.z`) | `latest` | `1.0.0` |
| Pre-release (`-rc.N`, `-beta.N`) | `next` | `1.0.0-rc.1` |

`release.yml` selects the tag automatically (`*-*` → `next`, otherwise
`latest`). Never publish a pre-release to `latest`: consumers using
`npm install @akshay2642005/fingerprint-sdk` must not receive an RC.

Promotion to stable is a normal `npm publish` with `latest`; do not move the
`next` tag to a stable build.

## 4. Canary procedure

1. Bump `src/clients/browser/package.json` to the canary version
   (e.g. `1.0.0-rc.1`). Commit it through a PR to `develop`.
2. Build and verify:

   ```sh
   PATH="$PWD/src/clients/browser/node_modules/.bin:$PATH" zig build clients:browser
   cd src/clients/browser && npm run verify
   ```

3. Rehearse the artifact without publishing:

   ```sh
   npm pack --pack-destination "$TMPDIR"
   npm publish --dry-run --tag next --access public
   ```

4. Install the tarball in a **clean** consumer and smoke it:

   ```sh
   npm install "$TMPDIR"/akshay2642005-fingerprint-sdk-<version>.tgz
   node smoke.mjs   # import the entry point, call packageSignals(), check SDK_VERSION
   ```

5. Publish for real only through the OIDC workflow: tag `v<version>` and let
   `publish-npm` run. Local `npm publish` is intentionally unauthenticated.
6. Verify from the registry:

   ```sh
   npm view @akshay2642005/fingerprint-sdk@<version> version dist.tarball
   npm view @akshay2642005/fingerprint-sdk dist-tags
   ```

**Recorded W4-D4 rehearsal (2026-10-21):** built `1.0.0-rc.1` from a bumped
`package.json`, packed 38 files (24.1 kB, 83.9 kB unpacked), `npm publish
--dry-run --tag next` succeeded, and a clean consumer resolved the package,
reported `SDK_VERSION = 1.0.0-rc.1`, `MAGIC = FNGR`, schema `2`, 16-byte package
id, and 45 signals. No registry write was made.

## 5. OIDC trusted publishing

`publish-npm` uses npm trusted publishing (OIDC), not a long-lived token:

- Job permissions: `id-token: write`, `contents: read`.
- Node 24 + `actions/setup-node@v4` with `registry-url`.
- `npm publish` exchanges the GitHub OIDC token; no `NODE_AUTH_TOKEN` secret.
- Idempotency: before publishing, the job runs
  `npm view "$PACKAGE@$VERSION" version`; if it exists, it logs and exits 0.
  Re-running a tag therefore cannot double-publish.
- The job rebuilds `dist/` from the tagged commit (`npm run build` via
  `prepublishOnly`), so the tarball always matches the tag.

## 6. Pre-publish guards

- `npm run verify` — typecheck, type-level surface, runtime contracts
  (28 tests).
- `zig build clients:browser` — dist surface guard (no wasm/hash surface).
- `zig build test --summary all` — engine suite.
- `api_surface.test.mjs` — version agreement and single typed export.
- `contract.test.mjs` — collect→package→POST wire/error contract.
- The tag↔version check in `release.yml`.

## 7. CHANGELOG conventions for 1.0.0

- Keep unreleased work under `## [Unreleased]`; on the canary cut, move the SDK
  entries under `## [1.0.0-rc.N] - YYYY-MM-DD` with a
  `> Pre-release — install with @next` note.
- The stable `1.0.0` section must call out, at minimum: the frozen surface
  (`SDK_API_SURFACE.md`), `packageSignals()`, `CollectResult.status`/`error`,
  the SemVer + deprecation policy, and the pinned TypeScript toolchain.
- Breaking changes since the last stable use `### Changed` / `### Removed` with
  a migration note, per `SDK_DEPRECATION_POLICY.md`.

## 8. 1.0.0 final checklist

- [ ] `package.json` version is `1.0.0`; full `npm run verify` green.
- [ ] `SDK_API_SURFACE.md` has no `Deprecated since` entry whose removal is
      due earlier than 1.0.0.
- [ ] Changelog section written with the required call-outs.
- [ ] `npm publish` with `latest` via OIDC; `dist-tags` shows `latest: 1.0.0`.
- [ ] Clean-consumer install pinned to `1.0.0` runs `packageSignals()` and
      `collect()` (mocked ingress) successfully.
