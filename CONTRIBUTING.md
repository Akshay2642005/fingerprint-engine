# Contributing to Fingerprint Engine

Thanks for your interest in contributing! Please read the
[Code of Conduct](CODE_OF_CONDUCT.md) first — we expect everyone who
participates in this project to follow it.

## Project Overview

Fingerprint Engine is a deterministic, zero-dependency browser
fingerprinting engine written in Zig. It ships one artifact — the browser
WASM module — and knows nothing about transport, queues, databases, or
business logic. The core contains only deterministic computation.

Before writing code, read the design docs:

- `specs/` — decisions, architecture, and migration plans
- `docs/` — GitHub Pages site (index, API, architecture)

## Development Setup

The project targets **Zig 0.14.1**. Install it via
[zvm](https://github.com/tristanisham/zvm) or from the
[Zig downloads](https://ziglang.org/download/) page.

```bash
zvm install 0.14.1
zvm use 0.14.1
zig version   # must print 0.14.1
```

## Build & Test

Everything is a `zig build` step — no Node, no scripts, no separate
toolchains:

```bash
# Preflight: unit + integration/e2e tests (must be green before any change)
zig build test --summary all

# Unit tests matching a filter
zig build test -- "hashing"

# WebAssembly module (zig-out/bin/fingerprint.wasm)
zig build wasm

# Browser npm package (src/clients/browser/dist/)
zig build clients:browser

# Performance benchmarks
zig build bench

# Docs snapshot (zig-out/docs/)
zig build docs
```

Rules of thumb:

- Run `zig build test` after **every** change and show the result.
- Use `--release=safe` / `--release=small`, never `-Doptimize`
  (0.14.1 build API).
- Keep tests **F**ast, **I**ndependent, **R**epeatable,
  **S**elf-Validating, **T**imely.

## How to Contribute

1. **Fork** the repository on GitHub.
2. **Create a feature branch off `develop`** — never commit directly to
   `master` (locked) or `develop` (integration):

   ```bash
   git fetch origin
   git checkout -b feat/my-change origin/develop
   ```

3. **Make your change.** Keep it minimal and focused. One responsibility
   per module, one thing per function, no dead code.
4. **Add or update tests** for the code you changed. Every new function
   gets a test; every bug fix gets a regression test.
5. **Run the preflight** and confirm it is green:

   ```bash
   zig build test --summary all
   ```

6. **Commit** following the commit conventions below.
7. **Open a pull request** targeting `develop` and fill out the
   [pull request template](.github/PULL_REQUEST_TEMPLATE.md). CI runs
   automatically on your PR; it must pass before the PR can merge. `develop`
   is merged to `master` only after the full gate — test suite, simulations,
   and regression testing — is green.

## Commit Conventions

All commits follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>
```

- Space after the colon is mandatory.
- Subject line limited to 50 characters, imperative mood,
  no trailing punctuation.
- Common types: `feat`, `fix`, `perf`, `docs`, `chore`, `style`,
  `refactor`, `test`.
- Breaking changes add `!` after the type or a `BREAKING CHANGE:`
  footer.
- Versioning follows [Semantic Versioning](https://semver.org/).
- Do not add attribution footers (e.g., `Co-authored-by`) to commit
  messages.

Examples:

```
feat(core): add similarity scoring for feature pairs
fix(serialization): handle empty payload in TLV decoder
docs: refresh architecture diagram
```

## Code Style

See `CONVENTIONS.md` at the repository root for the full style guide.
Highlights:

- Compile-time work over runtime work; no reflection or dynamic dispatch.
- No magic strings or numbers — extract named constants.
- Early returns over nested ifs; max two levels of indentation.
- Tests live outside `src/` in `tests/`, mirroring production modules.
- Write *why* in comments, not *what*.

## Reporting Issues

Found a bug or have an idea? Open an issue using the
[bug report](.github/ISSUE_TEMPLATE/bug_report.yml) or
[feature request](.github/ISSUE_TEMPLATE/feature_request.yml)
template. Include your Zig version, OS, and browser where relevant, plus
a minimal repro if you can.
