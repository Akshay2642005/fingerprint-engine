# Phase 11 — Server SDK (Native C ABI)

> Exposes the fingerprint engine as a C-compatible native static/dynamic library for server-side integration.

## Scope

1. **C ABI entry point** — `src/server/native/root.zig` with exported C-compatible functions
2. **Opaque handle** — pointer-based API with `create`/`destroy` lifecycle
3. **Exported API**: `fingerprint_engine_create`, `fingerprint_engine_destroy`, `fingerprint_engine_add_feature`, `fingerprint_engine_compute`, `fingerprint_engine_get_error`
4. **Test coverage** — native library tests

### API Design

```c
// C header equivalent:
typedef struct FingerprintEngine FingerprintEngine;

FingerprintEngine* fingerprint_engine_create(void);
void fingerprint_engine_destroy(FingerprintEngine* engine);
int fingerprint_engine_add_feature(FingerprintEngine* engine,
    int feature_id, int value_type,
    const unsigned char* value_data, int value_len);
int fingerprint_engine_compute(FingerprintEngine* engine,
    unsigned char* out_digest, int* out_len);
const char* fingerprint_engine_get_error(FingerprintEngine* engine);
```

### Constraints

- Uses system allocator (native = has heap)
- C ABI compatible types (int, unsigned char*, etc.)
- No global state — thread-safe handle-based design
