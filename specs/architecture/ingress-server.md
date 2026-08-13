# Ingress server — S4-c HTTP termination, S4-d worker pool + e2e + deploy

Story: `s4-ingress-http` (STATUS.yaml). Complements `ingress.md` (the full
ingress design) and `ingress-io.md` (S4-a/b: `io.connect` on three backends +
`adapter.TcpClient`, done). This document covers the two slices that make the
system fully e2e-testable browser → HTTP ingress → FPKG → worker → AMQP:

- **S4-c** — the HTTP/1.1 server: accept loop, bounded request parsing,
  boundary checks, `/healthz`, graceful shutdown (H-2).
- **S4-d** — the worker pool over pooled `TcpClient`s, request→status mapping,
  integration/e2e coverage, and the deploy surface (compose, GHCR, CI).

## Where the code lives

The ingress is part of the shared CLI folder `src/cmd/` (ADR-011):

```
src/cmd/
├── ingress/
│   ├── ingress.zig    # CLI root + start() orchestration (unchanged surface)
│   ├── http.zig       # S4-c: bounded HTTP/1.1 server + parser (no engine)
│   └── pool.zig       # S4-d: worker pool (round-robin, retry, lazy connect)
└── shutdown.zig       # shared graceful-shutdown flag (worker + ingress)
```

`shutdown.zig` exists because the ingress cannot import `worker` (module
import map restriction — no engine code in the ingress, D16), yet the
combined `fingerprint` binary must install exactly one SIGTERM/SIGINT
handler that drains both apps. Both `worker` and `ingress` now observe the
same flag; the combined binary installs it once via `worker.install…`.

## S4-c — HTTP server

### Connection model

HTTP/1.1 with `Connection: close`: one request per connection, then the
ingress closes it. The browser SDK performs one `fetch()` per `collect()`,
so keep-alive buys nothing for v1 and costs per-connection state and
timeout surface. Request smuggling is avoided by rejecting
`Transfer-Encoding` (chunked) outright (400).

The accept loop mirrors the worker exactly (worker-resilience.md H-1/H-2):

```
while (!shutdown.requested.load(.acquire)) {
    if (!server.acceptWait(250ms)) continue;   // H-2: observes the flag
    server.handleConnection(alloc) catch |err| {
        if (peerGone(err)) continue;           // clean HTTP disconnect
        server.closeClient();                  // protocol error → drop client
        continue;
    };
}
```

### Bounded parsing

- Head (request line + headers) is read into a fixed 16 KiB stack buffer
  until `\r\n\r\n`. A buffer that fills without the terminator → 413.
- Each `recv` stage races a deadline completion (H-1 pattern from
  `adapter.Tcp`): a slow-loris client that stalls mid-head or mid-body is
  disconnected, and the accept loop keeps serving.
- Body is read per `Content-Length`. `Content-Length` missing on POST →
  411; `Content-Length > --max-body` → 413 (checked _before_ reading the
  body); `Transfer-Encoding` present → 400.

### Boundary checks (before proxying)

1. Integrity: if `x-fpkg-integrity` is `sha256-<64 hex>`, compute the
   SHA-256 of the body and compare case-insensitively; mismatch → 400. This
   is the same digest the FPKG frame integrity uses, so it costs nothing
   extra.
2. Schema: `x-fpkg-schema-version` must be `1` or `2` (the engine's v1
   compatibility path covers legacy bodies); anything else → 415.
3. Frame: `adapter.buildFrame(.signal_package, .binary, body, …)` — the
   exact helper the worker trusts, so framing stays single-source.

### Request → status mapping (no engine import)

The reply payload is `u8 status | engine result`. The ingress switches on
the raw byte — the same wire values `engine.Status` defines (status.zig) —
without importing the engine:

| status byte                 | meaning                                           | HTTP |
| --------------------------- | ------------------------------------------------- | ---- |
| 0                           | ok                                                | 200  |
| 1, 2, 4                     | invalid_request / invalid_payload / invalid_input | 400  |
| 3                           | unsupported_version                               | 415  |
| 5                           | buffer_overflow                                   | 413  |
| 6, 7                        | out_of_memory / internal_error                    | 502  |
| other / missing status byte | unknown                                           | 502  |

The reply body is relayed verbatim (status byte + result). Response headers:
`content-type: application/octet-stream`, `x-fpkg-message-type:
fingerprint-result`, `connection: close`.

### Health

`GET /healthz` → `200 {"status":"ok","version":"<version>"}` with
`content-type: application/json`. Any other GET → 404; non-POST/GET methods
→ 405.

### Graceful shutdown (H-2)

SIGTERM/SIGINT (Linux) and Ctrl+C/Ctrl+Break (Windows) set the shared
`shutdown.requested` flag. The accept loop exits between connections;
in-flight requests complete (the request path is synchronous) before the
server closes its pool connections and exits 0.

## S4-d — worker pool

### Shape

One `adapter.TcpClient` per worker seed — the worker serves one connection
at a time, and each pooled connection exchanges many sequential
request/reply frames, so a slot is the concurrency unit for a single
request. The pool round-robins across slots and lazily connects on first
use, so a dead seed costs nothing until it is asked to work.

```
request(frame):
  for slot in round-robin(self.next, n):
      try exchange(slot, frame) → return reply
      catch err: drop the broken connection; try the next slot
  return last error           // every seed failed
```

- Connect deadline: 5 s (a dead worker cannot wedge a request).
- Read deadline: 10 s per frame stage (H-1; the worker replies in ms).
- Retry: each request is attempted once per slot in round-robin order —
  "retry once" in practice because workers are stateless and deterministic:
  any worker can process any package (design §7, D16). After a success the
  cursor advances so traffic spreads across seeds.
- A slot whose exchange failed is closed and reconnected lazily on the next
  use — the pool self-heals when a worker restarts.

### e2e coverage (`src/integration_tests.zig`)

Reuses `spawnWorker` and the pinned fixture digest; adds `spawnIngress`
(reads `ingress: listening on ` from stderr) and a raw-TCP HTTP client:

1. HTTP → FPKG → worker → HTTP: POST the canonical
   `signal-package-v2.bin` fixture, assert 200 and the pinned digest in the
   relayed payload (cross-checks the whole path against the reference
   engine).
2. Dead-worker retry: seed one dead + one live worker; the request lands on
   the live one with the same digest.
3. Boundary: oversized body → 413; integrity mismatch → 400; unknown schema
   → 415; GET /healthz → 200 with the version; unknown method → 405.
4. H-2: SIGTERM mid-idle → clean exit 0 (POSIX only, mirrors the worker
   test).

### Deploy surface

- `compose.yml`: `ingress` service (Dockerfile.ingress) wired to `worker`
  (Dockerfile.worker) + `rabbitmq`; ingress gets its pool seed via
  `FPKG_WORKERS=worker:7001`.
- `release.yml`: publish `fingerprint-ingress` to GHCR alongside the worker
  and list both images in the release notes (npm publish unchanged).
- `ci.yml`: `docker-ingress` job — build `zig build docker:ingress`, verify
  the image, smoke-test the entrypoint (`ingress version`).

## Out of scope (unchanged from ingress.md)

Engine computation (workers only), AMQP (the worker publishes), the
fraud-platform WebSocket, TLS, rate limiting, and keep-alive. Body-size and
header caps are the v1 boundary controls; rate limiting is backlogged for a
later slice (audit S6).
