# Conventions — Fingerprint Engine

## Conventional Commits & Semantic Versioning

All changes to this repository MUST follow the [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) specification. Versioning MUST strictly adhere to [Semantic Versioning 2.0.0](https://semver.org/).

### Commit Message Format

`<type>(<scope>): <description>` (Space after colon is MANDATORY)

### Types & Version Bumps

- `feat`: Minor (x.Y.z) - New feature
- `fix`: Patch (x.y.Z) - Bug fix
- `perf`: Patch (x.y.Z) - Performance improvement
- `docs`, `chore`, `style`, `refactor`, `test`: No bump (unless breaking)
- `BREAKING CHANGE:` (or `!` after type): Major (X.y.z)

## Git Operations

- No direct work on `main` or `master`. Every task MUST start with a feature branch or worktree via `kickoff-branch`.
- **Integrate (solo profile):** Ship with `bash scripts/land-branch.sh <branch> "<conventional message>"` after `release-branch` gates.
- `git push origin <feature-branch>` is allowed for backup; never push directly to `main`.
- **Git Attribution:** NEVER include `Co-authored-by`, `Co-Authored-By`, or any other footer that attributes code to an AI agent.
- Never create GitHub issues from automated workflows — produce local .md files in `specs/` instead.

## Always Green / Shift Left

Solo developers own the whole codebase. **Always Green** means Preflight and CI are green before any forward work — not "green enough for this task."

**Shift Left (1-10-100):** Defects cost roughly 1× to fix in development, 10× in integration, 100× in production. Fixing a red gate now is cheaper than shipping and debugging later.

**Preflight** — `zig build test` MUST pass before kickoff, develop, or verify phases advance.

## Discovered Defects

Any **reproducible gate failure** encountered during unrelated work is a discovered defect — not optional background noise.

**fix-or-log ladder (mandatory):**

1. **quick-fix** — trivial, data-only, or single-file fixes within guardrails.
2. **fix-bug** — when quick-fix guardrails abort, or the failure needs investigation (`specs/bugs/BUG-*.md` + TDD).
3. **Log** — only when reproduction is blocked after good-faith attempt; write a BUG spec and stop forward work.

Discovered fixes ship in the **same PR** but in **separate commits**. Never narrate a failure and continue.

**Hard block:** Red Preflight blocks forward progress until fix-or-log produces green.

### Banned dismissive phrases

| Banned phrase | Required behavior instead |
| --------------- | --------------------------- |
| Pre-existing / pre-existing issues | Run fix-or-log; prove with a passing repro after revert |
| unrelated to this session | Same — session boundaries do not waive green gates |
| not introduced by my changes | Bisect or fix anyway; solo-owner owns the whole tree |
| out of scope (ignoring a red gate) | Invoke quick-fix or fix-bug |

## specs/ — All Planning Output Goes Here

All domain docs, plans, and investigation outputs go in `specs/` at the project root.

| Layer | File | Purpose |
| ------- | ------ | --------- |
| Session | `specs/state.yaml` | Active flow, epic/bug, git, handoff |
| Release index | `specs/release-plan.yaml` | Target semver, WSJF epic list |
| Progress | `specs/execution-status.yaml` | Flat story/epic status |
| Intent | `specs/product/SCOPE_LATEST.yaml` | What should the product do? |
| North star | `specs/product/VISION_LATEST.yaml` | Initiative direction |
| Glossary | `specs/product/GLOSSARY_LATEST.yaml` | Domain terms |
| Architecture | `specs/tech-architecture/tech-stack.md` | Stack + architecture |
| Epics | `specs/epics/eNN-slug/` | Stories and tasks with `verify:` |

## Code Style

- Functions: 4–20 lines. Split if longer.
- Files: under 300 lines. Split by responsibility.
- One thing per function, one responsibility per module (SRP).
- Names: specific and unique. Avoid `data`, `handler`, `Manager`, `Service`.
- Types: explicit. No `any`, no untyped public functions.
- No code duplication. Extract shared logic into a function/module.
- Early returns over nested ifs. Max 2 levels of indentation.
- Conditionals: expressed as positives. Avoid negative flags.
- The Stepdown Rule: functions should descend exactly one level of abstraction.
- No magic strings or numbers — extract to named constants.
- Boolean logic in named functions — complex boolean expressions must be extracted into a named predicate.
- Remove dead code: unused functions, unreachable branches, stale imports must be deleted.
- Boy Scout Rule: leave every file you touch at least as clean as you found it.
- Law of Demeter: call only immediate collaborators.

## Comments

- Write WHY, not WHAT.
- Complex or non-obvious logic must include provenance links.
- Docstrings on public functions: intent + one usage example.
- No obvious comments that restate the code.
- No commented-out code — delete it; use git history to recover.

## Tests

- Tests live outside `src/` in `tests/`, mirroring production module structure.
- Tests run headless with a single command: `zig build test`.
- Every new function gets a test. Every bug fix gets a regression test.
- Tests are **F**ast, **I**ndependent, **R**epeatable, **S**elf-Validating, **T**imely.
- Test boundary conditions: empty input, maximum, minimum, off-by-one.
- Test through public interfaces only — assert on observable outcomes.
- Never skip or @ignore a test without an explicit ambiguity note.
- Every change must be verifiable with a single runnable command before done.

## Build Philosophy

| Step | Command |
| ------ | --------- |
| Build | `zig build` |
| Test | `zig build test` |
| WASM | `zig build wasm` |
| Native | `zig build native` |

Incremental development. One module at a time.

## Optimization Philosophy

Prefer compile-time work over runtime work:

- ✅ compile-time lookup tables
- ✅ compile-time validation
- ✅ immutable metadata
- ❌ runtime registration
- ❌ reflection
- ❌ dynamic dispatch
- ❌ unnecessary heap allocation

## Defensive Code

Where applicable in this project:

- **Retry with backoff** — for network/API calls
- **Timeout** — for long-running operations
- **Graceful degradation** — when external dependencies fail

## Guiding Principle

> **Correctness first. Performance second. Features third.**

A fast fingerprinting engine that produces inconsistent results is unacceptable.
Every subsystem should first be deterministic, well-tested, and maintainable.
Once correctness is guaranteed, optimize using Zig's compile-time capabilities.
