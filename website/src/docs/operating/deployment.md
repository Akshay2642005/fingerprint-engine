---
title: "Deployment"
description: "Deploying the Fingerprint Engine stack: docker compose, GHCR container images, cross-platform native binaries, and how the release pipeline produces them."
category: "operating"
order: 2
crumbs: ["operating", "deployment"]
---

# Deployment

The entire backend—a RabbitMQ broker, a stateless Zig worker, and an HTTP
ingress—deploys as three containers behind one command. The same topology
runs on a laptop and in production; nothing about the worker or ingress
changes between the two, because every hostname in the system is resolved by
container name through `getaddrinfo`.

## The full stack in one command

From a repository checkout with a Docker daemon running:

```bash
docker compose up
```

This starts three services:

| Service | Container name | Role | Published ports |
| ------- | -------------- | ---- | ---------------- |
| `rabbitmq` | `rabbitmq` | AMQP 0-9-1 broker, the durable outbound boundary | `5672` (AMQP), `15672` (management UI) |
| `worker` | `fingerprint-worker` | Stateless engine runner; FPKG over TCP in, AMQP out | `8081 → 8080` |
| `ingress` | `fingerprint-ingress` | HTTP termination, integrity/schema checks, worker pooling | `8080 → 8080` |

The worker connects to `rabbitmq:5672` and the ingress connects to
`worker:8080`. Hostnames are resolved with `getaddrinfo`
(`transport.resolveHost`), so the default `docker compose` DNS stack is all
that is needed—no IP-literal configuration, no extra networking flags. The
`rabbitmq` hostname in `--amqp-address=rabbitmq:5672` and the `worker`
hostname in `--worker=worker:8080` are the same names the containers
themselves use.

Note on order: `depends_on` declares the startup order (ingress after worker
after broker), but neither the worker nor the ingress waits on readiness
checks. Each retries naturally through its OS-level connection results, so
the stack converges shortly after `docker compose up`.

## The compose file

This is a production-equivalent `docker-compose.yml`: it pulls the released
images from GitHub Container Registry instead of building from source, but
keeps identical environment and command wiring:

```yaml
services:
  rabbitmq:
    image: rabbitmq:4-management
    container_name: rabbitmq
    restart: always
    ports:
      - "5672:5672"      # AMQP protocol port (for applications)
      - "15672:15672"    # HTTP management UI
    environment:
      - RABBITMQ_DEFAULT_USER=guest
      - RABBITMQ_DEFAULT_PASS=guest
      - RABBITMQ_DEFAULT_VHOST=/
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
      - rabbitmq_logs:/var/log/rabbitmq

  worker:
    image: ghcr.io/akshay2642005/fingerprint-engine/fingerprint-worker:v0.4.1
    container_name: fingerprint-worker
    restart: always
    ports:
      - "8081:8080"
    environment:
      - FPKG_LOG_LEVEL=info
    command:
      - "start"
      - "--transport=tcp"
      - "--listen=0.0.0.0:8080"
      - "--publish=amqp"
      - "--amqp-address=rabbitmq:5672"
      - "--amqp-user=guest"
      - "--amqp-password=guest"
    depends_on:
      - rabbitmq

  ingress:
    image: ghcr.io/akshay2642005/fingerprint-engine/fingerprint-ingress:v0.4.1
    container_name: fingerprint-ingress
    restart: always
    ports:
      - "8080:8080"
    environment:
      - FPKG_LOG_LEVEL=info
      - FPKG_WORKERS=worker:8080
    command:
      - "start"
      - "--listen=0.0.0.0:8080"
      - "--worker=worker:8080"
    depends_on:
      - worker

volumes:
  rabbitmq_data:
  rabbitmq_logs:
```

The repository's own `compose.yml` is the same file with `build:` contexts in
place of the two `image:` lines, so a checkout builds both containers from
source while production pulls the released artifacts.

### Environment you may want to change

- `RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS` — the `guest/guest` pair
  is the standard RabbitMQ development default. Production deployments must
  override these and mirror them in the worker's `--amqp-user` /
  `--amqp-password` flags.
- `FPKG_LOG_LEVEL` — `err | warn | info | debug`; the worker and ingress
  honor it when no `--log-level` flag is given.
- `FPKG_LOG_FORMAT` — `text | json`; `json` for log aggregators.
- `FPKG_WORKERS` — the ingress's comma-separated worker list, an alternative
  to repeated `--worker=` flags. Useful for horizontal worker scaling.

## GHCR container images

The release pipeline publishes two images to GitHub Container Registry on
every annotated, versioned git tag (`v*`):

| Image | Source Dockerfile | Tags pushed |
| ----- | ----------------- | ----------- |
| `ghcr.io/akshay2642005/fingerprint-engine/fingerprint-worker` | `deploy/Dockerfile.worker` | `:<version>` (e.g. `v0.4.1`) and `:latest` |
| `ghcr.io/akshay2642005/fingerprint-engine/fingerprint-ingress` | `deploy/Dockerfile.ingress` | `:<version>` (e.g. `v0.4.1`) and `:latest` |

Jobs `release-docker` and `release-docker-ingress` build and push these
images with `docker/build-push-action`, tagging each with both the full
version and `latest`, and attaching OCI labels for source repository and
version. Both images are Alpine-based, run the component binary via `tini`
as PID 1 under an unprivileged service user, and expose port 8080. The
version tag always matches `build.zig.zon`, the single source of truth for
versioning.

Pull with the exact tag used by your deployment rather than `:latest` when
you need reproducibility; `:latest` is intended for rolling environments.

## Cross-platform native binaries

Each release also ships four tarballs, one per supported target, containing
all three executables (`fingerprint`, `worker`, `ingress`):

| Target | Archive | Environment |
| ------ | ------- | ----------- |
| Linux x86_64 (musl) | `fingerprint-<version>-x86_64-linux-musl.tar.gz` | Alpine, Debian, most containers |
| Linux aarch64 (musl) | `fingerprint-<version>-aarch64-linux-musl.tar.gz` | ARM64 Linux servers |
| macOS x86_64 | `fingerprint-<version>-x86_64-macos.tar.gz` | Intel Macs |
| macOS aarch64 | `fingerprint-<version>-aarch64-macos.tar.gz` | Apple Silicon Macs |

The musl builds need no glibc and run unchanged in Alpine-based images; the
macOS builds are for local development and thin-server deployments. Each
archive also includes the WebAssembly artifact separately as
`fingerprint-<version>.wasm` (an infrastructure artifact for benchmark and
test containers only—not shipped in the browser SDK).

Extract a Linux tarball on a server and run, for example:

```bash
tar xzf fingerprint-0.4.1-x86_64-linux-musl.tar.gz
./worker start --transport=tcp --listen=0.0.0.0:8080 \
  --publish=amqp --amqp-address=rabbitmq:5672 --amqp-user=... --amqp-password=...
```

The combined `fingerprint` binary dispatches `worker`/`ingress` subcommands
with identical argv contracts, so one artifact can serve both roles.

## How release artifacts are produced

The pipeline lives in `.github/workflows/release.yml` and triggers on an
annotated git tag push matching `v*` (for example `v0.4.1`):

1. **Pre-release tests** (`test`): runs `zig build test` on the tagged tree.
   Nothing else publishes until this job is green.
2. **Native binaries** (`build-binaries`): a four-target matrix; each job
   runs `zig build fingerprint worker ingress -Dtarget=<target>
   --release=safe`, bundles the three executables, and tars them into
   `fingerprint-<version>-<target>.tar.gz`.
3. **WASM** (`build-wasm`): `zig build wasm`, renamed to
   `fingerprint-<version>.wasm`.
4. **GitHub Release** (`create-release`, after 2 and 3): assembles the
   tarballs and WASM artifact, generates release notes referencing the image
   tags, npm package, and changelog, and publishes the release.
5. **GHCR images** (`release-docker`, `release-docker-ingress`): each logs
   into GHCR and pushes its image at `:<version>` and `:latest`.
6. **npm** (`publish-npm`): builds the browser SDK (`zig build
   clients:browser`) and publishes `@akshay2642005/fingerprint-sdk@<version>`
   unless that version already exists.

Versioning is compile-time-tracked: `build.zig` parses `.version` from
`build.zig.zon` and injects it into the binaries (CLI, AMQP connection
properties), and the release jobs derive image tags from the same git tag.
A drift between what the binary reports and what is on the registry is
therefore impossible by construction.

## Local container builds

For development, the build system drives Docker directly:

```bash
zig build docker:worker    # builds fingerprint-worker:<version>
zig build docker:ingress   # builds fingerprint-ingress:<version>
```

The equivalent script helpers:

```bash
zig build scripts -- docker build-worker [--tag=name]   # build the worker image
zig build scripts -- docker run [--tag=name]            # run it, publishing 8080
```

These tags deliberately match the release-pipeline artifacts after the
registry prefix, so a locally built image is interchangeable with a GHCR
pull.

## Verify the deployment

With the stack up, confirm each layer:

```bash
docker compose ps                                  # all three services Up
curl -s http://127.0.0.1:8080/healthz              # ingress liveness
zig build scripts -- amqp --address=127.0.0.1:5672 # broker round-trip smoke test
zig build scripts -- worker request --listen=127.0.0.1:8081  # canonical package → worker reply
```

The `amqp` script declares the `fingerprint` exchange, binds a throwaway
queue to `result.fingerprint-result`, publishes a reply frame through the
real worker publisher, and verifies the byte-identical round trip. `worker
request` sends the canonical signal-package fixture to a running worker and
cross-checks the returned digest against an in-process engine call; under
`docker compose` the worker's published host port is 8081.

Once those all pass, the stack is deployed. Move on to
[AMQP Topology](/docs/operating/amqp-topology/) to understand the message stream the
fraud platform consumes, and [Monitoring](/docs/operating/monitoring/) for the runbook
that keeps it observable.