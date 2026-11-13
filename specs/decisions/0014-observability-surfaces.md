<!-- // story: m8-observability -->

# ADR-014 — Observability surfaces (metrics + probes)

- **Status:** Adopted (2026-11-04)
- **Source:** `src/cmd/ingress/http.zig`, `src/cmd/ingress/pool.zig`,
  `src/cmd/worker/worker.zig`, `src/adapter/tcp.zig`, `src/io/root.zig`,
  `src/log.zig`, `compose.yml`
- **Extends:** ADR-006 (inbound request/response, outbound AMQP events),
  ADR-007 (tiny stateless worker), ADR-011 (shared CLI components).
  Does not supersede any of them.

## Context

M8 needs Prometheus metrics and readiness probes. Today neither component
exposes anything but `GET /healthz` on the ingress (`src/cmd/ingress/http.zig`,
`handleGet`); the worker speaks raw FPKG over TCP on `--listen` and has no HTTP
surface at all. There is no `metrics` symbol anywhere in `src/`.

Three constraints shape the decision:

1. **Zero third-party dependencies.** `build.zig.zon` declares no packages; the
   project's whole hedge is std-only. Pulling in a Prometheus client or an HTTP
   library is out.
2. **Zero allocation in hot paths.** The engine ethos is comptime-first,
   no runtime allocation. A metrics registry must not allocate per request, and
   must not let a scrape perturb latency.
3. **The worker has no HTTP server.** Prometheus scrapes HTTP; the worker's
   port speaks FPKG. Something has to terminate HTTP on a second port.

The ingress is a single-threaded event loop with exactly one accept context and
one `io.IO` instance (`HttpServer.acceptWait`, `accept_poll_ms`), and the H-2
drain logic depends on that shape. Adding a second listener to it would mean
touching the drain path; letting a scraper share the request loop would let a
slow scrape stall request serving.

## Decision

### 1. A new leaf module `src/obs/`

Two files, depending only on `std` and `io` (never `engine`, `adapter`, or
`cmd`), so both executables can import it without inverting the layering
(ADR-002):

- `src/obs/metrics.zig` — the registry (`std` only).
- `src/obs/scrape.zig` — the HTTP scrape/probe listener (`std` + `io` for
  sockets).

### 2. Metrics are comptime-declared, atomic, and allocation-free

A metric set is a `struct` of member types declared at comptime:

| Kind | Storage | Operations |
|---|---|---|
| counter | `std.atomic.Value(u64)` | `inc()`, `add(n)` |
| gauge | `std.atomic.Value(i64)` | `set(v)`, `inc()`, `dec()` |
| histogram | fixed `[N]std.atomic.Value(u64)` buckets + `sum`/`count` | `observe(v)` |

Rules:

- **No dynamic labels.** Every label value is a comptime enum
  (`op`, `status`, `codec`), so cardinality is bounded by the type system and
  there is no label map to allocate. No session ids, digests, or peer
  addresses — those are unbounded and would be a memory and privacy hazard.
- **Fixed buckets**, chosen per metric at comptime. Percentiles (p50/p95/p99)
  are derived **at scrape time** from cumulative bucket counts, not stored.
- **Atomics, not locks**, because the scrape listener runs on its own thread
  (§3). An uncontended atomic increment is the only hot-path cost.

### 3. The scrape listener runs on a dedicated OS thread

`scrape.serve()` spawns one thread with a blocking accept loop:

- One connection at a time; `Connection: close`; a short socket timeout; a
  bounded request-head read (a scraper cannot hold a slot forever).
- `GET` only. `/metrics` returns `text/plain; version=0.0.4`. `/readyz`
  returns `200 {"ready":true,...}` or `503` with the failing dependency named.
  Anything else → `404`; any other method → `405` with `Allow: GET`.
- **No request bodies are read**, so there is no body-parsing surface.

Why a thread rather than the existing event loop: a scraper must never be able
to stall request serving, and the ingress's single accept context is load-
bearing for the H-2 drain. A separate thread keeps both properties and touches
no existing code path.

### 4. Dedicated ports, never the API port

| Component | Default | Flag | Disable |
|---|---|---|---|
| ingress | `:9090` | `--metrics-listen=host:port` | `--metrics-listen=off` |
| worker | `:9091` | `--metrics-listen=host:port` | `--metrics-listen=off` |

The metrics port is **never** the HTTP ingress port or the FPKG port. Metrics
reveal traffic rate, rejection spikes, and worker health; keeping them off the
public port is the point. In `compose.yml` they are declared with `expose:`,
not `ports:` — reachable inside the network, never published to the host. A
`compose.override.yml` publishes them for local development only.

Enabled by default so a deployment cannot silently have no observability;
`off` is explicit and logged at startup.

**Threat model.** The metrics/probe ports stay network-internal (`expose:`)
because they are unauthenticated by design. The worker's FPKG port remains
published on all host interfaces in `compose.yml` (`8081:8080`) by
*deliberate* decision: the worker itself has no auth (ADR-007 is a tiny
stateless worker) and every request must pass the ingress's HMAC check on the
ingress port before being forwarded. Publishing the worker FPKG port is
therefore not an auth bypass for `compose.yml` deployments where callers route
through the ingress on `8080`; it is documented in
`website/src/docs/operating/deployment.md:30,239`. Deployments that do not
route through the ingress should bind `--listen` loopback instead.

### 5. Naming and the ready-semantics split

`fpkg_<component>_<subject>_<unit>`, e.g. `fpkg_ingress_request_duration_seconds`,
`fpkg_worker_jobs_total`. `component` ∈ {`ingress`, `worker`}.

**`/healthz` and `/readyz` are different questions** and keep different
owners:

- `/healthz` (existing, ingress only, on the API port) — liveness: the process
  is up and serving. Never checks dependencies; a failing dependency must not
  restart a healthy process.
- `/readyz` (new, both components, on the metrics port) — readiness: this
  instance can serve traffic *now*. Ingress checks that at least one worker is
  reachable; the worker checks its AMQP link when `--publish=amqp` is active.
  Ingress reachability is a cached gauge refreshed by a **time-gated health
  tick (~2 s)** that runs whether or not requests arrive; the idle-counter
  gate was removed because any steady connection stream starves it. Each tick
  re-probes slots with no connection and connections idle longer than the
  readiness TTL (`--readiness-ttl-ms`, default 30 s = 3 × the frame deadline):
  a socket to a worker that died while connected looks alive at the kernel
  level, so an idle connection is dropped and re-established before it may
  keep reporting readiness. Failed probes back off per slot (5 s doubling to a
  60 s cap) so a pool of dead workers cannot spend the tick's connect budget
  on the same unreachable seeds. A successful probe proves the seed's **kernel
  is listening**, not that a wedged worker is un-wedged.

**Rejected alternatives:** (a) an external Prometheus client or HTTP library —
violates the zero-dependency hedge; (b) metrics on the existing API port — mixes
public and operational surfaces; (c) scrape served from the request event loop
— a slow scraper becomes a latency source; (d) exported counters as FPKG frames
— no standard scraper speaks it, and it would need a client on the other side.

## Consequences

**Positive**

- One registry and one listener serve both components; no dependency added.
- Hot-path cost is a single atomic increment; scraping can never stall requests.
- Percentiles cost nothing until scraped.
- `/readyz` gives compose/operators a real dependency check instead of a
  process-liveness proxy.

**Negative / costs**

- A second listening socket per container is a new surface to firewall and to
  document in the security plan (it is read-only and unauthenticated by design;
  it must stay network-internal).
- Comptime-declared metrics mean adding a metric is a code change, not a config
  change — intentional, but it raises the bar for ad-hoc instrumentation.
- Thread + atomics is more machinery than a single-threaded counter; accepted
  for the isolation property.

**Revisit when:** metrics need labels whose values come from data rather than
types (that is the moment to consider a bounded label map and an explicit
cardinality cap), or if the scrape port must be authenticated (then it belongs
behind the same boundary as the API port).

## Notes

- Metric catalog, bucket choices, and the readyz dependency list:
  `specs/architecture/observability.md`.
- Probe semantics for the worker's FPKG port: `/readyz` is authoritative; a
  bare TCP connect to `--listen` proves nothing beyond the kernel backlog.
- Related: ADR-015 (`request_id` carried in logs), ADR-016 (publish-failure
  counters), ADR-017 (credential sourcing, same env-only pattern).
