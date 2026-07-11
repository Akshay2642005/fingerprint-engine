# @fingerprint/sdk

[![npm version](https://img.shields.io/npm/v/@fingerprint/sdk)](https://www.npmjs.com/package/@fingerprint/sdk)

WebAssembly-accelerated browser fingerprinting SDK. Collects browser signals and computes a deterministic SHA-256 fingerprint digest.

Built with [Zig](https://ziglang.org) — zero JavaScript dependencies, ~700 KB WASM binary.

## Install

```bash
npm install @fingerprint/sdk
```

## Quick Start

```typescript
import { FingerprintEngine, FeatureID } from '@fingerprint/sdk';

// Load the WASM module
const wasm = await WebAssembly.instantiateStreaming(
  fetch('/fingerprint.wasm')  // served from your public directory
);
const engine = new FingerprintEngine(wasm.instance);
engine.init();

// Collect browser signals
engine.addBoolean(FeatureID.CookieEnabled, navigator.cookieEnabled);
engine.addString(FeatureID.UserAgent, navigator.userAgent);
engine.addString(FeatureID.Language, navigator.language);
engine.addInteger(FeatureID.HardwareConcurrency, navigator.hardwareConcurrency || 0);
engine.addInteger(FeatureID.ScreenWidth, screen.width);
engine.addInteger(FeatureID.ScreenHeight, screen.height);
// ... add more signals as needed

// Compute fingerprint digest (SHA-256)
const result = engine.compute();
console.log(result.digest);        // Uint8Array (32 bytes)
console.log(result.featureCount);  // number of features used
```

## API

### FingerprintEngine

| Method | Description |
| -------- | ------------- |
| `init()` | Initialize the fingerprint module |
| `addBoolean(id, value)` | Add a boolean feature |
| `addInteger(id, value)` | Add an integer feature (i64) |
| `addFloat(id, value)` | Add a float feature (f64) |
| `addString(id, value)` | Add a string feature (UTF-8) |
| `addBytes(id, value)` | Add a bytes feature |
| `addStringArray(id, value)` | Add a string array feature |
| `addIntegerArray(id, value)` | Add an integer array feature |
| `addFloatArray(id, value)` | Add a float array feature |
| `addBytesArray(id, value)` | Add a bytes array feature |
| `compute()` | Compute fingerprint digest |
| `reset()` | Reset all collected features |
| `clear()` | Reset and re-initialize |
| `featureCount()` | Number of features in buffer |

### FeatureID

37 browser fingerprint signals across navigator, screen, canvas, WebGL, audio, fonts, hardware, platform, storage, permissions, media, network, locale, and timezone categories.

## Development

```bash
# Build the package
cd packages/browser
npm run build

# Run examples
node examples/node-verify/verify.mjs
# Then open examples/browser-demo/index.html in a browser
```

## License

MIT
