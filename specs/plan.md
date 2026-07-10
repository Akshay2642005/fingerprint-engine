# Phase 10 — Browser SDK (WebAssembly)

> Exposes the fingerprint engine as a WebAssembly module consumable from browser JavaScript.

## Scope

1. **WASM entry point** — `src/browser/wasm/root.zig` with exported JS-compatible functions
2. **Feature buffer** — fixed-size internal buffer for collecting features without heap allocation
3. **Exported API**: `init`, `add_feature`, `compute_digest`, `get_error`, `reset`

### API Design

```
// JS usage:
// const m = await WebAssembly.instantiate(bytes, imports);
// const ptr = m.exports.fingerprint_init();
// m.exports.fingerprint_add_feature(ptr, CookieEnabled, 1, 0);
// const digest_ptr = m.exports.fingerprint_compute(ptr);
// const digest = new Uint8Array(m.exports.memory, digest_ptr, 32);

All functions use numeric handles and flat memory — no JS objects cross the boundary.
```

### Constraints

- No heap allocation — uses static internal buffer
- `entry = .disabled` (already set in build.zig)
- `rdynamic = true` (already set in build.zig)
