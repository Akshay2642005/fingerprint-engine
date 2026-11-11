<!-- // story: m8-observability -->

# ADR-017 — AMQP credential sourcing (env-only, CLI deprecated)

- **Status:** Adopted (2026-11-04)
- **Source:** `src/cmd/worker/worker.zig` (`--amqp-user`, `--amqp-password`),
  `src/cmd/main.zig` (usage), `compose.yml`,
  `src/cmd/ingress/ingress.zig` (`FPKG_HMAC_SECRET` precedent)
- **Extends:** ADR-007 (worker shape), ADR-011 (shared CLI components).
  Closes the "Known gap (S5/M8)" recorded in `specs/security/SECURITY_PLAN.md`
  §Secret handling.

## Context

The worker takes broker credentials as command-line flags:

```
--amqp-user=user  --amqp-password=pass
```

with `guest`/`guest` defaults (`src/cmd/worker/worker.zig`), and `compose.yml`
passes `--amqp-user=guest --amqp-password=guest` in the container command. Any
local process can read another process's argv (`ps`), and argv is commonly
captured in shell history, `docker inspect`, and process-supervision logs.

The corrective precedent already exists in the same codebase: the ingress takes
`FPKG_HMAC_SECRET` from the environment only, validates it at startup, refuses
to run with a weakened configuration, and never logs it. `FPKG_LOG_LEVEL`,
`FPKG_LOG_FORMAT`, and `FPKG_WORKERS` establish the same env-first pattern.

`SECURITY_PLAN.md` records this as a tracked gap to close before production
fanout, and the v0.6.0 verification checklist carries it forward as an M8 item.

## Decision

### 1. `FPKG_AMQP_USER` / `FPKG_AMQP_PASSWORD` are the supported source

Read at startup, the same way `FPKG_HMAC_SECRET` is. Validation:

- If one of the pair is set and the other is not, **fail startup** with a clear
  error rather than silently pairing a configured user with a default password.
- The password is never written to any log, error message, or metric label —
  not even its length. A failed handshake reports the broker's reply code and
  the user name, never the secret.
- Absent both → keep the `guest`/`guest` development default, and log a single
  `warn` line naming the env vars to set. The default must be loud, not quiet.

### 2. Precedence: environment wins; flags are deprecated and warn

- If both a flag and the env var are present, the **env var wins** and a warning
  says the flag was ignored. Rationale: a stale flag baked into an image or a
  compose file must not be able to override a rotated secret.
- Using `--amqp-user` / `--amqp-password` at all emits a deprecation warning
  pointing at the env vars.
- Both flags are **removed at v1.0.0**. This is a documented CLI break, allowed
  pre-1.0 and recorded in the v1.0.0 migration guide.

### 3. `compose.yml` stops putting credentials on the command line

- The worker service moves credentials to `environment:` reading
  `${FPKG_AMQP_USER:-guest}` / `${FPKG_AMQP_PASSWORD:-guest}`.
- A `.env.example` documents the variables; `.env` is added to `.gitignore`
  (it is not there today).
- The dev default stays `guest`, because that is what the bundled
  `rabbitmq:4-management` image provisions. Documented as dev-only.

### 4. Rotation is a restart, and that is stated

The publisher holds one long-lived connection, so rotating credentials means
updating the env and restarting the worker. The runbook records this and notes
that a rolling restart is safe: the reply path never depends on the broker
(ADR-016 §1), so collections keep being served while the worker reconnects.

**Not** in this ADR: `--amqp-address` / `--amqp-vhost` stay as flags. They are
not secrets, they are operationally visible, and moving them would break
compose DNS-based addressing for no security gain. Revisit only if address
discovery becomes dynamic.

**Rejected alternatives:** (a) credentials in a file path (`--amqp-secret-file`)
— an extra mount and an extra failure mode for no gain over env; (b) credentials
in a URL (`amqp://user:pass@host`) — the same argv exposure plus URL-encoding
hazards and easy accidental logging; (c) broker-side federated identity / mTLS —
the right long-term answer, but it is a platform/broker topology decision, not
a worker config change, and it belongs with the M10 trust work; (d) keep flags
and merely redact logs — argv is already exposed before logging happens.

## Consequences

**Positive**

- Credentials stop appearing in `ps`, shell history, and image metadata.
- The pattern is identical to `FPKG_HMAC_SECRET`, so there is one secret story.
- Configuring half a pair fails loudly instead of degenerating to a default.

**Negative / costs**

- A CLI break at v1.0.0; users with scripts must migrate (warned from v0.7.0).
- One more env var to document, and container orchestration must inject secrets
  (compose `.env`, or the platform's secret store).
- Restart-to-rotate is coarser than hot reload; acceptable while there is one
  connection.

**Revisit when:** the broker offers federated identity or mTLS and the platform
owns trust (M10), or when multiple brokers make per-connection credentials
necessary.

## Notes

- Precedent and validation style: `FPKG_HMAC_SECRET` handling in
  `src/cmd/ingress/ingress.zig` and the rotation note in
  `specs/security/SECURITY_PLAN.md` §Secret handling.
- The gap being closed is listed there as "Known gap (S5/M8)" and in the
  v0.6.0 verification checklist under "Carried forward".
- `.env` must be added to `.gitignore` as part of this change.
