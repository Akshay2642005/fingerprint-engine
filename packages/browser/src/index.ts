/**
 * @fingerprint/sdk — Fingerprint Engine Browser SDK
 *
 * Provides WebAssembly-accelerated browser fingerprinting with a
 * type-safe API for collecting and computing fingerprint digests.
 *
 * ## Quick Start
 *
 * ```typescript
 * import { FingerprintEngine, FeatureID } from '@fingerprint/sdk';
 *
 * const wasm = await WebAssembly.instantiateStreaming(
 *   fetch('/fingerprint.wasm')
 * );
 * const engine = new FingerprintEngine(wasm.instance);
 * engine.init();
 *
 * engine.addBoolean(FeatureID.CookieEnabled, navigator.cookieEnabled);
 * engine.addString(FeatureID.UserAgent, navigator.userAgent);
 *
 * const result = engine.compute();
 * console.log(result.digest); // Uint8Array (32 bytes)
 * ```
 *
 * @packageDocumentation
 */

export { FingerprintEngine } from './engine';
export { FeatureID, FeatureType, ErrorCode } from './types';
export type {
  FeatureValue,
  Feature,
  FingerprintDigest,
  FingerprintResult,
  ComputeResult,
} from './types';
