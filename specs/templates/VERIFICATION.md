# Verification — <Milestone / Slice / Story>

Checklists for manual verification and UAT. Per `CONVENTIONS.md`
(Verification Mandate), a story is not done until the checklist is executed
and the user confirms.

## Gate

- [ ] `zig build test --summary all` green.
- [ ] Slice-specific build steps green (`zig build wasm`, `zig build worker
      --release=safe`, `zig build clients:browser`, …).

## Checklist

1. [ ] First behavioral item — expected observable result.
2. [ ] Second item — including the negative case (what must NOT happen).
3. [ ] Determinism / replay case (run twice, identical result).

## UAT

- [ ] User ran the command/flow and confirmed the output.
- [ ] Evidence recorded (paste the actual output here before closing).
