# Ingress design — F-1 (M5)

The HTTP ingress is the only component that speaks HTTP. It terminates the
browser SDK's POST, validates integrity, wraps the body in an FPKG frame,
forwards it to a pooled worker over the existing `--transport=tcp` path,
and translates the FPKG reply back to HTTP. It contains **no engine code**:
`engine.process()` stays exclusively in the workers (design §7, D16).

## Why a shared CLI folder with separate processes

The ingress scales differently from the workers (few replicas, long-lived
connections) and owns concerns the worker must never see: HTTP, TLS, rate
limiting, body-size policy, and worker selection. It therefore stays a
separate _process_ from the worker, but both apps now live in one CLI folder
(`src/cmd/`) per ADR-011: `main.zig` (combined `fingerprint` binary),
`worker.zig`, and `ingress.zig` each with their own `pub fn main`. This keeps
process separation (both ship as containers with a single entrypoint) while
sharing the CLI conventions, shutdown handling, and build plumbing. The
combined `fingerprint` binary is the single-artifact distribution;
`zig build worker` and `zig build ingress` produce the individual
components.

## The contract it serves (already fixed by the SDK)

`src/clients/browser/src/transport.ts` POSTs to `config.ingressUrl`
(default `http://127.0.0.1:8080`):

| Header                  | Example                    | Meaning                                                              |
| ----------------------- | -------------------------- | -------------------------------------------------------------------- |
| `content-type`          | `application/octet-stream` | raw SignalPackage v2 body                                            |
| `x-fpkg-schema-version` | `2`                        | body schema version                                                  |
| `x-fpkg-sdk-version`    | `1.0.0-rc.1`               | SDK version (informational)                                          |
| `x-fpkg-package-id`     | 32 hex chars               | replay identity                                                      |
| `x-fpkg-integrity`      | `sha256-<64 hex>`          | SHA-256 of the body (best-effort; the ingress enforces when present) |
| `x-fpkg-session-id`     | `tenant42:8d56529f`        | browser/idp session, 1–128 bytes of `[A-Za-z0-9._:-]` (optional; ADR-013 §4) |
| `x-fpkg-collected-at`   | `1757312345678`            | epoch ms, signed; the freshness input (required when HMAC is on)     |
| `x-fpkg-nonce`          | 32 hex chars               | fresh per attempt, 16–64 lowercase hex (required when HMAC is on)    |
| `x-fpkg-signature`      | `hmac-sha256=<64 hex>`     | MAC over the canonical string below (required when HMAC is on)       |
| `origin`                | `https://example.com`      | CORS origin (optional)                                               |

The reply body is the worker's raw payload `u8 status | engine result`
(`fingerprint_result`: `[32]digest | u16 feature_count | u16 schema_version`
— see BUG-001; the ingress relays bytes verbatim and never interprets them).

## Request flow

```mermaid
sequenceDiagram
    participant SDK as Browser SDK
    participant IN as Ingress
    participant WK as Worker (tcp)
    SDK->>IN: POST / (octet-stream body + x-fpkg-* headers)
    IN->>IN: content-length cap, integrity verify, schema check
    IN->>IN: wrap body in FPKG signal_package frame
    IN->>WK: write frame on pooled connection
    WK->>WK: engine.process (validate, normalize, hash, ...)
    WK-->>IN: FPKG reply frame (status | result)
    IN->>IN: map engine status to HTTP status
    IN-->>SDK: HTTP reply (raw result payload)
```

## Request authentication (M7 W6-D3)

The ingress is multi-tenant and trusts the network by default (D-v1-2). For
deployments that need proof of origin and tamper evidence, set
`FPKG_HMAC_SECRET` (at least 32 characters, from the environment/secret store,
never a CLI flag):

| Variable | Meaning |
| --- | --- |
| `FPKG_HMAC_SECRET` | Current key. Setting it enables enforcement. |
| `FPKG_HMAC_SECRET_PREVIOUS` | Optional previous key, accepted during rotation. |
| `FPKG_HMAC_WINDOW_MS` | Freshness/replay window, default `300000` (5 min); 1 s–1 h. |

The client signs this canonical string with HMAC-SHA256:

```
fpkg-hmac-v1
<collected_at>
<nonce>
<sha256(body) as lowercase hex>
```

and sends `x-fpkg-signature: hmac-sha256=<hex>`. The signature is bound to the
timestamp, the nonce, and the body digest, so a captured request cannot be
re-aimed at a different package or replayed with a fresh timestamp.

Rejection matrix (nothing request-derived is echoed back or logged):

| Condition | Status | Body |
| --- | --- | --- |
| Any of the three headers absent | 401 | `signature required` |
| Malformed value (bad hex, bad nonce length/case, bad prefix) | 401 | `malformed signature headers` |
| Timestamp outside the window, past or future | 401 | `stale request timestamp` |
| MAC mismatch | 401 | `invalid signature` |
| Nonce already used inside the window | 409 | `replayed nonce` |
| Replay cache full (capacity exhausted by sustained traffic) | 503 | `replay cache full` |

The replay cache holds 65 536 nonces (~200 req/s at the default window per
ingress instance); it is per-process, so signing clients should be pinned to
one instance or the window must be small enough to tolerate per-instance
duplication. Honouring a retry requires a **new nonce** — the same body may be
re-sent, since idempotency is `package_id`'s job at the ledger.

Rotation: deploy the new key as `FPKG_HMAC_SECRET` and the old one as
`FPKG_HMAC_SECRET_PREVIOUS`, roll clients, then unset the previous variable
after one window has elapsed.

The browser SDK cannot hold a secret, so enabling this obliges callers to sign
server-side (the platform gateway or a trusted edge that re-signs the body).
The comparison is constant-time; the secret, the nonce, and the timestamp are
never logged.

## Ingress responsibilities

1. **Boundary checks** (before proxying):

   - Reject `Content-Length > max_body` with 413 (H-5). Configurable cap,
     default 1 MiB — far below the 16 MiB FPKG cap, comfortably above a real
     package (canvas/audio bytes are tens of KB).
   - If `x-fpkg-integrity` is present: compute SHA-256 of the body and
     compare; mismatch → 400. It must match the FPKG frame integrity the
     ingress computes anyway (same digest, zero extra work).
   - `x-fpkg-schema-version` must be a known schema (2; v1 tolerated per the
     engine's compatibility path, or rejected with 415 — decide in review).
   - If `x-fpkg-session-id` is present it must be 1–128 bytes of
     `[A-Za-z0-9._:-]`; anything else is 400 (ADR-013 §4). The value is
     never logged, only its presence.
   - **Request authentication (M7 W6-D3)** is enforced when
     `FPKG_HMAC_SECRET` is set: `x-fpkg-collected-at`, `x-fpkg-nonce`, and
     `x-fpkg-signature` must be present and valid, or the request is rejected
     before framing (401). Fail-closed — with a secret configured there is no
     unauthenticated path. See [Request authentication](#request-authentication-m7-w6-d3).
   - `cross-origin` / CORS headers are optional; the ingress does not enforce them
     (the SDK does). checks the preflight `OPTIONS` request and responds with the appropriate CORS headers if needed.

2. **Frame translation**: reuse `adapter.buildFrame(...)` — the exact helper
   the worker already trusts. Every forwarded POST is a
   `.signal_package_context` frame: `io.session_context.wrap` prefixes the
   client's body with the session id (possibly empty) and the ingress arrival
   time (`[u16 session_len][session][i64 ingress_received_at][body]`). The
   worker strips the header and hashes the inner body unchanged, so the digest
   is independent of the context. Direct TCP/loopback clients may still send a
   plain `.signal_package`; those collections record no ingress timestamp.
3. **Worker pool**:
   - `--worker=host:port` (repeatable) seeds the pool; default from
     `FPKG_WORKERS` env (comma-separated) for containerized deploys.
   - Round-robin selection; a connect/write error re-routes to the next
     worker and retries once (safe: workers are stateless and deterministic —
     any worker can process any package).
   - Idle connections are reused (avoid per-request TCP handshakes). Each
     pooled connection maps to the worker's single-client-at-a-time accept
     loop; open enough connections per worker for the desired concurrency
     (H-1 timeouts in the worker make a stalled connection self-healing).
4. **Reply translation**: relay the worker payload verbatim; map `engine.Status`
   to HTTP:
   - `ok` → 200
   - `invalid_request` / `invalid_payload` / `invalid_codec` → 400
   - `unsupported_version` → 415
   - `buffer_overflow` → 413
   - everything else → 502 (upstream/worker fault)
   - Response headers: `content-type: application/octet-stream`,
     `x-fpkg-message-type: fingerprint-result`.
5. **Health**: `GET /healthz` → 200 `{ "status": "ok", "version": "..." }`
   (H-3). Liveness of the pool is derived by the ingress from worker
   connections; a `--health-only` mode may be added for load-balancer probes.
6. **Graceful shutdown** (H-2): SIGTERM/SIGINT → stop accepting, drain
   in-flight requests and pool connections, exit.

## Out of scope (explicitly)

- Engine computation, risk, similarity — workers only.
- AMQP — the worker publishes; the ingress never touches the broker.
- The fraud-platform WebSocket (`connectDecisionSocket`) — separate system.

## CLI (mirrors the worker)

```
# Standalone binary (zig build ingress -> zig-out/bin/ingress)
ingress start --listen=host:port --worker=host:port [--worker=...]
              [--max-body=bytes] [--log-level=level] [--log-format=text|json]
ingress version
ingress help

# Combined binary (zig build fingerprint -> zig-out/bin/fingerprint)
fingerprint ingress start --listen=host:port --worker=host:port [--worker=...]
fingerprint ingress version
fingerprint ingress help
```

Both invocations share the same parser (`ingress.parse`, ADR-011 argv
contract).

## Build, deploy, CI

- `src/cmd/ingress.zig` (imports `io` + `adapter` framing helpers only —
  never `engine`), built by `zig build ingress` → `zig-out/bin/ingress`;
  also shipped inside the combined `fingerprint` binary
  (`zig build fingerprint` → `zig-out/bin/fingerprint`, ADR-011).
- `deploy/Dockerfile.ingress` — same multi-stage alpine pattern as
  `deploy/Dockerfile.worker` (host-built binary, tini, non-root, EXPOSE
  8080/8443).
- `zig build docker:ingress` (tag `fingerprint-ingress:<version>` from
  `package_version`, mirroring `build_docker_worker`).
- `compose.yml`: `ingress` service wired to `worker` + `rabbitmq` (F-5).
- `release.yml`: publish `fingerprint-ingress` to GHCR alongside the worker
  and list it in the release notes (F-6).
- `ci.yml`: `ingress-build` job (build + docker image + entrypoint smoke).

## Tests

- Unit: header validation (missing/mismatched integrity, bad schema,
  oversized body), frame wrapping, status→HTTP mapping.
- Integration (extend `src/integration_tests.zig`): spawn a real worker
  (tcp, ephemeral port) + the ingress binary, POST the canonical
  `signal-package-v2.bin` fixture, assert the reply matches the pinned
  digest (the same constant the worker e2e tests use — cross-checks the
  whole HTTP→FPKG→worker→HTTP path against the reference engine).
- Pool: one dead worker + one live worker → the retry lands on the live one
  with the same digest (determinism makes this a strong assertion).
- Graceful shutdown: SIGTERM mid-poll → clean exit code.
