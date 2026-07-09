# Fingerprint Engine — Claude Code

Read CONVENTIONS.md before any GitHub or git operation.

## Project

High-performance, enterprise-grade browser fingerprinting SDK written in Zig.
Stack: Zig 0.16.0

## Commands

| Action | Command |
|--------|---------|
| Run    | `zig build` |
| Test   | `zig build test` |
| Build  | `zig build` |
| WASM   | `zig build wasm` |
| Native | `zig build native` |
| Preflight | `zig build test` |

## Architecture

Core engine (shared business logic) → Browser SDK (WebAssembly, signal collection) + Server Library (native, fingerprint matching, fraud detection). Strict layered dependency graph — dependencies flow downward, no circular deps.

## Conventions

- **Compile-time first:** validate at compile time, not runtime
- **Zero runtime allocation** in core algorithms
- **Deterministic:** same input, same output, any platform
- **Platform separation:** browser collects, core processes, server analyzes
- **Data-driven:** algorithms consume metadata, no large switch statements
- **Stable ABI:** integer sizes are intentional and breaking if changed
- **Public facade:** every module exports through `root.zig`
- **Subsystem-oriented files:** one file per subsystem, not one per type

## Never

- Platform-specific code must never contain fingerprint algorithms
- No circular dependencies between modules
- No runtime registration, reflection, or dynamic dispatch
- No heap allocation in core algorithms where avoidable
- No direct work on `main` or `master`
- Never dismiss reproducible gate failures as pre-existing or out of scope
- Never proceed on red Preflight or red CI — invoke `quick-fix` or `fix-bug` first

## Agent Rules

- **Workflow Mandate:** You MUST use the bigpowers skills (e.g. `plan-work`, `develop-tdd`) to perform tasks. DO NOT write code directly in response to a user prompt.
- **Always Green:** Preflight and CI must be green before forward work. Reproducible gate failures require fix-or-log per CONVENTIONS § Discovered Defects.
- Read `specs/` before writing code.
- All planning and specifications MUST be written to `specs/` before any code is generated.
- Write the minimum code that solves the stated problem. Nothing extra.
- Run tests after every change. Show evidence before declaring done.
- One clarifying question beats a wrong assumption baked into 200 lines.
- **Verification Mandate:** Every story implementation MUST end with step-by-step manual verification. Wait for user confirmation (UAT) before declaring done.
- **Traceability:** Every story MUST have at least one `// story: eNNsNN` tag in its implementing code or test file.
