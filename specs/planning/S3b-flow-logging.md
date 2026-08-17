# S3b — Flow logging for worker and ingress

Status: done (2026-08-15)
Spec: specs/architecture/logging.md (F-2); follow-up to slice S3 (S3-logging.md, done)
Scope: per-request flow traces and lifecycle logs for the worker and ingress at
all four levels (debug/info/warn/err). Deviation from the spec's original
"access lines at debug": operator feedback (S3b UAT) moved the flow lifecycle
lines to `info` so they are visible at the default level; only the request
access line, connection open/close, and frame-detail fields stay at `debug`.

## Level contract (S3b revision, supersedes logging.md §leveling)

- `info` — flow lifecycle, visible by default: got job, processing, job done,
  reply sent, AMQP publish + confirm, signal received / forwarding, worker
  reply status, reply relayed, pool connected, healthz probe, client accepted.
- `debug` — access + detail: method/target/peer access line, connection
  open/close, frame-detail fields (codec, payload_len, result_len), payload /
  relayed byte counts, pool forward/reply per attempt.
- `warn` — recoverable: frame dropped, publish dropped, client dropped,
  malformed request, pool worker unavailable, oversized body.
- `err` — unrecoverable/startup: invalid --listen/--amqp-address, publisher
  failed, CLI parse diagnostics.

`--log-level=debug` reveals the full trace including frame detail; `--log-level=err`
suppresses everything except fatal diagnostics.

## Deliverables

### 1. Worker flow logs — src/cmd/worker/worker.zig

`serve()` per-frame trace (request-header decode gated on `log.shouldLog(.info)`,
so the default build pays the SHA-256 integrity decode exactly once per frame):

- `worker: got job type={s}` (info) — request header via `adapter.decodeFrame`.
- `worker: job detail codec={s} payload_len={d}` (debug) — frame-detail fields.
- `worker: processing job` (info) — before `engine.process`.
- `worker: job done status={s}` (info) — reply via `decodeReply`.
- `worker: job detail result_len={d}` (debug) — reply result size.
- `worker: reply sent to client (type={s})` (info) — after `writeFrame`.
- `worker: publishing reply (type={s}) to exchange '{s}' key '{s}'` (info) —
  before `publish_reply`, only when a publisher is configured.
- `worker: publish confirmed` (info) — after a successful publish.

tcp accept loop:

- `worker: client accepted` (info) — after `acceptWait` returns true.
- `worker: client closed` (debug) — when `serve` returns on a clean peer close
  (logged inside `serve()`, which swallows `EndOfStream`).
- `worker: client dropped: {s}` (warn) — protocol error (malformed frame leaves
  the stream desynchronized; client closed, loop keeps serving).

Existing lines unchanged: frame dropped (warn), publish dropped (warn),
publisher ready (info), `worker: listening on` (info, substring contract),
CLI/startup errors (err).

### 2. Ingress flow logs — http.zig + pool.zig

`HttpServer.handleConnection` trace:

- `ingress: connection accepted from {s}` (debug) — `peerLabel(client)`.
- `ingress: {method} {target} {content_length?} from {s}` (debug) — parsed head.
- `ingress: signal received from client, forwarding to worker` (info) — after
  the body is wrapped in an FPKG frame.
- `ingress: forwarding to worker ({d} payload bytes)` (debug) — byte detail.
- `ingress: worker reply status {d} -> http {d}` (info) — after `pool.request`.
- `ingress: reply relayed` (info) — after the reply is written.
- `ingress: relayed reply ({d} bytes)` (debug) — byte detail.

`WorkerPool` (scope `pool`; each slot carries a stable `worker_id`, its 0-based
`--worker=` position):

- `pool: connected to worker {d} ({s}:{d})` (info) — lazy connect succeeded.
- `pool: worker {d} ({s}:{d}) unavailable ({s}), retrying next slot` (warn) — an
  exchange failed; the slot is dropped and the request re-routed.
- `pool: no workers reachable` (warn) — every slot failed.
- `pool: forwarding signal package to worker {d} ({s}:{d})` (debug) — per
  request attempt.
- `pool: reply from worker {d} ({s}:{d}) ({d} bytes)` (debug) — per successful
  exchange.

Existing lines unchanged: healthz probe (info, now with peer + origin),
listening on (info, substring contract), chunked/unsupported method/integrity/
schema/oversized-body/missing-content-length (warn), client dropped (warn),
worker request failed (warn), CLI errors (err).

### 3. Imports

- pool.zig adds `const log = @import("log");` (the `ingress` module already has
  the `log` import map entry; worker.zig and http.zig already import it).

## Tests

1. `src/integration_tests.zig` — worker debug-flow test: spawn
   `worker start --transport=tcp --listen=127.0.0.1:0 --log-level=debug`, read
   the announcement, exchange the fixture frame, expect the hash reply, close
   the client, SIGTERM, then assert stderr contains the info flow lines
   (`got job type=signal_package`, `processing job`, `job done status=ok`,
   `reply sent to client (type=fingerprint_result)`, `client closed`) and the
   debug detail lines (`job detail codec=binary payload_len=84`,
   `job detail result_len=36`).
2. `src/integration_tests.zig` — worker default-level test: same exchange
   without `--log-level`; asserts the flow lines still emit at the default
   `info` level and that `worker: job detail` does not (debug-gated).
3. `src/integration_tests.zig` — ingress debug-flow test:
   `ingress start --log-level=debug` + POST + GET /healthz; asserts the access,
   flow, pool (worker 0), status, relay, and healthz lines.
4. Existing substring contracts (`worker: listening on`, `ingress: listening on`)
   must stay intact — asserted by the existing spawnWorker/spawnIngress tests.
5. `zig build test --summary all` green (unit + integration).

## Verification

1. `zig build test --summary all` green (448 = 425 unit + 23 integration).
2. Manual: `worker start --transport=tcp --listen=127.0.0.1:0` (default level)
   shows got job → processing → job done → reply sent after one frame;
   `--log-level=debug` adds the `job detail` lines; `--log-level=err` shows none.
3. Manual: `ingress start` (default level) shows signal received / forwarding,
   pool connected to worker 0, reply status, relayed for a POST and a healthz
   probe; `--log-level=debug` adds the access and byte-count lines.
4. Update specs/planning/STATUS.yaml note and this plan's status when done.
