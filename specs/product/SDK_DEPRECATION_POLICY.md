# SDK Versioning & Deprecation Policy

- **Status:** Adopted (W4-D2, M6) — effective with SDK **1.0.0**
- **Package:** `@akshay2642005/fingerprint-sdk`
- **Scope:** the frozen public surface in
  [`SDK_API_SURFACE.md`](SDK_API_SURFACE.md) and the SignalPackage wire contract
  in [ADR-012](../decisions/0012-versioning-compatibility-adr.md).
- **Authority:** refines ADR-012 §5 into an actionable rulebook. If the two
  disagree, ADR-012 wins for the wire and this document wins for the SDK
  surface; both must be updated together.

---

## 1. What a version means

The npm package version is the only version consumers pin. It must equal
`SDK_VERSION` emitted into `dist/generated/config.js` (injected from
`package.json` by `zig build clients:browser`), and is recorded per package in
the `sdk_version` header / v2 body.

| Bump | Allowed changes | Examples |
|---|---|---|
| **patch** | Bug fixes with no observable API, type-shape, default-behavior, or wire change. | Fix a collector returning the wrong value; fix a reply-parsing bug; docs typo. |
| **minor** | Additive, backwards-compatible changes. Existing programs keep compiling and behaving the same. | New export; new optional field on a result/config type; new collector or feature id; new signal-group option; new constant; deprecation announcements. |
| **major** | Any breaking change. | Remove/rename an export; change a signature or required field; change a default behavior; raise the minimum engine version; require a new SignalPackage schema; renumber/reuse a feature id or header. |

**Rules of thumb**

- If a consumer's `tsc` can fail after the upgrade, it is **major**.
- If bytes decoded by a 1.0 engine can change, it is **at least minor** (and if
  the schema version must change, **major**).
- If only incorrect behavior is corrected and the contract is untouched, it is
  **patch**.
- When in doubt, treat it as the higher bump.

### Pre-1.0 (0.y.z)

Until 1.0.0, a minor bump may include breaking changes (standard SemVer 0.x).
Every such break must be called out under `### Changed` / `### Removed` in
`CHANGELOG.md` with a migration note. This exception ends at 1.0.0.

---

## 2. Deprecation window

A public symbol is deprecated for **two consecutive minor releases** before it
may be removed.

```
1.2.0  announce deprecation (still works)
1.3.0  first minor with the warning (still works)
1.4.0  earliest removal (major only if removal is breaking)
```

- Removal is a **major** bump. A deprecation does not itself justify a major.
- A deprecated symbol may be removed in the next major even if fewer than two
  minors shipped, provided at least **90 days** have elapsed since the
  deprecation release and the removal is documented in the major's changelog.
- Security fixes may bypass the window: a symbol may be disabled immediately
  with a patch, with a `SECURITY` note. Removing the symbol still requires a
  major; disabling its behavior is a documented emergency exception.

---

## 3. How to deprecate (mechanics)

1. **Mark the API** with TSDoc on the declaration:

   ```ts
   /**
    * @deprecated since 1.2.0 — use `packageSignals()` instead.
    * Removal: 2.0.0 (announced 1.4.0).
    */
   ```

2. **Warn at runtime, once per symbol per process.** Emit through a single
   helper so output is filtered and testable:

   ```
   [fingerprint-sdk] collectLegacy() is deprecated since 1.2.0; use packageSignals(). Removal: 2.0.0.
   ```

   - Use `console.warn` when available; never throw and never warn from a hot
     path more than once per symbol.
   - Warnings are suppressible via module state (internal), not an env var.

3. **Record it** under `### Deprecated` in `CHANGELOG.md`, naming the
   replacement and the earliest removal version.

4. **Update the contract:** mark the symbol `Deprecated since X.Y.Z` in
   `SDK_API_SURFACE.md` and add the replacement. The runtime surface test keeps
   the export until removal so the deprecation is deliberate.

5. **Keep the behavior.** A deprecated symbol must not change semantics during
   its window; the replacement ships alongside it.

Removal checklist: delete the export, delete the warning helper call, move the
entry to `### Removed` in the changelog with a migration note, bump major,
update the surface doc and the contract test, and add an ADR note if a default
behavior changed.

---

## 4. Wire compatibility (non-negotiables)

Independent of the npm version:

- Additive body fields/types are introduced only by a schema version bump when
  a 1.0 consumer cannot skip them. Skip-by-length extensions stay within
  schema 2 (capability tail precedent).
- Feature ids are **append-only**. Never renumber, never reuse a retired id.
  New ids land in a minor SDK release and a tolerant engine.
- Header names and `CodecID` values are never repurposed inside a schema the
  1.0 engine supports.
- An SDK minor must work with every engine that speaks the same
  `SignalPackage` schema version. The SDK reports its claim via `sdk_version`.

See ADR-012 for the ABI table and the dual-decode / coordinated-release rules.

---

## 5. Pinned toolchain

The published type surface must not drift because a compiler upgrade changed
emit rules.

- `typescript` is pinned to an **exact** version in
  `src/clients/browser/package.json` (no `^`/`~`). Upgrading it is its own PR
  with a regenerated `dist/` and a passing contract suite.
- `tsconfig.json` sets `"types": []`, so ambient `@types/*` packages can never
  leak into the emitted `.d.ts`. Only `lib` (`ES2020`, `DOM`, `DOM.Iterable`)
  contributes globals.
- The package exposes exactly one entry point:

  ```json
  "exports": { ".": { "types": "./dist/index.d.ts", "default": "./dist/index.js" } }
  ```

  The `types` condition stays first. Adding a subpath export is a **minor**;
  removing one is **major**.
- `types` / `main` / `module` continue to point at `dist/index.d.ts` /
  `dist/index.js` for legacy resolvers.
- CI builds with the pinned compiler (`npm install` resolves the exact pin) and
  runs the runtime surface test, so a drifted `dist/` fails loudly.

---

## 6. Review checklist

Every SDK PR that touches `src/clients/browser/`:

- [ ] Does it add or change a public symbol? If so, update
      `SDK_API_SURFACE.md`.
- [ ] Is the version bump correct (patch / minor / major), and does
      `SDK_VERSION` match `package.json`?
- [ ] If deprecating: TSDoc `@deprecated`, runtime warning, changelog
      `### Deprecated`, replacement documented.
- [ ] If removing: two-minor window (or 90 days + major), migration note,
      surface test updated.
- [ ] Wire bytes unchanged for patch/minor; feature ids append-only.
- [ ] `npm test` (contract suite) and `zig build clients:browser` green.

---

## Related

- [`SDK_API_SURFACE.md`](SDK_API_SURFACE.md) — the frozen 1.0 surface.
- [`../decisions/0012-versioning-compatibility-adr.md`](../decisions/0012-versioning-compatibility-adr.md) — wire ABI + SemVer baseline.
- [`../../CHANGELOG.md`](../../CHANGELOG.md) — release notes.
