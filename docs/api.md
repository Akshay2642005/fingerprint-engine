# Fingerprint Engine API Documentation

## Overview

The Fingerprint Engine is a browser fingerprinting engine written in
Zig 0.14.1. It provides:

- **Feature collection**: 102 browser signals across 21 categories (canvas, WebGL, audio, fonts, battery, media codecs, speech, input, permissions, etc.)
- **Deterministic hashing**: SHA-256 fingerprint digests
- **Normalization**: Type and bounds validation
- **Similarity scoring**: Feature-level and fingerprint-level comparison
- **Entropy analysis**: Shannon entropy measurement
- **Risk assessment**: Browser fingerprint risk scoring
- **Serialization**: Compact TLV binary and JSON codecs
- **WASM**: The only shipped artifact — `ReleaseSmall`, built by Zig

There is no native SDK and no C ABI. Fingerprint workers run the engine as
Docker containers.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Engine (Zig)                     │
├─────────────┬─────────────┬─────────────┬───────────┤
│   model     │    core     │serialization│  browser  │
│  registry   │  hashing    │ binary      │  (WASM)   │
│  102 sigs   │  normalize  │ JSON        │  exports  │
│  fingerprint│  similarity │             │           │
│             │  entropy    │             │           │
│             │  risk       │             │           │
├─────────────┴─────────────┴─────────────┴───────────┤
│  dependencies flow inward; no transport, no I/O     │
└─────────────────────────────────────────────────────┘
```

## Quick Start

### Browser (WASM — script tag)

```html
<script src="https://cdn.jsdelivr.net/npm/@akshay2642005/fingerprint-sdk"></script>
<script>
  const result = await Fingerprint.collect();
  console.log('Digest:',  result.hex);      // 64-char hex digest
  console.log('Signals:', result.signals);  // ~102
  console.log('Risk:',    result.risk);     // 0.0 – 1.0
  console.log('Entropy:', result.entropy);  // bits/signal
  console.log('Warnings:', result.warnings);// normalization warning count
</script>
```

`Fingerprint.collect()` returns:

| Field | Type | Description |
| ----- | ---- | ----------- |
| `hex` | `string` | 64-char hex digest |
| `digest` | `Uint8Array` | 32-byte digest |
| `risk` | `number` | 0.0 (low) – 1.0 (high) |
| `entropy` | `number` | bits/signal |
| `warnings` | `number` | normalization warning count |
| `signals` | `number` | feature count |
| `collectedAt` | `number` | epoch ms |

### Browser (TypeScript — lower level)

```typescript
import { FingerprintEngine, FeatureID } from '@akshay2642005/fingerprint-sdk';

const engine = await FingerprintEngine.create('/fingerprint.wasm');
engine.addString(FeatureID.UserAgent, navigator.userAgent);
engine.addBoolean(FeatureID.CookieEnabled, navigator.cookieEnabled);

const result = engine.compute();          // { digest, featureCount }
const risk = engine.risk();               // 0.0 – 1.0
const entropy = engine.entropy();         // bits/signal
const warnings = engine.normalize();      // warning count
```

## Core Modules

### Model (`model`)

Defines the 102 browser signals and their metadata across 21 categories.

```zig
const model = @import("model");

// FeatureID enum values:
// .UserAgent, .Language, .Platform, .HardwareConcurrency,
// .DeviceMemory, .ScreenWidth, .ScreenHeight, .Timezone, etc.
```

### Fingerprint model (`model`)

The core data model for fingerprints.

```zig
const Fingerprint = model.Fingerprint;
const Feature = model.Feature;
const FeatureValue = model.FeatureValue;

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
const core = @import("core");

// Hash a single feature
var hash: [32]u8 = undefined;
try core.hashing.hashFeature(feature.value, &hash);

// Hash an entire fingerprint
try core.hashing.hashFingerprint(fingerprint, &hash);

// Hash a feature slice (used by the WASM target)
try core.hashing.hashFingerprintBuffer(features, &hash);

// Incremental hashing
var hasher = core.hashing.Hasher.init(schema_version, sdk_version, collected_at);
try hasher.add(feature.id, feature.value);
hasher.final(&hash);
```

### Serialization (`serialization`)

Binary and JSON encoding/decoding.

```zig
const serialization = @import("serialization");

// Binary encode
var buf: [1024]u8 = undefined;
var w = std.io.Writer(...);
try serialization.encode(&w, fingerprint);

// Binary decode
var decoded = try serialization.decode(&r, allocator);
defer decoded.deinit();

// JSON encode
try serialization.jsonEncode(&json_w, fingerprint);
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
const assessment = core.risk.computeRisk(fingerprint, allocator);
// assessment.score: 0.0 (low risk) to 1.0 (high risk)
// assessment.label: .low, .medium, .high, .critical
// assessment.flags: missing_features, bound_violations, etc.
```

## Browser SDK (WASM)

### Exported Functions

| Function | Description |
| ---------- | ------------- |
| `fingerprint_init()` | Initialize the engine |
| `fingerprint_reset()` | Reset all features |
| `fingerprint_feature_count()` | Number of added features |
| `fingerprint_get_error()` | Pointer to last error message |
| `fingerprint_add_boolean(id, value)` | Add a boolean feature |
| `fingerprint_add_integer(id, value)` | Add an integer feature |
| `fingerprint_add_float(id, value)` | Add a float feature |
| `fingerprint_add_string(id, ptr, len)` | Add a string feature |
| `fingerprint_add_bytes(id, ptr, len)` | Add a bytes feature |
| `fingerprint_compute()` | Compute digest (returns pointer) |
| `fingerprint_get_digest_ptr()` | Pointer to the 32-byte digest |
| `fingerprint_get_scratch_ptr()` | Pointer to the 64 KB scratch buffer |
| `fingerprint_normalize()` | Validate types and bounds (warning count) |
| `fingerprint_risk()` | Risk score (0.0–1.0) |
| `fingerprint_entropy()` | Entropy (bits/signal × 100) |

### Error Codes

| Code | Value |
| ---- | ----- |
| `success` | 0 |
| `buffer_full` | 1 |
| `invalid_feature_id` | 2 |
| `invalid_value_type` | 3 |
| `not_initialized` | 4 |
| `invalid_input` | 5 |

## Test Data

### Browser Fingerprints

- `tests/data/fingerprints/chrome_win10.json` — Chrome on Windows 10
- `tests/data/fingerprints/firefox_macos.json` — Firefox on macOS
- `tests/data/fingerprints/minimal.json` — Minimal valid fingerprint

### Similarity Matrix

- `tests/fixtures/datasets/similarity_suite.json` — fingerprints with expected similarity scores

## Benchmarking

Run performance benchmarks:

```bash
zig build bench
```

12 benchmark targets cover hashing, serialization, normalization, similarity,
and entropy (illustrative output):

```
Fingerprint Engine — Benchmark Harness
Zig 0.14.1 | ReleaseSafe | x86_64
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

Fuzz targets live in `tests/fuzz/` and run as part of the test suite:

- `fuzz_decode.zig` — Binary decode with arbitrary bytes
- `fuzz_normalize.zig` — Normalization with arbitrary features
- `fuzz_hashing.zig` — Hashing with arbitrary values

## Security

See [SECURITY.md](../SECURITY.md) for security policy and vulnerability reporting.
