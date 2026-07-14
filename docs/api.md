# Fingerprint Engine API Documentation

## Overview

The Fingerprint Engine is a browser fingerprinting SDK written in Zig 0.16.0. It provides:

- **Feature collection**: 102 browser signals across 21 categories (canvas, WebGL, audio, fonts, battery, media codecs, speech, input, permissions, etc.)
- **Deterministic hashing**: SHA-256 fingerprint digests
- **Normalization**: Type and bounds validation
- **Similarity scoring**: Feature-level and fingerprint-level comparison
- **Entropy analysis**: Shannon entropy measurement
- **Risk assessment**: Browser fingerprint risk scoring
- **Cross-platform**: WASM (browser), C ABI (server), Go (cgo), TypeScript

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Core Engine                       │
├─────────────┬─────────────┬─────────────┬───────────┤
│  Features   │    Hash     │ Serialize   │  Similar  │
│  Registry   │  Feature    │ Binary      │  Score    │
│  102 sigs   │  Fingerprint│ JSON        │  Entropy  │
│             │  Hasher     │             │  Risk     │
├─────────────┴─────────────┴─────────────┴───────────┤
│                       SDKs                          │
├─────────────────────┬───────────────────────────────┤
│  WASM + TypeScript  │  C ABI / C Header             │
│  (browser SDK)      │  (server — Go, C, Zig, etc.)  │
└─────────────────────┴───────────────────────────────┘
```

## Quick Start

### Browser (WASM + TypeScript)

```html
<script src="https://cdn.jsdelivr.net/npm/@fingerprint/sdk"></script>
<script>
  const fp = await Fingerprint.collect();
  console.log('Fingerprint:', fp.hex);       // 32-byte hex digest
  console.log('Signals:', fp.features.length); // ~102 signals
  console.log('Risk:', fp.risk);              // 0.0 – 1.0
  console.log('Entropy:', fp.entropy);        // bits/signal
</script>
```

Or with ES modules:

```typescript
import { FingerprintEngine, FeatureID } from '@fingerprint/sdk';

const engine = new FingerprintEngine();
engine.addBoolean(FeatureID.CookieEnabled, navigator.cookieEnabled);
engine.addString(FeatureID.UserAgent, navigator.userAgent);

const result = engine.compute();
console.log('Fingerprint:', result.hex);
console.log('Risk:', result.risk);
```

### Server (C ABI — Go, C, Zig, etc.)

```c
#include "fingerprint.h"

FingerprintEngine* engine = fingerprint_engine_create();
fingerprint_engine_add_feature(engine,
    FINGERPRINT_FEATURE_USER_AGENT,
    FINGERPRINT_TYPE_STRING,
    "Mozilla/5.0...", 14);

uint8_t digest[32];
fingerprint_engine_compute(engine, digest);

int risk = fingerprint_engine_risk(engine);
int entropy = fingerprint_engine_entropy(engine);

fingerprint_engine_destroy(engine);
```

> Any language with C FFI can call the engine.  
> For Go: `// #include "fingerprint.h"` + `import "C"`.

## Core Modules

### Features (`core.features`)

Defines the 102 browser signals and their metadata across 21 categories.

```zig
const FeatureID = core.features.FeatureID;
const FeatureType = core.features.FeatureType;

// FeatureID enum values:
// .UserAgent, .Language, .Platform, .HardwareConcurrency,
// .DeviceMemory, .ScreenWidth, .ScreenHeight, .Timezone, etc.
```

### Fingerprint (`core.fingerprint`)

The core data model for fingerprints.

```zig
const Fingerprint = core.fingerprint.Fingerprint;
const Feature = core.fingerprint.Feature;
const FeatureValue = core.fingerprint.FeatureValue;

// FeatureValue is a tagged union:
// .Boolean(bool)
// .String([]const u8)
// .Integer(i64)
// .Float(f64)
// .Bytes([]const u8)
// .StringArray([]const []const u8)
// .IntegerArray([]const i64)
// .FloatArray([]const f64)
// .BytesArray([]const []const u8)
```

### Hashing (`core.hashing`)

Deterministic SHA-256 fingerprinting.

```zig
// Hash a single feature
var hash: [32]u8 = undefined;
try core.hashing.hashFeature(feature.value, &hash);

// Hash an entire fingerprint
try core.hashing.hashFingerprint(fingerprint, &hash);

// Incremental hashing
var hasher = core.hashing.Hasher.init(schema_version, sdk_version, collected_at);
try hasher.add(feature.id, feature.value);
hasher.final(&hash);
```

### Serialization (`core.serialization`)

Binary and JSON encoding/decoding.

```zig
// Binary encode
var buf: [1024]u8 = undefined;
var w = std.Io.Writer.fromArrayList(&buf);
try core.serialization.encode(&w, fingerprint);

// Binary decode
var r = testing.Reader.init(&buf, &.{.{ .buffer = buf[0..len] }});
var decoded = try core.serialization.decode(&r, allocator);
defer decoded.deinit();

// JSON encode
var json_buf: [4096]u8 = undefined;
var json_w = std.Io.Writer.fromArrayList(&json_buf);
try core.serialization.jsonEncode(&json_w, fingerprint);
```

### Normalization (`core.normalization`)

Type and bounds validation.

```zig
// Validate feature types
const type_warnings = try core.normalization.validateTypes(fingerprint, allocator);
defer allocator.free(type_warnings);

// Check value bounds
const bound_warnings = try core.normalization.checkAllBounds(fingerprint, allocator);
defer allocator.free(bound_warnings);

// Full normalization (types + bounds)
const warnings = try core.normalization.normalize(fingerprint, allocator);
defer allocator.free(warnings);
```

### Similarity (`core.similarity`)

Feature-level and fingerprint-level comparison.

```zig
// Compare two feature values (0.0 to 1.0)
const score = core.similarity.featureScore(value_a, value_b);

// Compare two fingerprints (0.0 to 1.0)
const fp_score = core.similarity.fingerprintScore(fp_a, fp_b);
```

### Entropy (`core.entropy`)

Shannon entropy measurement.

```zig
// Shannon entropy of raw bytes (0.0 to 8.0 bits/byte)
const entropy = core.entropy.shannonEntropy(data);

// Fingerprint entropy (weighted average)
const fp_entropy = core.entropy.fingerprintEntropy(fingerprint);
```

### Risk (`core.risk`)

Browser fingerprint risk assessment.

```zig
const assessment = core.risk.computeRisk(fingerprint);
// assessment.score: 0.0 (low risk) to 1.0 (high risk)
// assessment.label: .low, .medium, .high, .critical
// assessment.flags: missing_features, bound_violations, etc.
```

## Browser SDK (WASM)

### Functions

| Function | Description |
| ---------- | ------------- |
| `fingerprint_init()` | Initialize the engine |
| `fingerprint_add_feature(id, type, ptr, len)` | Add a feature value |
| `fingerprint_compute()` | Compute the fingerprint digest |
| `fingerprint_get_digest_ptr()` | Get pointer to 32-byte digest |
| `fingerprint_reset()` | Reset the engine for reuse |
| `fingerprint_get_error()` | Get last error message |
| `fingerprint_feature_count()` | Get number of added features |
| `fingerprint_normalize()` | Validate types and bounds (returns warning count) |
| `fingerprint_risk()` | Compute risk score (0-100) |
| `fingerprint_entropy()` | Compute entropy (0-800) |

### Usage

```javascript
// Load WASM module
const module = await WebAssembly.instantiateStreaming(fetch('fingerprint.wasm'));
const { memory, fingerprint_engine_create, ... } = module.instance.exports;

// Create engine
const engine = fingerprint_engine_create();

// Add features (write to linear memory)
const encoder = new TextEncoder();
const ua = encoder.encode("Mozilla/5.0...");
const ptr = fingerprint_engine_alloc(ua.length);
new Uint8Array(memory.buffer, ptr, ua.length).set(ua);
fingerprint_engine_add_feature(1, 2, ptr, ua.length); // UserAgent, String

// Compute fingerprint
fingerprint_engine_compute();
const digest = new Uint8Array(memory.buffer, fingerprint_engine_get_digest_ptr(), 32);
console.log('Fingerprint:', Array.from(digest).map(b => b.toString(16).padStart(2, '0')).join(''));
```

## Server SDK (C ABI)

### Functions

| Function | Description |
| ---------- | ------------- |
| `fingerprint_engine_create()` | Create engine (returns handle) |
| `fingerprint_engine_destroy(handle)` | Destroy engine |
| `fingerprint_engine_add_feature(handle, id, type, data, len)` | Add feature |
| `fingerprint_engine_compute(handle, out)` | Compute digest |
| `fingerprint_engine_normalize(handle)` | Validate types and bounds (returns warning count) |
| `fingerprint_engine_risk(handle)` | Compute risk score (0-100) |
| `fingerprint_engine_entropy(handle)` | Compute entropy (0-800) |

### Usage (C)

```c
#include "fingerprint.h"

FingerprintEngine* engine = fingerprint_engine_create();
fingerprint_engine_add_feature(engine, 
    FINGERPRINT_FEATURE_USER_AGENT,
    FINGERPRINT_TYPE_STRING,
    "Mozilla/5.0...", 14);

uint8_t digest[32];
fingerprint_engine_compute(engine, digest);

// Processing
int warnings = fingerprint_engine_normalize(engine);
int risk = fingerprint_engine_risk(engine);     // 0-100
int entropy = fingerprint_engine_entropy(engine); // 0-800

fingerprint_engine_destroy(engine);
```

## Test Data

### Browser Fingerprints

- `tests/data/fingerprints/chrome_win10.json` — Chrome on Windows 10
- `tests/data/fingerprints/firefox_macos.json` — Firefox on macOS
- `tests/data/fingerprints/minimal.json` — Minimal valid fingerprint

### Similarity Matrix

- `tests/fixtures/datasets/similarity_suite.json` — 5 fingerprints with expected similarity scores

## Benchmarking

Run performance benchmarks:

```bash
zig build bench
```

Output:

```
Fingerprint Engine — Benchmark Harness
Zig 0.16.0 | Debug | x86_64
------------------------------------------------------------
                         Benchmark    Ops/Sec        Avg
------------------------------------------------------------
                  hashing: hashFeature    2659221 376ns
              hashing: hashFingerprint     171656 5.83µs
           hashing: incremental hasher     182705 5.47µs
          serialization: binary encode     274816 3.64µs
            serialization: json encode     165755 6.03µs
          normalization: validateTypes     300409 3.33µs
            normalization: checkBounds    1513317 660ns
              normalization: normalize     124247 8.05µs
              similarity: featureScore     330737 3.02µs
          similarity: fingerprintScore      56700 17.64µs
               entropy: shannonEntropy    1222344 818ns
           entropy: fingerprintEntropy     258572 3.87µs
------------------------------------------------------------
```

## Fuzz Testing

Run fuzz tests:

```bash
zig build test -- --fuzz
```

Fuzz targets:

- `fuzz_decode.zig` — Binary decode with arbitrary bytes
- `fuzz_normalize.zig` — Normalization with arbitrary features
- `fuzz_hashing.zig` — Hashing with arbitrary values

## Security

See [SECURITY.md](../SECURITY.md) for security policy and vulnerability reporting.
