/**
 * Fingerprint Engine — Browser SDK bindings.
 *
 * @packageDocumentation
 */

export { FingerprintEngine } from './engine';
export {
  FeatureID,
  FeatureType,
  ErrorCode,
} from './types';
export type {
  FeatureValue,
  Feature,
  FingerprintDigest,
  FingerprintResult,
  ComputeResult,
} from './types';

// Processing API result types
export interface NormalizeResult {
  /** Number of type warnings */
  typeWarnings: number;
  /** Number of bound warnings */
  boundWarnings: number;
  /** Total warnings */
  total: number;
}

export interface RiskResult {
  /** Risk score 0-100 */
  score: number;
  /** Risk label */
  label: 'low' | 'medium' | 'high';
}

export interface EntropyResult {
  /** Entropy score 0-800 (8.0 bits/byte * 100) */
  score: number;
  /** Entropy in bits per byte */
  bitsPerByte: number;
}
