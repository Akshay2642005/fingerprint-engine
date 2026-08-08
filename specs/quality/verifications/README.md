# Verifications — Fingerprint Engine

Manual verification / UAT checklists. Per `CONVENTIONS.md` (Verification
Mandate), every story implementation ends with step-by-step manual
verification and waits for user confirmation (UAT) before declaring done.

## Files

| File | Contents |
|------|----------|
| `v0.2.x.md` | Evidence for released milestones (v0.1.0 … v0.2.2), including the 2026-08-08 session evidence |
| `backlog-s1-s6.md` | Planned verification checklists for the audit backlog slices S1–S6 |

## How to run a verification

1. Machine gate first: `zig build test --summary all` green, and the slice's
   own command sequence (`zig build wasm`, `zig build worker --release=safe`,
   `zig build clients:browser`, etc.) from `README.md` / `docs/`.
2. Follow the checklist top to bottom; record the actual output/evidence.
3. For anything user-visible (CLI, npm package, Docker image), the user
   confirms (UAT) before the story is closed.
4. Never mark a milestone verified on green CI alone — the checklist items
   exercise the *behavior* CI can't see (live broker, real browser, container
   run).
