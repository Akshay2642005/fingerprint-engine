# Architecture Overview

## System Design

The Fingerprint Engine is designed as a layered architecture with clear separation between core logic, platform integration, and consumer SDKs.

### Layer 1: Core Engine (`src/core/`)

Platform-independent fingerprint processing with zero external dependencies.

```
src/core/
├── features/          # Feature definitions and registry
│   ├── definitions.zig  # 102 FeatureIDs with types and weights across 21 categories
│   ├── model.zig        # FeatureType, FeatureDefinition
│   └── registry.zig     # Compile-time feature registry
├── fingerprint/       # Core data model
│   ├── feature.zig      # Feature struct
│   ├── value.zig        # FeatureValue tagged union
│   └── metadata.zig     # FingerprintMetadata
├── hashing/           # Deterministic SHA-256 hashing
│   ├── feature.zig      # Single feature hashing
│   ├── fingerprint.zig  # Full fingerprint hashing
│   └── hasher.zig       # Incremental hasher
├── serialization/     # Binary and JSON encoding
│   ├── binary.zig       # TLV binary format
│   └── json.zig         # Human-readable JSON
├── normalization/     # Input validation
│   ├── types.zig        # Type checking
│   ├── bounds.zig       # Range validation
│   └── normalize.zig    # Combined validation
├── validation/        # Required feature checking
│   └── required.zig     # Static bitset presence check
├── similarity/        # Fingerprint comparison
│   ├── feature.zig      # Feature-level scoring
│   └── fingerprint.zig  # Weighted fingerprint scoring
├── entropy/           # Information theory metrics
│   └── entropy.zig      # Shannon entropy calculation
└── risk/              # Risk assessment
    └── risk.zig         # Risk scoring and flagging
```

### Layer 2: Platform SDKs

Platform-specific wrappers that import the core engine.

```
src/
├── browser/
│   ├── wasm/
│   │   └── root.zig      # WASM exports for browsers
│   └── bindings/
│       ├── types.ts       # TypeScript type definitions
│       ├── engine.ts      # FingerprintEngine class
│       └── index.ts       # Barrel exports
└── server/
    ├── native/
    │   └── root.zig       # C ABI for native linking
    └── api/
        └── c/
            └── fingerprint.h  # C header file
```

### Layer 3: Consumer SDKs

Language-specific packages for end users.

```
packages/
├── browser/
│   └── @fingerprint/sdk   # npm package
└── server/
    ├── python/
    │   └── fingerprint-sdk  # PyPI package
    └── rust/
        └── fingerprint-sdk  # crates.io crate
```

## Data Flow

### Browser Collection Flow

```
┌─────────────────────────────────────────────────────────┐
│                    Browser                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │ navigator   │  │ screen      │  │ canvas      │     │
│  │ userAgent   │  │ width       │  │ hash        │     │
│  │ language    │  │ height      │  │             │     │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘     │
│         │                │                │             │
│         └────────────────┼────────────────┘             │
│                          │                              │
│                  ┌───────▼───────┐                      │
│                  │ WASM Engine   │                      │
│                  │ add_feature() │                      │
│                  │ compute()     │                      │
│                  └───────┬───────┘                      │
│                          │                              │
│                  ┌───────▼───────┐                      │
│                  │ 32-byte hash  │                      │
│                  └───────────────┘                      │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
                  ┌───────────────┐
                  │   Server      │
                  │  (match/track)│
                  └───────────────┘
```

### Server Processing Flow

```
┌─────────────────────────────────────────────────────────┐
│                    Server                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │ Receive     │  │ Decode      │  │ Normalize   │     │
│  │ fingerprint │  │ binary/JSON │  │ validate    │     │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘     │
│         │                │                │             │
│         └────────────────┼────────────────┘             │
│                          │                              │
│                  ┌───────▼───────┐                      │
│                  │   Hash        │                      │
│                  │ SHA-256       │                      │
│                  └───────┬───────┘                      │
│                          │                              │
│         ┌────────────────┼────────────────┐             │
│         │                │                │             │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐     │
│  │ Similarity  │  │ Entropy     │  │ Risk        │     │
│  │ score       │  │ analysis    │  │ assessment  │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
└─────────────────────────────────────────────────────────┘
```

## Binary Format

The binary format uses a compact TLV (Type-Length-Value) encoding:

```
┌─────────────────────────────────────────────────────────┐
│ Magic: "FNGR" (4 bytes)                                │
├─────────────────────────────────────────────────────────┤
│ Schema Version: u16 LE                                 │
├─────────────────────────────────────────────────────────┤
│ Feature Count: u16 LE                                  │
├─────────────────────────────────────────────────────────┤
│ Features:                                              │
│   ┌───────────────────────────────────────────────────┐│
│   │ FeatureID: u16 LE                                ││
│   │ Type: u8                                         ││
│   │ Payload Length: u32 LE                           ││
│   │ Payload: [length] bytes                          ││
│   └───────────────────────────────────────────────────┘│
│   ... (repeated for each feature)                      │
└─────────────────────────────────────────────────────────┘
```

## Hashing Algorithm

Fingerprint hashing follows these steps:

1. **Hash metadata**: Schema version + SDK version + collection timestamp
2. **Sort features**: By FeatureID (deterministic order)
3. **Hash each feature**: Type tag + feature ID + value hash
4. **Combine**: Concatenate all hashes and compute final SHA-256

```zig
// Pseudocode
hash = SHA256()
hash.update(schema_version)
hash.update(sdk_version)
hash.update(collected_at)

for feature in sorted(features):
    hash.update(feature.id)
    hash.update(type_tag)
    hash.update(value_hash(feature.value))

return hash.final()
```

## Memory Management

### Zero-Allocation Paths

- Feature construction
- Single feature hashing
- Fingerprint digest computation
- Entropy calculation

### Allocator-Required Paths

- Binary/JSON serialization (uses ArrayList)
- Normalization (returns warning slices)
- Decoding (allocates feature arrays)

### Safety Patterns

```zig
// Error cleanup
const features = try allocator.alloc(Feature, count);
errdefer allocator.free(features);

// Deferred cleanup
defer {
    for (features) |f| freeFeatureValue(allocator, f.value);
    allocator.free(features);
}
```

## Concurrency Model

The core engine is designed for single-threaded use:

- No global state
- No locks or atomics
- Thread safety via separate engine instances
- WASM is inherently single-threaded

## Platform Considerations

### WASM (Browser)

- Linear memory model
- No filesystem access
- No network access
- Byte-level ABI crossing

### Native (Server)

- C ABI for maximum compatibility
- Handle-based resource management
- Page allocator for simplicity
- No libc dependency

## Testing Strategy

### Unit Tests

- Each module has its own test file
- Tests live in `tests/` outside `src/`
- Public API only via `root.zig`

### Fuzz Tests

- Binary decode with arbitrary bytes
- Normalization with random features
- Hashing determinism verification

### Integration Tests

- Cross-platform CI (Linux, macOS, Windows)
- WASM build verification
- Native library build verification

### Test Data

- Real browser fingerprints (Chrome, Firefox)
- Similarity matrix with expected scores
- Binary round-trip fixtures
