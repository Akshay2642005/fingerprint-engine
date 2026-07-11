/**
 * High-level browser signal collector.
 * Gathers all available browser signals and prepares them for fingerprinting.
 * This is the main entry point for collecting browser fingerprints.
 */

import { FingerprintEngine } from '../bindings/engine';
import { FeatureID, type ComputeResult } from '../bindings/types';
import { collectCanvasFingerprint, getCanvasCapabilities } from './canvas';
import { collectWebGLInfo } from './webgl';
import { collectAudioFingerprint } from './audio';

export interface CollectorOptions {
  /** Enable canvas fingerprinting (default: true) */
  enableCanvas?: boolean;
  /** Enable WebGL fingerprinting (default: true) */
  enableWebGL?: boolean;
  /** Enable audio fingerprinting (default: true) */
  enableAudio?: boolean;
  /** Enable standard navigator signals (default: true) */
  enableNavigator?: boolean;
  /** Enable screen signals (default: true) */
  enableScreen?: boolean;
}

export interface CollectedSignals {
  /** Number of signals collected */
  signalCount: number;
  /** Compute result from the engine */
  result: ComputeResult;
  /** Fingerprint hex digest */
  hex: string;
  /** Collection timestamp */
  collectedAt: number;
  /** List of feature IDs that were collected */
  collectedFeatures: FeatureID[];
}

/**
 * Collect all available browser signals and compute the fingerprint.
 */
export async function collectFingerprint(
  wasmInstance: WebAssembly.Instance,
  options: CollectorOptions = {}
): Promise<CollectedSignals> {
  const {
    enableCanvas = true,
    enableWebGL = true,
    enableAudio = true,
    enableNavigator = true,
    enableScreen = true,
  } = options;

  const engine = new FingerprintEngine(wasmInstance);
  engine.init();
  const collectedFeatures: FeatureID[] = [];

  // Standard navigator signals
  if (enableNavigator) {
    collectNavigatorSignals(engine, collectedFeatures);
  }

  // Screen signals
  if (enableScreen) {
    collectScreenSignals(engine, collectedFeatures);
  }

  // Canvas fingerprinting
  if (enableCanvas) {
    const canvasData = collectCanvasFingerprint();
    if (canvasData) {
      engine.addBytes(FeatureID.CanvasFingerprint, canvasData);
      collectedFeatures.push(FeatureID.CanvasFingerprint);
    }

    const canvasCaps = getCanvasCapabilities();
    if (canvasCaps.length > 0) {
      engine.addStringArray(FeatureID.Platform, canvasCaps);
    }
  }

  // WebGL fingerprinting
  if (enableWebGL) {
    const webglInfo = collectWebGLInfo();
    if (webglInfo) {
      engine.addString(FeatureID.WebGLVendor, webglInfo.vendor);
      engine.addString(FeatureID.WebGLRenderer, webglInfo.renderer);
      collectedFeatures.push(FeatureID.WebGLVendor, FeatureID.WebGLRenderer);
    }
  }

  // Audio fingerprinting
  if (enableAudio) {
    const audioData = await collectAudioFingerprint();
    if (audioData) {
      engine.addBytes(FeatureID.AudioFingerprint, audioData);
      collectedFeatures.push(FeatureID.AudioFingerprint);
    }
  }

  // Compute the fingerprint
  const result = engine.compute();

  // Convert digest to hex string
  const hex = Array.from(result.digest)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');

  return {
    signalCount: collectedFeatures.length,
    result,
    hex,
    collectedAt: Date.now(),
    collectedFeatures,
  };
}

/**
 * Collect standard navigator signals.
 */
function collectNavigatorSignals(
  engine: FingerprintEngine,
  collected: FeatureID[]
): void {
  // User Agent
  if (navigator.userAgent) {
    engine.addString(FeatureID.UserAgent, navigator.userAgent);
    collected.push(FeatureID.UserAgent);
  }

  // Language
  if (navigator.language) {
    engine.addString(FeatureID.Language, navigator.language);
    collected.push(FeatureID.Language);
  }

  // Platform
  if (navigator.platform) {
    engine.addString(FeatureID.Platform, navigator.platform);
    collected.push(FeatureID.Platform);
  }

  // Hardware Concurrency
  if (navigator.hardwareConcurrency) {
    engine.addInteger(FeatureID.HardwareConcurrency, navigator.hardwareConcurrency);
    collected.push(FeatureID.HardwareConcurrency);
  }

  // Device Memory (Chrome only)
  const nav = navigator as Navigator & { deviceMemory?: number };
  if (nav.deviceMemory) {
    engine.addInteger(FeatureID.DeviceMemory, nav.deviceMemory);
    collected.push(FeatureID.DeviceMemory);
  }

  // Cookie Enabled
  engine.addBoolean(FeatureID.CookieEnabled, navigator.cookieEnabled);
  collected.push(FeatureID.CookieEnabled);

  // Do Not Track
  if (navigator.doNotTrack) {
    engine.addString(FeatureID.DoNotTrack, navigator.doNotTrack);
    collected.push(FeatureID.DoNotTrack);
  }

  // Timezone
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  if (timezone) {
    engine.addString(FeatureID.Timezone, timezone);
    collected.push(FeatureID.Timezone);
  }

  // Timezone Offset
  const timezoneOffset = new Date().getTimezoneOffset();
  engine.addInteger(FeatureID.TimezoneOffset, timezoneOffset);
  collected.push(FeatureID.TimezoneOffset);
}

/**
 * Collect screen and display signals.
 */
function collectScreenSignals(
  engine: FingerprintEngine,
  collected: FeatureID[]
): void {
  // Screen dimensions
  engine.addInteger(FeatureID.ScreenWidth, screen.width);
  engine.addInteger(FeatureID.ScreenHeight, screen.height);
  collected.push(FeatureID.ScreenWidth, FeatureID.ScreenHeight);

  // Available screen (excluding taskbar/dock)
  engine.addInteger(FeatureID.ScreenAvailWidth, screen.availWidth);
  engine.addInteger(FeatureID.ScreenAvailHeight, screen.availHeight);
  collected.push(FeatureID.ScreenAvailWidth, FeatureID.ScreenAvailHeight);

  // Color depth
  engine.addInteger(FeatureID.ScreenColorDepth, screen.colorDepth);
  collected.push(FeatureID.ScreenColorDepth);

  // Pixel depth
  engine.addInteger(FeatureID.ScreenPixelDepth, screen.pixelDepth);
  collected.push(FeatureID.ScreenPixelDepth);

  // Device pixel ratio
  engine.addFloat(FeatureID.ScreenDevicePixelRatio, window.devicePixelRatio);
  collected.push(FeatureID.ScreenDevicePixelRatio);
}
