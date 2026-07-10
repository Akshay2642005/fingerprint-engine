/**
 * Fingerprint Engine — WebAssembly bindings for browser JavaScript.
 *
 * Wraps the Zig-compiled WASM module (fingerprint.wasm) with a
 * type-safe API for collecting browser signals and computing
 * fingerprint digests.
 *
 * Usage:
 *   const wasm = await WebAssembly.instantiateStreaming(fetch('fingerprint.wasm'));
 *   const engine = new FingerprintEngine(wasm.instance);
 *   engine.addBoolean(FeatureID.CookieEnabled, true);
 *   engine.addString(FeatureID.UserAgent, navigator.userAgent);
 *   const result = engine.compute();
 *   console.log(result.digest);
 */

import { FeatureID, FeatureType, ErrorCode, type ComputeResult, type FingerprintResult } from './types';

// ── Constants ──

/** Size of the scratch buffer reserved in WASM linear memory for value serialization. */
const SCRATCH_SIZE = 4096;

/** Offset in WASM linear memory where the scratch buffer begins. */
const SCRATCH_OFFSET = 0;

/** Expected size of the SHA-256 digest output. */
const DIGEST_SIZE = 32;

// ── Engine ──

/**
 * Type-safe wrapper around the fingerprint WASM module.
 * Each instance manages one fingerprint buffer in the WASM module.
 */
export class FingerprintEngine {
  private readonly exports: WebAssembly.Exports & {
    fingerprint_init: () => number;
    fingerprint_add_feature: (id: number, type: number, ptr: number, len: number) => number;
    fingerprint_compute: () => number;
    fingerprint_get_digest_ptr: () => number;
    fingerprint_reset: () => void;
    fingerprint_feature_count: () => number;
    fingerprint_get_error: () => number;
    memory: WebAssembly.Memory;
  };
  private readonly textEncoder: TextEncoder;

  constructor(instance: WebAssembly.Instance) {
    this.exports = instance.exports as typeof this.exports;
    this.textEncoder = new TextEncoder();
  }

  /** Initializes the fingerprint module. Must be called before adding features. */
  init(): void {
    const code = this.exports.fingerprint_init();
    if (code !== ErrorCode.Success) {
      throw new Error(`fingerprint_init failed: ${this.getError()}`);
    }
  }

  /** Resets all collected features. */
  reset(): void {
    this.exports.fingerprint_reset();
  }

  /** Returns the number of features currently in the buffer. */
  featureCount(): number {
    return this.exports.fingerprint_feature_count();
  }

  /** Adds a boolean feature. */
  addBoolean(id: number, value: boolean): void {
    const data = new Uint8Array([value ? 1 : 0]);
    this.addFeature(id, FeatureType.Boolean, data);
  }

  /** Adds an integer feature (i64). */
  addInteger(id: number, value: number): void {
    const buf = new ArrayBuffer(8);
    const view = new DataView(buf);
    view.setBigInt64(0, BigInt(value), true);
    this.addFeature(id, FeatureType.Integer, new Uint8Array(buf));
  }

  /** Adds a float feature (f64). */
  addFloat(id: number, value: number): void {
    const buf = new ArrayBuffer(8);
    const view = new DataView(buf);
    view.setFloat64(0, value, true);
    this.addFeature(id, FeatureType.Float, new Uint8Array(buf));
  }

  /** Adds a string feature (UTF-8 encoded). */
  addString(id: number, value: string): void {
    const encoded = this.textEncoder.encode(value);
    this.addFeature(id, FeatureType.String, encoded);
  }

  /** Adds a raw bytes feature. */
  addBytes(id: number, value: Uint8Array): void {
    this.addFeature(id, FeatureType.Bytes, value);
  }

  /** Adds a string array feature. */
  addStringArray(id: number, value: string[]): void {
    // Flatten joined by null bytes (the WASM module just receives the raw bytes)
    const parts: Uint8Array[] = value.map(s => this.textEncoder.encode(s));
    const totalLen = parts.reduce((acc, p) => acc + p.length, 0) + parts.length;
    const buf = new Uint8Array(totalLen);
    let offset = 0;
    for (const part of parts) {
      buf.set(part, offset);
      offset += part.length;
      buf[offset] = 0; // null separator
      offset += 1;
    }
    this.addFeature(id, FeatureType.StringArray, buf);
  }

  /** Adds an integer array feature. */
  addIntegerArray(id: number, value: number[]): void {
    const buf = new ArrayBuffer(value.length * 8);
    const view = new DataView(buf);
    for (let i = 0; i < value.length; i++) {
      view.setBigInt64(i * 8, BigInt(value[i]), true);
    }
    this.addFeature(id, FeatureType.IntegerArray, new Uint8Array(buf));
  }

  /** Adds a float array feature. */
  addFloatArray(id: number, value: number[]): void {
    const buf = new ArrayBuffer(value.length * 8);
    const view = new DataView(buf);
    for (let i = 0; i < value.length; i++) {
      view.setFloat64(i * 8, value[i], true);
    }
    this.addFeature(id, FeatureType.FloatArray, new Uint8Array(buf));
  }

  /** Adds a bytes array feature. */
  addBytesArray(id: number, value: Uint8Array[]): void {
    const totalLen = value.reduce((acc, b) => acc + b.length, 0) + value.length;
    const buf = new Uint8Array(totalLen);
    let offset = 0;
    for (const part of value) {
      buf.set(part, offset);
      offset += part.length;
      buf[offset] = 0; // null separator
      offset += 1;
    }
    this.addFeature(id, FeatureType.BytesArray, buf);
  }

  /**
   * Computes the fingerprint digest from all added features.
   * Features are automatically sorted by FeatureID for deterministic output.
   */
  compute(): ComputeResult {
    const ptr = this.exports.fingerprint_compute();
    if (ptr === 0) {
      throw new Error(`fingerprint_compute failed: ${this.getError()}`);
    }
    const memory = this.exports.memory.buffer;
    const digest = new Uint8Array(memory.slice(ptr, ptr + DIGEST_SIZE));
    return {
      digest: digest as ComputeResult['digest'],
      featureCount: this.featureCount(),
    };
  }

  /** Clears the buffer and re-initializes. */
  clear(): void {
    this.exports.fingerprint_reset();
    this.exports.fingerprint_init();
  }

  // ── Private ──

  /**
   * Writes raw bytes into WASM linear memory and calls the add_feature export.
   */
  private addFeature(id: number, type: FeatureType, data: Uint8Array): void {
    const memory = this.exports.memory;

    // Grow memory if needed
    const needed = SCRATCH_OFFSET + data.length;
    const pagesNeeded = Math.ceil(needed / 65536);
    const currentPages = memory.buffer.byteLength / 65536;
    if (pagesNeeded > currentPages) {
      memory.grow(pagesNeeded - currentPages);
    }

    // Write data into scratch buffer
    const view = new Uint8Array(memory.buffer);
    view.set(data, SCRATCH_OFFSET);

    const code = this.exports.fingerprint_add_feature(
      id,
      type,
      SCRATCH_OFFSET,
      data.length,
    );

    if (code !== ErrorCode.Success) {
      throw new Error(`fingerprint_add_feature failed: ${this.getError()} (code=${code})`);
    }
  }

  /** Reads the error string from WASM linear memory. */
  private getError(): string {
    const ptr = this.exports.fingerprint_get_error();
    if (ptr === 0) return '';
    const memory = this.exports.memory.buffer;
    const view = new Uint8Array(memory);
    let end = ptr;
    while (end < view.length && view[end] !== 0) {
      end++;
    }
    return new TextDecoder().decode(view.slice(ptr, end));
  }
}
