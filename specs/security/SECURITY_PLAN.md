# Security plan — Fingerprint Engine

Refreshed 2026-10-27 for **v0.6.0** (M7: event envelope + platform ledger
contract). Supersedes the 2026-08-08 pass; the original audit findings (H-1…H-5
in `specs/quality/audits/2026-08-08.md`) remain the numbering used below.

This plan is about what the **engine** ships. Anything a platform adds around
it — identity, tenancy, storage, retention — is listed as a platform
responsibility, not assumed.

## Trust model

The engine is compute-only and stateless (D-v1-4/D-v1-5): it has no users, no
tenants, no keys, and no database. Two processes matter:

- **worker** — speaks FPKG framing over TCP (or loopback/in-process), runs the
  engine, replies, and optionally fans out to AMQP.
- **ingress** — the only HTTP surface, terminates the browser SDK's POST,
  validates the boundary, wraps the body, and proxies to a pooled worker.

Trust boundary: **the network between ingress and worker**. Both are expected on
a private network; the engine does not authenticate the ingress, and the
documented deployment places them on the same host or a private segment. This is
a deliberate 1.0 posture (D-v1-2), not an oversight: authn/authz belongs to the
platform (M10).

## Threat model (v0.6.0)

| Asset | Exposure | Status |
|-------|----------|--------|
| Worker FPKG TCP port | private network | **H-1 closed**: idle clients are disconnected after `--idle-timeout-ms` (default 30 s; `0` disables). No authn — place on a private segment. |
| HTTP ingress | public internet | Body cap (default 1 MiB → 413 before framing) and **optional HMAC request authentication** (W6-D3). No rate limiting and no TLS termination yet (H-4/H-5) — run behind a proxy. |
| AMQP broker | private network | At-least-once fanout of replies and envelope. Credentials are CLI flags today (**known gap**, see below). |
| SignalPackage bodies | in transit | SHA-256 `x-fpkg-integrity` is tamper *evidence*; HMAC, when enabled, adds authenticity and freshness. Encryption in transit is TLS at the proxy. |
| `collection_event` envelope | broker → platform | Full signal payload plus `session_id`; the most sensitive artifact the engine emits. Encrypt at rest and restrict reads (platform-side). |
| Engine memory | in-process | Per-request arena, reset after each frame; nothing persists and no request state crosses frames. |

## What leaves the engine

Two outbound surfaces, both derived from the same request and both
platform-visible:

1. **The reply** — the unchanged `fingerprint_result` (72 bytes since D2:
   36-byte v1 prefix + `core_digest`/`core_feature_count`/`core_version`). It
   carries digests and counts, never raw signal values.
2. **`result.collection-event`** — one `collection_event` per *successful*
   collection, published **after** the reply, only when a publisher is
   configured. It is the ADR-013 JSON document and it **does contain the
   canonicalized signal values** (`signals`), plus `session_id` when supplied.

The envelope is best-effort by design: a build failure (over the **64 KiB** cap)
or a publish failure is logged and dropped, never truncated or retried in
process. Consumers must be idempotent on `package_id` and tolerate gaps; the
live reply fanout is the fallback. Nothing about the envelope handler can change
the reply the SDK receives — the reply path is unchanged and is sent first.

## Boundary limits

Every input is bounded before it is parsed, so a hostile request costs a
rejection rather than unbounded work:

| Boundary | Limit | Enforced by |
|----------|-------|-------------|
| HTTP request body | 1 MiB default (`--max-body`) → 413 | ingress, before framing |
| FPKG payload | 16 MiB | `adapter.transport`, on read *and* write |
| Envelope payload | 64 KiB; over → drop + log, never truncate | worker (`collection_event.max_payload`) |
| Session id | 1–128 bytes of `[A-Za-z0-9._:-]`; anything else → 400 | ingress |
| Nonce | 16–64 lowercase hex | ingress HMAC |
| HMAC window | 1 s – 1 h, default 300 000 ms | ingress startup validation |
| HMAC secret | ≥ 32 characters; shorter exits at startup | ingress startup validation |
| Replay cache | 65 536 slots; exhausted → 503 (no eviction) | ingress |
| TCP idle | `--idle-timeout-ms`, default 30 s | worker (H-1) |
| HTTP connection | one request per connection, `Connection: close`; chunked rejected | ingress (smuggling surface closed) |

## Replay and idempotency layers

Three independent layers, each with a different owner:

| Layer | Question | Mechanism | Owner |
|-------|----------|-----------|-------|
| Request authenticity | "did this request come from a key holder, just now?" | HMAC-SHA256 over `[collected_at, nonce, sha256(body)]` + freshness window + nonce cache | ingress (optional, W6-D3) |
| Delivery duplication | "is this the same collection arriving twice?" | SDK-minted 128-bit `package_id` (32 lowercase hex) as the ledger's primary/unique key | platform ledger |
| Content identity | "is this the same device/state?" | Deterministic digests over canonicalized signals | engine |

They are deliberately separate: a retry legitimately re-sends the same body and
therefore needs a **new nonce**, while `package_id` is what collapses the retry
at the ledger. Determinism is a security property here — the same input yields
the same digest, so silent tampering shows up as a digest change rather than as
plausible-looking drift.

## Secret handling

- **The engine holds no application secrets.** No API keys, no user
  credentials, no tenant material. There is nothing to leak from the compute
  path.
- **HMAC keys are environment-only**: `FPKG_HMAC_SECRET` and
  `FPKG_HMAC_SECRET_PREVIOUS`. Never CLI flags (visible in `ps` and shell
  history), never logged. Startup validates length and window bounds and exits
  rather than running with a weakened configuration.
- **Rotation**: set the new key as `FPKG_HMAC_SECRET` and the old one as
  `FPKG_HMAC_SECRET_PREVIOUS`, roll clients, then unset the previous key after
  one window. Both keys share one nonce space, so rotation opens no replay hole.
- **Constant-time comparison** against every accepted key without early exit,
  so rotation does not leak which key matched.
- **Log redaction**: the secret, the nonce, the timestamp, the session id, and
  the signal values are never logged. Logs carry presence and sizes only
  (`session context attached (N session bytes)`, `job detail result_len=…`), plus
  a fixed failure reason (`invalid signature`, never the MAC or key).
- **Known gap (S5/M8)**: AMQP broker credentials are still passed as
  `--amqp-user`/`--amqp-password` CLI flags (and `guest/guest` in the dev
  compose file). They are visible to any local process listing. Move them to
  environment/secret-store input, or credentials-in-URL handled without echo,
  before production fanout. Tracked, not silently accepted.

## Data at rest, PII, and the ledger

The engine has **no store** (D-v1-4): no device ledger, no AOF, no Zig-side
persistence. `deploy/ledger/` is a *contract other people own* — Postgres DDL and
a MongoDB validator, plus a generated example envelope. Consequently:

- **Encryption at rest, retention, and deletion are platform decisions.** The
  engine cannot expire a row. Apply retention to `collected_at`.
- **`signals` is device-identifying.** It includes high-entropy and potentially
  sensitive values (user agent, canvas/WebGL strings, fonts, screen metrics).
  Never expose the raw field to unauthenticated callers; read it through an
  access-controlled service.
- **`session_id`** is an opaque tenant correlation label, not an identity. The
  engine validates its shape and logs only its presence; the platform decides
  whether it is PII under its own policy.
- **`ingress_received_at = 0`** means the collection did not traverse the HTTP
  ingress; store `NULL`, never 1970. Both timestamps are epoch **milliseconds**.
- **`core_version` gates comparability.** Matching `core_digest` across different
  `core_version` values is not a verdict.
- Details: `deploy/ledger/README.md`, ADR-013.

## Platform-side scope (not built here)

Out of the engine's scope by decision, and required for a real deployment:

1. **TLS termination** and rate limiting in front of the ingress (H-4/H-5).
2. **Authn/authz and tenancy** — API keys, per-tenant quotas, request identity
   (D-v1-2; M10). The optional HMAC proves key possession, not who the caller is.
3. **Ledger storage and reads** — access control, encryption at rest, retention,
   deletion, backups, and any cross-tenant isolation of `signals`.
4. **Broker hardening** — non-guest credentials, vhost isolation, TLS, and a
   dead-letter queue for poison frames (S5/M8).
5. **Abuse response** — blocking, quota, and alerting on 401/409/413/503 rates.

## Already done

- H-1 idle timeout (completion-based deadline race, all platforms) and H-2
  graceful drain — `specs/architecture/worker-resilience.md`.
- Chunked transfer encoding rejected outright (request-smuggling surface).
- Body cap enforced before framing; FPKG payload cap on read and write.
- Optional HMAC request authentication with a bounded replay cache (W6-D3).
- `SECURITY.md` reporting policy, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`.
- dist surface guard (`src/build/dist_surface.zig`) — no wasm, no
  `hash`/`compute` identifiers in the shipped npm bundle (no fingerprinting in
  the browser).
- Zero third-party Zig dependencies; no secrets in the repo or CI.
- Docker images run non-root with `tini`.

## Open questions

1. **DLQ (S5/M8).** Poison frames are dropped today, and failed envelope
   publishes are log-and-drop. Should the worker own a bounded retry/DLQ, or
   stay fire-and-forget with the platform compensating? Current bias: keep the
   worker stateless and let the platform own durability.
2. **Worker↔ingress auth.** mTLS vs network ACL vs plaintext on a private
   segment. Now that HMAC exists at the edge, the cheapest next step is a
   shared-secret frame header rather than mTLS.
3. **AMQP credential sourcing** (§Secret handling) — env vs file vs broker-side
   federated identity.
4. **Per-process replay cache.** Multi-instance ingress means a nonce is only
   spent on the instance that saw it. Options: accept it (retries need new
   nonces anyway), or pin a client to an instance at the proxy.
5. **TLS.** Terminate at the ingress or at a reverse proxy. Current default:
   proxy.
