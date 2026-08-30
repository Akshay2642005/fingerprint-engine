---
title: "Ingress setup"
description: "Run the HTTP ingress — the only component that speaks HTTP — and configure its worker pool, body cap, and logging via flags or environment variables."
category: "start"
order: 3
crumbs: ["start", "ingress"]
---

# Ingress setup

The ingress is the **only** component allowed to speak HTTP. It terminates the
browser SDK's `POST /v1/fingerprints`, validates the package's integrity
headers, wraps the body in an **FPKG frame**, forwards it to a pooled worker over
TCP, and translates the worker's FPKG reply back into an HTTP response.

It contains **no engine code** — `engine` is not even in its import graph. The
ingress is a pure boundary: parse, validate, forward, relay.

```mermaid
flowchart LR
  SDK[Browser SDK] -->|HTTP POST| ING[Ingress]
  ING -->|FPKG frame| WK[Worker pool]
  WK -->|FPKG reply| ING
  ING -->|WorkerReply| SDK
```

## Build and run

The ingress ships as a standalone binary (`zig build ingress`) and as the
`fingerprint ingress` subcommand of the combined binary (`zig build fingerprint`).
Both are equivalent.

```bash
# standalone
zig build ingress --release=safe
./zig-out/bin/ingress start --listen=0.0.0.0:8080 --worker=127.0.0.1:8080

# or combined
zig build fingerprint --release=safe
./zig-out/bin/fingerprint ingress start --listen=0.0.0.0:8080 --worker=127.0.0.1:8080
```

In containers, the `deploy/Dockerfile.ingress` image already sets the entrypoint
to `/usr/local/bin/ingress`, so the compose `command` is just the flags:

```yaml
ingress:
  build:
    context: .
    dockerfile: deploy/Dockerfile.ingress
  ports:
    - "8080:8080"
  environment:
    - FPKG_WORKERS=worker1:8080,worker2:8080,worker3:8080
  command:
    - "start"
    - "--listen=0.0.0.0:8080"
```

## Flags

```
ingress start --listen=host:port --worker=host:port [--worker=...]
               [--max-body=bytes] [--log-level=level]
               [--log-format=text|json]

ingress version
ingress help
```

| Flag | Default | Description |
| ---- | ------- | ----------- |
| `--listen` | _(required)_ | `host:port` to bind for HTTP. Port `0` picks an ephemeral port (announced on stderr). IPv6 bracket notation `[::1]:8080` is accepted. |
| `--worker` | _(required, repeatable)_ | Worker pool seed, `host:port`. Repeat it to add more workers, or set `FPKG_WORKERS` instead. |
| `--max-body` | `1048576` (1 MiB) | POST body cap in bytes; requests above it get `413`. Far below the 16 MiB FPKG cap and comfortably above a real package. |
| `--log-level` | `info` | `err` \| `warn` \| `info` \| `debug`. |
| `--log-format` | `text` | `text` \| `json`. |

At least one worker must be reachable or the ingress refuses to start
(`no workers (pass --worker=host:port or set FPKG_WORKERS)`).

## Environment variables

Flags win over environment variables, which win over defaults.

| Variable | Equivalent | Notes |
| -------- | ---------- | ----- |
| `FPKG_WORKERS` | repeated `--worker` | Comma-separated `host:port` list, e.g. `worker1:8080,worker2:8080`. Read when no `--worker` is given. |
| `FPKG_LOG_LEVEL` | `--log-level` | `err` \| `warn` \| `info` \| `debug`. |
| `FPKG_LOG_FORMAT` | `--log-format` | `text` \| `json`. |

Example — point the ingress at three workers purely through the environment:

```bash
export FPKG_WORKERS=worker1:8080,worker2:8080,worker3:8080
export FPKG_LOG_LEVEL=debug
./zig-out/bin/ingress start --listen=0.0.0.0:8080
```

## Multiple workers (load balancing)

The ingress holds a pool of workers and load-balances frames across them. Add
workers by repeating `--worker` (or by listing them in `FPKG_WORKERS`). Each
worker runs independently and statelessly, so the pool scales horizontally with
zero coordination:

```bash
./zig-out/bin/ingress start \
  --listen=0.0.0.0:8080 \
  --worker=worker1:8080 \
  --worker=worker2:8080 \
  --worker=worker3:8080
```

Because the engine is deterministic, any worker in the pool produces the identical
digest for the identical package — so placement is arbitrary and safe. See
[Worker](/docs/start/worker/) for how to run the worker containers and
[Self-host](/docs/start/self-host/) for a ready-made three-worker compose file.

## Next steps

- [Worker](/docs/start/worker/) — the computation side of the pool.
- [Self-host](/docs/start/self-host/) — a full compose file with ingress + 3 workers.
- [Guides: Serialization](/docs/internals/serialization/) — the FPKG frame the ingress and worker exchange.
