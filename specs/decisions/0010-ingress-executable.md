# ADR-010 — HTTP ingress as a separate executable

- **Status:** Adopted (planned, unbuilt — M5/F-1)
- **Source:** `specs/architecture/ingress.md`

## Context

The browser SDK POSTs `SignalPackage` bodies to an ingress endpoint, but no
such component exists yet (v0.2.2). The ingress must terminate HTTP (the only
component allowed to), validate integrity, translate to FPKG, forward to a
pooled worker over the existing `--transport=tcp` path, and translate the FPKG
reply back to HTTP — with **no engine code** inside it.

## Decision

- **Separate executable `src/ingress/main.zig`** (imports `io` + `adapter`
  framing helpers only — never `engine`). Rejected a combined
  `fingerprint-edge` binary for now: the ingress scales differently (few
  replicas, long-lived connections) and owns concerns the worker must never
  see (HTTP, TLS, rate limiting, body-size policy, worker selection).
- Contract is already fixed by the SDK: POST `/` with `content-type:
  application/octet-stream`, `x-fpkg-schema-version`, `x-fpkg-sdk-version`,
  `x-fpkg-package-id`, `x-fpkg-integrity: sha256-<hex>`.
- Flow: boundary checks (413 on oversized body, 400 on integrity mismatch) →
  `adapter.buildFrame(.signal_package, .binary, body)` → pooled worker
  connection (round-robin, one retry on dead worker — safe because workers
  are stateless) → relay reply payload verbatim → map `engine.Status` to HTTP
  (ok=200, invalid*=400, unsupported_version=415, buffer_overflow=413, else
  502). `GET /healthz`. Graceful shutdown.
- CLI: `ingress start --listen=host:port --worker=host:port [--worker=...]
  [--max-body=bytes] [--log-level=...] [--log-format=...]`; `version`; `help`.
  `FPKG_WORKERS` env for containerized deploys.
- Deliverables: `deploy/Dockerfile.ingress`, `zig build docker:ingress`
  (tag `fingerprint-ingress:<version>`), compose service, ci.yml job,
  release.yml GHCR push, e2e tests posting the canonical fixture through a
  real worker + ingress.

## Consequences

- Production can connect **multiple workers** to one ingress; ingress can
  scale independently (more replicas or more pooled connections per worker).
- The worker's TCP single-client-at-a-time design means the ingress should
  pool several connections per worker for concurrency; H-1 timeouts in the
  worker make a stalled connection self-healing.
- This is the last missing piece before a full-stack local compose
  (F-5) and the S6 release surface.
