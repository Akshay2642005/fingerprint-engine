# Security plan — Fingerprint Engine

Refreshed 2026-08-08 from the audit (H-1…H-5 in `specs/quality/audits/2026-08-08.md`).

## Threat model (current, v0.5.0)

The shipped attack surface today is small: the worker's TCP transport
(`--transport=tcp`) and the AMQP client. The planned ingress becomes the only
public surface.

| Asset | Exposure | Notes |
|-------|----------|-------|
| Worker FPKG tcp port | LAN/trusted network today | No auth; H-1 idle timeout missing → remotely wedge-able |
| AMQP broker | trusted network | guest/guest in compose dev only |
| HTTP ingress | public internet | Body cap (413) and optional HMAC request authentication are in place; rate limits and TLS termination still pending (H-4/H-5) |
| SignalPackage bodies | transit (HTTPS once TLS lands) | SHA-256 integrity header is tamper-evidence; HMAC (when enabled) adds authenticity + freshness |

## Principles

- **The engine never sees secrets**: no keys, no auth, no users (D5).
  Integrity is SHA-256 (tamper/corruption detection); authenticity is the
  ingress/adapter's job (API key / mTLS — TBD in S4 review).
- **Determinism as a security property**: same input → same output means
  replay attacks are detectable via `package_id` dedupe and the pinned
  digest; the engine is stateless so there is no cross-request state to
  poison.
- **Boundary validation**: input is validated at every trust boundary —
  HTTP body cap (413), FPKG payload cap (16 MiB), engine-level schema/type
  validation.

## Actions by slice

| Slice | Action |
|-------|--------|
| S1 | H-1 socket idle timeout (completion-based deadline race over the new `src/io/` layer — epoll/IOCP/kqueue — surfacing `error.ConnectionTimedOut` on every platform; `SO_RCVTIMEO` is dead on Windows, see `specs/architecture/worker-resilience.md`). H-2 graceful shutdown (drain before exit, bounded accept). |
| S2 | Version SSoT (accurate versioning is a supply-chain hygiene property). |
| S3 | Structured logging with `--log-format`; no secrets in log fields. |
| S4 | H-4/H-5: decide auth (network ACL / mTLS worker↔ingress, optional API key on HTTP), rate limiting, TLS termination, body-size policy (default 1 MiB → 413 before proxying). |
| S5 | DLQ for poison frames; AMQP consumer with QoS; failed publishes no longer vanish. |
| S6 | Release surface: provenance via GHCR + OIDC npm; no tokens in the pipeline. |

## Request authentication (M7 W6-D3)

The ingress can require proof of origin without ever seeing a user identity or
a tenant: HMAC-SHA256 over `[timestamp, nonce, sha256(body)]`, keyed by
`FPKG_HMAC_SECRET` (32+ characters, environment/secret store only).

- **Fail-closed.** With a secret configured there is no unauthenticated path:
  a missing/malformed signature, a timestamp outside the window
  (`FPKG_HMAC_WINDOW_MS`, default 5 min, past *or* future), a MAC mismatch, or a
  replayed nonce is rejected before the body is framed or forwarded. Without a
  secret the ingress trusts the network (D-v1-2), which is the documented
  default, not an accident.
- **What it proves.** Integrity and freshness of the request as received, and
  possession of the deployment key by the caller. It is *not* tenancy, a user
  identity, or an authorisation decision — those stay platform-side (M10).
- **Comparison is constant-time** (`std.crypto.timing_safe.eql`), and the
  secret, nonce, and timestamp are never logged; only the failure reason.
- **Replay window.** Nonces are remembered for the window in a fixed-size,
  bounded table (65 536 entries). When it is exhausted the ingress refuses new
  requests (503) rather than evicting live nonces — a capacity signal, not a
  silent weakening. The cache is per-process.
- **Rotation.** `FPKG_HMAC_SECRET_PREVIOUS` is accepted alongside the current
  key so a roll does not drop in-flight clients; unset it after one window.
- **Browser deployments.** The SDK cannot hold a secret; signing happens at a
  trusted edge or platform gateway that forwards the signed request.

## Already done

- `SECURITY.md` with reporting policy; `CODE_OF_CONDUCT.md`;
  `CONTRIBUTING.md` (option B items added).
- dist surface guard (`src/build/dist_surface.zig`) — rejects `.wasm` files,
  wasm-instantiation markers, and `hash`/`compute` identifiers in the shipped
  npm `dist/` (no fingerprint computation in the browser).
- Zero third-party dependencies (Zig) and no secrets in the repo or CI.
- Docker images run non-root with tini.

## Open questions (S4 review)

1. Worker↔ingress auth: mTLS vs network ACL vs plaintext (with the pool
   staying on a private network).
2. HTTP ingress auth: shared API key per deployment? per-tenant keys are the
   Go platform's concern.
3. Rate-limit policy per client (IP / package_id / session).
4. TLS: terminate at the ingress or a reverse proxy in front of it.
