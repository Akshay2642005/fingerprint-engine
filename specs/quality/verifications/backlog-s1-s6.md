# Planned verification — backlog slices S1–S6

Checklists to run when each slice lands (from `specs/quality/audits/2026-08-08.md`).
Gate for every slice: `zig build test --summary all` green; each commit
compiles.

## S1 — BUG-001 + H-1 idle timeout + H-2 graceful shutdown

- [ ] `zig build test` green; `npm test --prefix src/clients/browser` green.
- [ ] SDK reply parsing fixed: a reply with `features=3, schema=2` now reports
      `featureCount=3, schemaVersion=2` (was swapped). Verify by running
      `zig build scripts -- worker request` and checking the SDK displays
      match the engine's output.
- [ ] TS test asserts the real wire layout (schema at 35..37, count at 33..35)
      and pins against the digest constant (features=3, schema=2).
- [ ] Worker tcp: a client that connects and writes < 48 bytes then stalls no
      longer wedges the accept loop — the worker serves the next request
      after the idle timeout (verify with a raw socket + subsequent
      `worker request`).
- [ ] SIGTERM/SIGINT mid-idle: worker exits cleanly (0) and drains in-flight
      requests during a sustained request.

## S2 — Version SSoT (F-3 + BUG-002 + BUG-003)

- [ ] `worker version` prints the injected `package_version` (matches
      `build.zig.zon`).
- [ ] AMQP connection properties advertise the injected version; `wasm.zig`
      `sdk_version` matches the release.
- [ ] `scripts` docker tag derives from the injected version.
- [ ] `specs/planning/SESSION.yaml` and `specs/planning/STATUS.yaml` counts refreshed.

## S3 — Application logging (F-2, `specs/architecture/logging.md`)

- [ ] `worker --log-level=err` suppresses the listening announcement but still
      serves frames (integration test).
- [ ] `--log-format=json` emits parseable JSON lines with ts/level/scope/msg.
- [ ] `scripts amqp get --quiet` silences the `info(amqp)` connection dump.
- [ ] `FPKG_LOG_LEVEL` env honored (CLI wins over env).
- [ ] Integration-test output contract intact: `worker: listening on host:port`
      and bench `Completed 12 benchmarks.` still emitted verbatim at default
      level.

## S4 — HTTP ingress MVP (F-1, `specs/architecture/ingress.md`)

- [ ] `zig build ingress` and `zig build docker:ingress` green.
- [ ] POST the canonical `signal-package-v2.bin` body with `x-fpkg-*` headers
      through a real worker (tcp) + ingress → 200 with digest
      `db29fc13…e6c75` (integration test).
- [ ] Oversized body → 413; integrity mismatch → 400; unknown schema → 415;
      dead worker + live worker → retry lands on the live worker with the
      same digest.
- [ ] `GET /healthz` → 200.
- [ ] SIGTERM mid-poll → clean exit (0).
- [ ] `docker run` the ingress image; browser demo POSTs to it and shows the
      worker reply.
- [ ] UAT: user runs the full browser → ingress → worker loop locally.

## S5 — AMQP consumer + DLQ (F-4)

- [ ] Push consumption (`basic.consume` + QoS) works for command/control.
- [ ] Failed/poison publishes land in a dead-letter queue instead of
      vanishing; worker no longer logs-and-drops.
- [ ] Consumer e2e runs against a live broker and skips cleanly when none is
      reachable.
- [ ] UAT: user inspects DLQ + results in the management UI.

## S6 — Full-stack compose + release surface (F-5/F-6)

- [ ] `docker compose up` runs browser → ingress → worker → RabbitMQ loop
      locally (demo hits the compose ingress).
- [ ] `fingerprint-ingress` image pushed to GHCR alongside the worker and
      listed in release notes.
- [ ] Release notes updated; docs/specs status files refreshed.
- [ ] UAT: user runs the full stack and a release end-to-end.
