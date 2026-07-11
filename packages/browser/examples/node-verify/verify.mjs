/**
 * Node.js Fingerprint Verification Example
 *
 * Loads the WASM module, collects representative signals,
 * computes a fingerprint digest, and prints the result.
 *
 * Usage:
 *   node verify.mjs <path/to/fingerprint.wasm>
 *
 * If no path is given, expects the WASM at ../../dist/fingerprint.wasm
 * relative to the package root.
 */

import { readFile } from 'fs/promises';
import { resolve } from 'path';
import { fileURLToPath } from 'url';

const __dirname = fileURLToPath(new URL('.', import.meta.url));

// In a real app you'd do: import { FingerprintEngine, FeatureID } from '@fingerprint/sdk';
// For this demo we import from the source directly.
import { FingerprintEngine, FeatureID } from '../../dist/index.js';

async function main() {
  // Resolve WASM path
  const wasmPath = process.argv[2]
    ? resolve(process.argv[2])
    : resolve(__dirname, '..', '..', 'dist', 'fingerprint.wasm');

  console.log(`Loading WASM from: ${wasmPath}`);
  console.log();

  // Load and instantiate WASM
  const wasmBuffer = await readFile(wasmPath);
  const { instance } = await WebAssembly.instantiate(wasmBuffer);
  const engine = new FingerprintEngine(instance);

  // Initialize
  engine.init();

  // Simulate browser signals
  const signals = {
    [FeatureID.CookieEnabled]: true,
    [FeatureID.UserAgent]: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) FingerprintEngine/0.1.0',
    [FeatureID.Language]: 'en-US',
    [FeatureID.Platform]: 'Win32',
    [FeatureID.HardwareConcurrency]: 8,
    [FeatureID.DeviceMemory]: 8,
    [FeatureID.ScreenWidth]: 1920,
    [FeatureID.ScreenHeight]: 1080,
    [FeatureID.ScreenColorDepth]: 24,
    [FeatureID.ScreenDevicePixelRatio]: 1.0,
    [FeatureID.Timezone]: 'America/New_York',
    [FeatureID.TimezoneOffset]: 300,
  };

  engine.addBoolean(FeatureID.CookieEnabled, true);
  engine.addString(FeatureID.UserAgent, signals[FeatureID.UserAgent]);
  engine.addString(FeatureID.Language, signals[FeatureID.Language]);
  engine.addString(FeatureID.Platform, signals[FeatureID.Platform]);
  engine.addInteger(FeatureID.HardwareConcurrency, signals[FeatureID.HardwareConcurrency]);
  engine.addInteger(FeatureID.DeviceMemory, signals[FeatureID.DeviceMemory]);
  engine.addInteger(FeatureID.ScreenWidth, signals[FeatureID.ScreenWidth]);
  engine.addInteger(FeatureID.ScreenHeight, signals[FeatureID.ScreenHeight]);
  engine.addInteger(FeatureID.ScreenColorDepth, signals[FeatureID.ScreenColorDepth]);
  engine.addFloat(FeatureID.ScreenDevicePixelRatio, signals[FeatureID.ScreenDevicePixelRatio]);
  engine.addString(FeatureID.Timezone, signals[FeatureID.Timezone]);
  engine.addInteger(FeatureID.TimezoneOffset, signals[FeatureID.TimezoneOffset]);

  // Compute
  const result = engine.compute();
  const hex = Array.from(result.digest)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');

  console.log('Collected signals:', Object.keys(signals).length);
  console.log('Fingerprint digest:', hex);
  console.log('Feature count:', result.featureCount);
  console.log();
  console.log('✓ Verification complete');
}

main().catch(err => {
  console.error('✗ Error:', err.message);
  process.exit(1);
});
