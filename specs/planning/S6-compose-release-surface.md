# S6 — Full-Stack Compose + Release Surface

Status: planned
Depends: S4 (ingress), S5 (AMQP consumer + DLQ)

## Problem

The compose file currently only has RabbitMQ. There is no way to run the
full browser→ingress→worker→RabbitMQ loop locally. The ingress image is
not published to GHCR and is not listed in release notes.

## Scope

### Full-stack compose

Add `worker` and `ingress` services to `compose.yml`:

- **worker**: builds from `deploy/Dockerfile.worker`, exposes 8080,
  connects to RabbitMQ at `rabbitmq:5672`.
- **ingress**: builds from `deploy/Dockerfile.ingress`, exposes 8080,
  connects to worker via `FPKG_WORKERS=worker:8080`.
- **rabbitmq**: existing service, no changes.

Networking: all three services on the default compose network.

### Ingress GHCR image

- `release.yml` gains a `publish-docker-ingress` job that mirrors
  `publish-docker-worker`: builds `deploy/Dockerfile.ingress`, pushes
  to `ghcr.io/akshay2642005/fingerprint-engine/fingerprint-ingress`
  with `:latest` and version tags.
- Release notes updated to list both images.

### Demo verification

- `examples/demo.html` documented as the full-stack verification tool.
- `docker compose up` starts all three services; the demo hits the
  compose ingress.

## Not in scope

- TLS termination — no nginx/traefik proxy in compose.
- Health-check-based restart policies — Docker's `restart: always` is
  sufficient for local dev.
- Multi-arch builds — x86_64 only for now.

## Verification

- `docker compose up` runs browser → ingress → worker → RabbitMQ.
- `docker images` shows both `fingerprint-worker` and `fingerprint-ingress`.
- `gh release create` lists both images in release notes.
- S6 verification checklist items signed off.
