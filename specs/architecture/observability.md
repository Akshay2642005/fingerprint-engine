<!-- // story: m8-observability -->

# Observability — metrics, probes, and correlation

Status: **adopted** (M8, ADR-014)
Applies to: `fingerprint-ingress`, `fingerprint-worker` (and the combined
`fingerprint` binary, which runs both).

The engine exposes a Prometheus text-format endpoint and a readiness probe on a
**dedicated port**, separate from the public HTTP port and from the FPKG port.
There is no third-party dependency, no per-request allocation, and no dynamic
label cardinality: every label value is a compile-time enum.

## Ports and flags

| Component | API / FPKG port | Metrics + probe port | Flag |
|---|---|---|---|
| ingress | `--listen` (default `:8080`) | `:9090` | `--metrics-listen=host:port` |
| worker | `--listen` (default `:8080`) | `:9091` | `--metrics-listen=host:port` |

- `--metrics-listen=off` disables the surface (logged at startup).
- The metrics port is **never** the API port. In `compose.yml` it is `expose:`,
  not `ports:` — reachable inside the network, not published to the host.
  `compose.override.yml` publishes it for local development only.

## Endpoint behaviour

| Method + path | Response |
|---|---|
| `GET /metrics` | `200`, `text/plain; version=0.0.4; charset=utf-8` |
| `GET /readyz` | `200` `{"ready":true}` or `503` `{"ready":false,"dependency":"<name>"}` |
| `GET /healthz` | ingress API port only — liveness, unchanged |
| anything else | `404`; non-`GET` → `405` with `Allow: GET` |

One connection at a time, `Connection: close`, bounded head read, no request
bodies parsed. A slow or stalled scraper cannot affect request serving: the
listener runs on its own thread and the registry is atomic.

### Liveness vs readiness

- **`/healthz`** (ingress, API port) — the process is up. **Never** checks
  dependencies: a failing dependency must not cause a restart loop.
- **`/readyz`** (both, metrics port) — this instance can serve traffic now.
  - ingress: at least one worker in the pool is reachable.
  - worker: the AMQP link is up **when** `--publish=amqp` is active; with
    `--publish=none` the worker is ready as soon as it is listening.

## Metric catalog

Naming: `fpkg_<component>_<subject>_<unit>`. Counters end in `_total`.
`component` ∈ {`ingress`, `worker`}.

### Ingress

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `fpkg_ingress_build_info` | gauge | `version` | Always `1`; carries the build version |
| `fpkg_ingress_requests_total` | counter | `status` (`2xx`/`4xx`/`5xx`) | Completed HTTP requests |
| `fpkg_ingress_request_duration_seconds` | histogram | — | HTTP-in → reply-out latency |
| `fpkg_ingress_auth_rejections_total` | counter | `reason` | `missing`, `malformed`, `forged`, `stale`, `replayed`, `cache_full` |
| `fpkg_ingress_replay_cache_entries` | gauge | — | Nonces currently held |
| `fpkg_ingress_replay_cache_capacity` | gauge | — | Configured bound (constant at runtime) |
| `fpkg_ingress_worker_pool_healthy` | gauge | — | Reachable workers in the pool |
| `fpkg_ingress_request_id_total` | counter | `source` (`minted`/`honoured`) | ADR-015: ids minted vs accepted from `x-request-id` |
| `fpkg_ingress_ready` | gauge | — | Mirrors `/readyz` (`1`/`0`) |

Duration buckets: `0.001 0.0025 0.005 0.01 0.025 0.05 0.1 0.25 0.5 1 2.5 5`.

### Worker

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `fpkg_worker_build_info` | gauge | `version` | Always `1` |
| `fpkg_worker_jobs_total` | counter | `op`, `result` (`ok`/`error`) | Engine operations executed |
| `fpkg_worker_job_duration_seconds` | histogram | `op` | Per-operation service time |
| `fpkg_worker_signals_present` | histogram | — | Features present per package (signal coverage) |
| `fpkg_worker_entropy` | histogram | — | Emitted entropy estimate (bits) |
| `fpkg_worker_risk_score` | histogram | — | Emitted risk score (0..1) |
| `fpkg_worker_publish_total` | counter | `result` | `acked`, `unroutable`, `dlq`, `dlq_failed`, `failed` |
| `fpkg_worker_frames_dropped_total` | counter | `reason` | Inbound poison frames (bad magic, integrity, decode) |
| `fpkg_worker_amqp_connected` | gauge | — | `1` while the publisher link is up |
| `fpkg_worker_ready` | gauge | — | Mirrors `/readyz` |

Bucket choices:

- duration: `0.0005 0.001 0.0025 0.005 0.01 0.025 0.05 0.1 0.25 0.5 1`
- `signals_present`: `0 8 16 32 48 64 80 96 102`
- `entropy` (bits): `0 16 32 64 96 128 160 192 224 256`
- `risk_score`: `0 0.1 0.2 … 1.0`

`op` is the `Operation` enum; `result` and `reason` are small enums. Cardinality
is therefore fixed by the type system — there is no label map and no unbounded
series.

## Correlation

Every log line for a collection carries `request_id` (and `session_id` when
present). The worker also sets `request_id` on the AMQP message **headers** of
every published frame, so a broker consumer can correlate without the envelope
changing (ADR-015). Nothing in this document puts a request id, session id,
digest, or peer address in a **metric label** — those are unbounded and, for
`session_id`/`signals`, identifying.

## Example scrape config

```yaml
scrape_configs:
  - job_name: fingerprint
    static_configs:
      - targets: ["ingress:9090"]
        labels: { component: ingress }
      - targets: ["worker:9091"]
        labels: { component: worker }
    scrape_interval: 15s
```

## Alerts worth having by default

Rules and thresholds are owned by the SLO document (Week 11-D5). The metrics
above are sufficient for all of them:

| Signal | Metric |
|---|---|
| DLQ growth / dead events | `increase(fpkg_worker_publish_total{result=~"dlq.*"}[5m])` |
| Broker link down | `fpkg_worker_amqp_connected == 0` |
| Replay-reject spike | `increase(fpkg_ingress_auth_rejections_total{reason="replayed"}[5m])` |
| p99 latency breach | `histogram_quantile(0.99, …)` on the request duration |
| No ready ingress | `fpkg_ingress_ready == 0` |
| Dropped poison frames | `increase(fpkg_worker_frames_dropped_total[5m])` |

## Deliberately not exported

- **Per-signal metrics.** 102 features × label is unbounded and would leak the
  fingerprint itself. Coverage is a histogram, not a per-feature series.
- **Digests or ids in labels** — unbounded cardinality.
- **Peer addresses, user agents, origins** — privacy and cardinality.
- **GC/allocation stats** — the engine does not allocate in these paths; there
  is nothing meaningful to report.

## Related

- ADR-014 (this surface), ADR-015 (`request_id`), ADR-016 (publish failures),
  ADR-017 (credentials).
- `src/obs/metrics.zig`, `src/obs/scrape.zig`.
