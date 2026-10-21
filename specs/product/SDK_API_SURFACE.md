# SDK Public API Surface — frozen for 1.0

- **Status:** FROZEN (W4-D1, M6)
- **Package:** `@akshay2642005/fingerprint-sdk`
- **Entry point:** `dist/index.js` / `dist/index.d.ts` (`exports` exposes `"."` only)
- **Contract:** this file is the SDK 1.0 public contract. Anything not listed
  here is internal. Adding a symbol beyond this surface is feature work and
  requires a **minor**; removing or changing a listed symbol requires a
  **major** (see ADR-012 §5 and the deprecation policy from W4-D2).
- **Supersedes:** nothing; the 0.4.x surface is a strict subset except where
  noted under [§9 Changes at the freeze](#9-changes-at-the-freeze).

The browser SDK never computes the canonical fingerprint. It collects browser
signals, serializes a `SignalPackage` v2 body, and POSTs it to the ingress.
Workers validate, normalize, hash, and score; the platform makes the decision.

---

## 1. Official surface (supported)

These are the functions a normal integrator uses. All are named exports and are
also members of the default export.

### `configure(options: Partial<SdkConfig>): void`

Sets runtime configuration. Merges into the current config; calling it again
replaces only the provided keys. If `wsUrl` is set, opens the decision socket
and wires pushes into the decision gate.

- `SdkConfig.ingressUrl` defaults to the build-time value injected by
  `--ingress-url` / `FINGERPRINT_INGRESS_URL`.
- Must be called before `collect()` for a non-default ingress.
- Does not throw for invalid URLs; the transport reports the failure on
  `collect()`.

### `packageSignals(options?: CollectOptions): Promise<PackageResult>`

Collects signals and serializes the SignalPackage v2 body **without sending**
it — the roadmap's `package()` step.

```ts
const pkg = await packageSignals();
// pkg.packageId — 16-byte replay identity
// pkg.bytes     — exact wire body
// pkg.hex       — hex of bytes
// pkg.signalCount
```

Use this to persist, relay, sign, or inspect the bytes, or to feed a
non-`fetch` transport. It never performs I/O.

**Naming note:** the roadmap and DESIGN call this step `package()`. The ES
module identifier is `packageSignals` because `package` is a strict-mode
reserved word and cannot be used as a binding/function name in a module. This
is a language constraint, not a design change; `package()` remains the
conceptual name.

### `collect(options?: CollectOptions): Promise<CollectResult>`

`packageSignals()` followed by `sendPackage()`. Resolves with the package plus
the transport outcome. **Does not throw on network or HTTP failures** — inspect
`sent`, `status`, `reply`, and `error`.

```ts
const result = await collect();
if (!result.sent) {
  console.warn("ingress not reached", result.status, result.error);
}
```

### `assertAllowed(): BlockDecision`

Returns the last-known decision for the session
(`{ blocked: boolean, reason?, expiresAt? }`). Defaults to
`{ blocked: false }` before any decision arrives. A UX gate only: the app
remains the authority and must enforce sensitive actions server-side.

### `onSessionBlocked(callback: (decision: BlockDecision) => void): () => void`

Registers a listener for `session.blocked` pushes (from the decision socket).
Returns an unsubscribe function. Listener exceptions propagate to the emitter;
listeners should not throw.

### `getFeatureIDs(): FeatureID[]`

Returns the numeric feature ids known to this SDK build, in table order. For
introspection and logging.

---

## 2. Low-level / advanced surface (supported, stability-caveated)

These are exported for advanced integrations and tests. They are part of the
frozen surface, so their signatures follow the same SemVer rule; however they
operate at the wire layer and are documented as advanced.

| Export | Signature | Purpose |
|---|---|---|
| `encodeSignalPackage` | `(signals: Signal[], options: SignalPackageOptions) => Uint8Array` | Serialize a SignalPackage v2 body (capability tail included). Throws on invalid signal values. |
| `newPackageId` | `() => Uint8Array` | 16 random bytes for replay identity. |
| `toHex` | `(bytes: Uint8Array) => string` | Lowercase hex. |
| `sendPackage` | `(bytes, config, headers: PackageHeaders) => Promise<SendResult>` | POST a body to the ingress; parses the relayed worker reply. |
| `connectDecisionSocket` | `(config: SdkConfig, onDecision) => () => void` | Open the platform decision socket; returns a disconnect function. No-op without `wsUrl`. |
| `DecisionGate` | `class` | Decision state holder behind `assertAllowed`/`onSessionBlocked`; use it for multiple independent gates. |

`PackageHeaders` is exported from the transport module but is **not** re-exported
by the package entry point; pass a structural equivalent.

---

## 3. Constants

| Export | Value / type | Meaning |
|---|---|---|
| `SDK_VERSION` | `string` | Version injected at build time. |
| `SCHEMA_VERSION` | `number` (`2`) | SignalPackage body schema. |
| `MAGIC` | `"FNGR"` | SignalPackage magic bytes. |
| `FeatureID` | enum-like object | Numeric feature ids (locked 0–101 per M6). |
| `FeatureType` | enum-like object | Wire value types for signals. |

`FeatureID` and `FeatureType` are public because `Signal` (used with
`encodeSignalPackage`) is typed in terms of them. New ids/types are additive
(minor); renumbering is breaking (major).

---

## 4. Types

All are type-only exports from the entry point:

`Signal`, `SignalValue`, `CollectOptions`, `PackageResult`, `CollectResult`,
`SendResult`, `SdkConfig`, `BlockDecision`, `WorkerReply`.

`SignalPackageOptions` (the second argument of `encodeSignalPackage`) is
declared in `types.ts` and appears in the emitted `.d.ts`, but is not
re-exported from `index.ts`; the entry-point list in §5 is authoritative.
`PackageHeaders` is likewise not re-exported.

Key shapes:

```ts
interface PackageResult {
  packageId: Uint8Array;   // 16 bytes
  bytes: Uint8Array;       // serialized body
  hex: string;
  signalCount: number;
}

interface CollectResult extends PackageResult {
  sent: boolean;           // ingress returned 2xx
  status?: number;         // HTTP status; 0 when the request never completed
  reply?: WorkerReply;     // relayed worker frame, when present
  error?: string;          // transport failure detail (sent === false)
}
```

---

## 5. Entry-point export list (exact)

Value exports from `dist/index.js`:

```
configure, packageSignals, collect, assertAllowed, onSessionBlocked,
getFeatureIDs, encodeSignalPackage, newPackageId, toHex, sendPackage,
connectDecisionSocket, DecisionGate, FeatureID, FeatureType, MAGIC,
SCHEMA_VERSION, SDK_VERSION
```

Type exports from `dist/index.d.ts`:

```
Signal, SignalValue, CollectOptions, CollectResult, PackageResult,
SendResult, SdkConfig, BlockDecision, WorkerReply
```

Default export:

```
{ configure, packageSignals, collect, assertAllowed, onSessionBlocked, getFeatureIDs }
```

**Not public:** `collectSignals` and the individual collectors, the generated
tables beyond `FeatureID`/`FeatureType`, and deep `dist/*` paths. Deep imports
are unsupported even if physically reachable; use the entry point.

---

## 6. Error contract

| Situation | Behavior |
|---|---|
| Network failure / thrown `fetch` | `collect()` resolves: `sent: false`, `status: 0`, `error: <message>` |
| Non-2xx HTTP response | `collect()` resolves: `sent: false`, `status: <code>`, `error` absent; `reply` present if the ingress relayed a worker frame |
| 2xx response | `collect()` resolves: `sent: true`, `status: <code>`, `reply` when relayed |
| 2xx with an unreadable reply body | `collect()` resolves: `sent: true`, `status: <code>`, `error: "failed to read ingress reply: …"` |
| Invalid signal value passed to `encodeSignalPackage` | **throws** `Error` |
| Worker rejects the package | `sent: true` (ingress accepted), `reply.status !== 0` |
| `configure()` with a bad URL | no throw; surfaces on the next `collect()` |

The SDK throws only for programmer errors in the low-level encoder. All runtime
I/O outcomes are returned as data.

---

## 7. Explicitly outside the 1.0 surface

- A class/constructor-based client. `configure()` is the configuration entry
  point; the module keeps a single SDK config and gate.
- Per-signal inspection of collection results (`CollectResult` carries counts
  and bytes, not the `Signal[]`). Use `encodeSignalPackage` with your own
  `Signal[]`, or rely on the worker/event payload.
- Any client-side fingerprint computation or hashing API (see
  `src/build/dist_surface.zig`, which fails the build if such identifiers leak
  into the public `.d.ts`).
- Retries, batching, queues, consent gating, and sampling. Callers compose
  `packageSignals()` / `sendPackage()` for those workflows.

---

## 8. Freeze rule

From W4-D1 onward:

- **No new public symbols** without a minor release and an update to this doc.
- **No renames or removals** without a major release; deprecate for two minors
  first (W4-D2 policy).
- **No signature changes** to the symbols above without a major release.
- Internal modules may change freely as long as the surface and wire bytes hold.
- The runtime contract suites (`tests/clients/browser/api_surface.test.mjs` and
  `contract.test.mjs`) plus the type-level check
  (`tests/clients/browser/types/surface.ts`, `npm run test:types`) guard the
  export list, signatures, wire round trip, and `collect()` error paths; they
  must stay green.

---

## 9. Changes at the freeze

Added relative to 0.4.1 (all additive, hence 1.0.0 rather than 2.0.0):

- `packageSignals()` and `PackageResult` — collect-without-send.
- `CollectResult.error` and `CollectResult.status` — transport failures are
  now observable instead of being reduced to `sent: false`.
- `collect()` is now defined as `packageSignals()` + `sendPackage()`; observable
  behavior is otherwise unchanged.

Nothing was removed from the 0.4.1 surface.

---

## Related

- `specs/decisions/0012-versioning-compatibility-adr.md` — wire + SDK versioning.
- `specs/quality/signal-determinism-contract.md` — stable-core subset (what the
  engine guarantees over time).
- `src/clients/browser/src/index.ts` — the surface itself.
