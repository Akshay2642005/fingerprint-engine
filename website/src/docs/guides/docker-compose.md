---
title: "Docker Compose"
description: "Run the full stack with docker compose up — RabbitMQ, the stateless worker, and the HTTP ingress."
category: "guides"
order: 4
crumbs: ["guides", "docker-compose"]
---

# Docker Compose

The fastest way to run the full Fingerprint Engine pipeline is the bundled
`docker compose` stack. One command starts every moving part — a RabbitMQ
broker, the stateless Zig worker, and the HTTP ingress — wired together by
Docker's built-in DNS. This guide walks through the topology, why
container-name resolution makes it work with zero configuration, and the exact
compose file to copy.

## The three services

The stack is intentionally small and layered, mirroring the architecture
([Architecture](../architecture.md)):

1. **RabbitMQ** — the AMQP 0-9-1 broker. The worker publishes fingerprint
   result events here after computing a digest (`--publish=amqp`). It is
   reachable on `rabbitmq:5672`.
2. **Worker** — a stateless Zig container running `worker start`. It listens
   for FPKG frames, computes the canonical SHA-256 fingerprint with
   `engine.process()`, relays a reply, and optionally publishes result events
   to RabbitMQ. It is reachable on `worker:8080`.
3. **Ingress** — the HTTP gateway built from `deploy/Dockerfile.ingress`. It
   receives HTTP POSTs from the browser SDK, forwards them to the worker over
   the FPKG transport, and returns the worker's reply to the client.

```mermaid
flowchart LR
    SDK[Browser SDK] -->|HTTP POST| ING[Ingress]
    ING -->|FPKG frame| WK[Worker]
    WK -->|AMQP result event| RMQ[RabbitMQ]
```

## Container-name DNS resolution

The crucial detail that lets this compose file work with no hardcoded
addresses is **Docker's built-in DNS**. When you start services with
`docker compose`, Compose creates a private network and registers each service
under its **service name** as a hostname. Containers on that network can then
reach one another by name — `rabbitmq`, `worker`, `ingress` — instead of by
IP address.

This matters for three reasons:

- **Stability**: container IPs are assigned dynamically and change across
  restarts. Hostnames do not.
- **Decoupling**: the worker does not need to know how RabbitMQ is deployed,
  and the ingress does not need to know how the worker is reachable. Each
  depends only on a logical name.
- **Configuration**: because the ingress connects to `worker:8080` and the
  worker connects to `rabbitmq:5672` by name, the compose file carries that
  wiring as plain service names — no environment-var gymnastics.

The name resolution happens at connection time, inside the network Compose
creates. As long as the referencing service is on the same network as the
service it names, `worker:8080` and `rabbitmq:5672` resolve correctly.

## The compose file

Create `docker-compose.yml` at the project root and run `docker compose up`:

```yaml
services:
  rabbitmq:
     image: rabbitmq:4-management
    container_name: rabbitmq
    ports:
      - "5672:5672"      # AMQP
      - "15672:15672"    # management UI (optional)
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  worker:
    build:
      context: .
      dockerfile: deploy/Dockerfile.worker
    container_name: worker
    depends_on:
      rabbitmq:
        condition: service_healthy
    command: >-
      worker start
      --transport=tcp
      --listen=0.0.0.0:8080
      --publish=amqp
      --amqp-address=rabbitmq:5672
      --amqp-user=guest
      --amqp-password=guest
      --amqp-vhost=/
    ports:
      - "8080:8080"      # FPKG TCP transport (ingress → worker)
    networks:
      - fingerprint

  ingress:
    build:
      context: .
      dockerfile: deploy/Dockerfile.ingress
    container_name: ingress
    depends_on:
      - worker
    ports:
      - "80:80"          # HTTP (browser SDK → ingress)
    environment:
      FPKG_WORKERS: worker:8080
    networks:
      - fingerprint

networks:
  fingerprint:
    driver: bridge
```

A few things to call out about this file:

- **Worker `--publish=amqp`** connects to `rabbitmq:5672` by container name.
  The `depends_on` with `condition: service_healthy` waits for RabbitMQ to
  pass its `healthcheck` before the worker starts, avoiding a race where the
  worker boots before the broker accepts connections.
- **Ingress `FINGERPRINT_WORKER=worker:8080`** — the ingress reaches the
  worker by the `worker` hostname. There is no IP to update when the worker
  restarts.
- Both worker and ingress sit on the same `fingerprint` bridge network, which
  is what makes `rabbitmq`, `worker`, and `ingress` resolvable as hostnames.

## Running the stack

Start everything in the foreground:

```bash
docker compose up
```

Or run it detached and watch the logs:

```bash
docker compose up -d
docker compose logs -f worker ingress
```

Verify the services are healthy:

```bash
docker compose ps
```

Each container reports its started state once its listeners are up. If the
worker fails to connect to RabbitMQ on first boot, confirm the `service_healthy`
dependency is in place and that RabbitMQ passes `rabbitmq-diagnostics ping`.

## Pointing the browser SDK at the ingress

With the stack running, configure the browser SDK to POST to the ingress. On
the same host as Docker, the ingress is published on port `80`:

```ts
import { configure, collect } from '@akshay2642005/fingerprint-sdk';

configure({ ingressUrl: 'http://localhost/v1/fingerprints' });

const result = await collect();
console.log('sent  :', result.sent);
console.log('reply :', result.reply);
```

See [Browser SDK](./browser-sdk.md) for the full collection contract.

## What happens on a request

1. The browser SDK POSTs a SignalPackage v2 body to the ingress
   ([Serialization](./serialization.md)).
2. The ingress wraps the request as an FPKG frame and sends it to
   `worker:8080` over TCP.
3. The worker verifies the frame, runs `engine.process()`, computes the
   canonical SHA-256 digest, and replies.
4. The ingress relays the worker's reply (the `WorkerReply`) back to the
   browser.
5. In parallel, the worker publishes a result event to RabbitMQ on
   `rabbitmq:5672` (routing key `result.*` on the durable `fingerprint`
   exchange), where downstream consumers — including the fraud platform — can
   read it.

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| Worker fails to connect to RabbitMQ | Brokker not ready when the worker boots | Use `condition: service_healthy` on `depends_on` (already set above) and restart the stack. |
| Ingress cannot reach `worker:8080` | Ingress and worker on different networks | Ensure both list the same `fingerprint` network. |
| Browser SDK POST returns non-2xx | Ingress not yet started, or wrong ingress URL | Check `docker compose ps`; confirm the `ingressUrl` points at the published port. |
| `rabbitmq` hostname unresolved | `docker compose` network not shared | Keep every service on the same named network. |

## Next steps

For the worker flags seen in this file explained in depth, including
`--transport`, `--listen`, and all the `--amqp-*` options, see
[Worker CLI](./worker-cli.md). For the exact bytes of the FPKG frames flowing
between ingress and worker, see [Serialization](./serialization.md).
