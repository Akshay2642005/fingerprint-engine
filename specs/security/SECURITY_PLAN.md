# Security plan — Fingerprint Engine

Refreshed 2026-08-08 from the audit (H-1…H-5 in `specs/quality/audits/2026-08-08.md`).

## Threat model (current, v0.4.0)

The shipped attack surface today is small: the worker's TCP transport
(`--transport=tcp`) and the AMQP client. The planned ingress becomes the only
public surface.

| Asset | Exposure | Notes |
|-------|----------|-------|
| Worker FPKG tcp port | LAN/trusted network today | No auth; H-1 idle timeout missing → remotely wedge-able |
| AMQP broker | trusted network | guest/guest in compose dev only |
| HTTP ingress (planned) | public internet | Auth, rate limits, TLS, body caps all pending (H-4/H-5) |
| SignalPackage bodies | transit (HTTPS once TLS lands) | SHA-256 integrity header is tamper-evidence, not authenticity |

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
