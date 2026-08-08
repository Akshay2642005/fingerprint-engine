# Impact analysis — Fingerprint Engine (current)

Refreshed 2026-08-08. Records the impact of (a) the completed distributed
rework and (b) the planned backlog slices.

## Impact of the rework (shipped v0.2.0–v0.2.2)

| Area | Change | Impact |
|------|--------|--------|
| Toolchain | Zig 0.16 → 0.14.1 | All builds must use 0.14.1; no `-Doptimize`; std APIs after 0.14 off-limits |
| Repository | Layered `src/` tree | Clear dependency direction; engine provably transport-free |
| Browser package | WASM/UMD → hand-written TS | Consumers get real source; no in-browser fingerprint; new `configure`/`collect` API (breaking, v0.2.0) |
| Canonical fingerprint | Browser → workers | Canonical digest only in Docker workers; browser needs ingress URL |
| Native SDK / C ABI | Removed | No native consumers; container-only deployment (breaking) |
| Wire format | Raw TLV → FPKG + SignalPackage v2 | Versioned, integrity-checked, lossless, replayable; v1 compat retained |
| Event transport | — → AMQP (outbound) | Fraud platform consumes durable `result.<message-type>` events |
| npm publishing | Manual → OIDC trusted publisher | Automated, no token; idempotent skip on re-runs |
| GHCR | — → worker image | Container deployment story (lowercase tags) |

## Impact of planned slices

| Slice | Impact | Risk if skipped |
|-------|--------|-----------------|
| S1 | SDK metadata correct; tcp transport self-healing; clean shutdown | Wrong digest metadata in every SDK reply; remotely wedge-able worker; dirty orchestrated rollouts |
| S2 | One version source | Continuing version drift on every release (worker/AMQP/wasm advertise stale versions) |
| S3 | Structured, leveled logging | Ops can't triage; `amqp get` noise |
| S4 | Ingress + HTTP surface | No browser→worker path in production; SDK has nowhere to POST |
| S5 | AMQP consumer + DLQ | Poison/unroutable messages vanish (worker logs-and-drops) |
| S6 | Full-stack compose + release surface | No reproducible local dev stack; ingress image not published |

## Cross-cutting concerns

- **Determinism/replay** is load-bearing for the distributed design: any
  worker can process any package, retries are idempotent, and the e2e tests
  pin one canonical digest (`db29fc13…e6c75`).
- **Security posture** (H-4/H-5): the ingress will be the only public
  surface; auth/rate-limit/TLS and body-size policy must land with or before
  S4 (see `specs/security/SECURITY_PLAN.md`).
- **Repo boundary**: the fraud platform (Go) is out of repo; this repo's
  impact on it is limited to the event contracts it defines.
