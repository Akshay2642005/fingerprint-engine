# Epic archive

Superseded epic material kept for history. Nothing here is active work.

## Why an archive

`specs/planning/STATUS.yaml` and `specs/planning/PLAN.md` once planned epics that the
distributed rework made obsolete (see `specs/decisions/rework/ANALYSIS.md` F7/F8 and
`specs/decisions/rework/DECISIONS.md` D10/D15). Rather than deleting the reasoning, the
obsolete items are recorded here with pointers to the decision that replaced
them.

## Archived items

| Item | Original plan | Replaced by | Decision |
|------|---------------|-------------|----------|
| Native server SDK + C ABI (`src/server/`, `fingerprint.h`) | M1.2, `zig build native` | Docker worker containers | D10/D11 |
| PyPI package (`packages/server/python`) | M2.2 | dropped — no native SDK | D10, e06 |
| Cargo crate (`packages/server/rust`) | M2.3 | dropped — no native SDK | D10, e07 |
| In-browser canonical fingerprinting (WASM compute, UMD base64 template) | M1.1 / M2.1 | hand-written TS SDK collecting + packaging only | D14 |
| Server-side matching engine / fingerprint database in this repo | M4.2 | Go fraud platform (separate repo) | D15/D18, e10 |
| RabbitMQ on the inbound path (browser → broker → workers) | rework draft | inbound FPKG request/response; AMQP outbound only | D16 |
| `build.mjs` node package build | D13-era | `zig build clients:browser` | D13/D14 |
| Zig 0.16 toolchain (`std.Io`, 0.16 build API) | pre-rework | Zig 0.14.1 | D1 |

## Adding to the archive

When a decision supersedes an active plan item: update the decision first
(`adr/`, `rework/DECISIONS.md`), then move the plan item here with a one-line
pointer to the deciding ADR/decision.
