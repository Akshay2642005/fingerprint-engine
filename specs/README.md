# Specs — Fingerprint Engine

Master index for all planning documentation. Everything is written before
code (per `CONVENTIONS.md`), and status files are refreshed after every
release. Current release: **v0.4.1** (2026-08-29), Zig **0.14.1**.

## Document map

The tree is organized by concern (lifecycle), not by phase:

```
specs/
├── product/        WHAT we build and why        (vision, scope, glossary, snapshots)
├── decisions/      Why we build it this way     (ADRs 0001–0010 + locked rework series)
├── architecture/   How it is designed           (tech stack, plans, subsystem designs)
├── planning/       When and in what order       (milestone plan, status trackers)
├── quality/        How we prove it works        (test plan, bugs, audits, verifications)
├── security/       How we keep it safe          (threat model, hardening plan)
├── archive/        What is superseded           (epic archive, dead-end plans)
└── templates/      Reusable document templates  (ADR, DESIGN, VERIFICATION)
```

## Index

| Path | Purpose | Status |
|------|---------|--------|
| `product/VISION.md` | Initiative direction and non-targets | Current |
| `product/SCOPE.md` | What the product does — targets, milestones, out-of-scope | Current |
| `product/GLOSSARY.yaml` | Domain terms (wire, engine, platform) | Current |
| `product/snapshots/` | "What exists today" per release (`v0.4.0.md`) | Current |
| `decisions/` | ADR-0001…0011 — architectural decision records | Adopted |
| `decisions/rework/` | Locked D1–D20 rework series: ANALYSIS, DECISIONS, DESIGN, MIGRATION | Complete |
| `architecture/tech-stack.md` | Toolchain, module inventory, formats, build targets | Current |
| `architecture/design-plan.md` | Current design state + planned additions | Current |
| `architecture/impact.md` | Impact of the rework and the backlog slices | Current |
| `architecture/refactor.md` | Executed old→new mapping + outstanding refactors | Current |
| `architecture/ingress.md` | F-1/M5 — HTTP ingress design (shared CLI folder per ADR-011, FPKG translation, worker pool) | Approved, S4 |
| `architecture/logging.md` | F-2 — application logging design (`src/log.zig`, levels, JSON) | Approved, unbuilt |
| `planning/PLAN.md` | Milestone plan — M1–M4 (done) + M5 (next) + slices S1–S6 | Current |
| `planning/STATUS.yaml` | Epic-level execution ledger (e01–e12) + rework breakdown | Current |
| `planning/PHASES.yaml` | Discover → design → plan → build → verify → release phases | Current |
| `planning/RELEASES.yaml` | Per-release records (v0.1.0 → v0.4.1) and superseded plans | Current |
| `planning/SESSION.yaml` | Session state — active flow, git, modules, CI, handoff | Current |
| `quality/TEST_PLAN.md` | Test layers, pinned goldens, planned additions | Current |
| `quality/BUGS.yaml` | Confirmed bug tracker (BUG-001 … BUG-003) | Open |
| `quality/audits/` | Repository audits (`2026-08-08.md` — bugs, gaps, features) | Current |
| `quality/verifications/` | Manual verification / UAT checklists per milestone | Current |
| `security/SECURITY_PLAN.md` | Threat model, security actions by slice | Current |
| `archive/epics.md` | Superseded epic material kept for history | Current |

## How to use these docs

- **Working on a bug or feature?** Read `quality/BUGS.yaml` and
  `quality/audits/2026-08-08.md` (slices S1–S6), then the design doc for the
  slice (`architecture/ingress.md`, `architecture/logging.md`).
- **Changing an architecture decision?** Update the matching `decisions/`
  ADR first; `decisions/rework/DECISIONS.md` is the source of truth for the
  rework series (D1–D20) and must be updated if a decision changes.
- **After a release?** Refresh `planning/{SESSION,PHASES,STATUS,RELEASES}.yaml`,
  the `product/snapshots/` snapshot, and the verification docs.
- **Starting a new doc?** Use the `templates/` ADR, DESIGN, and VERIFICATION
  templates so new specs match the existing ones.

## Source of truth

- Wire/API details: `src/` code + `docs/` user docs (never the specs).
- Decisions: `decisions/` (ADRs) + `decisions/rework/DECISIONS.md` (D-series).
- Test counts: CI summary (`zig build test --summary all`); specs keep
  best-effort copies (BUG-003).
