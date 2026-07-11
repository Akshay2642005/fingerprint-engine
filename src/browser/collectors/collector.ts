/**
 * High-level browser signal collector.
 * Gathers all available browser signals and feeds them to the WASM engine.
 * This is the main entry point for collecting browser fingerprints.
 */

import type { FingerprintEngine } from '../bindings/engine';
import { FeatureID, type ComputeResult } from '../bindings/types';
import { collectCanvasFingerprint } from './canvas';
import { collectWebGLInfo } from './webgl';
import { collectAudioFingerprint } from './audio';
import { collectFonts } from './fonts';
import { collectBattery } from './battery';
import { collectMediaInfo } from './media';
import { collectSpeechVoices } from './speech';
import { detectKeyboardLayout, collectPointerInfo, collectGamepadInfo, hasSharedWorker } from './input';
import { collectPermissions } from './permissions';

export interface CollectorOptions {
  /** Enable canvas fingerprinting (default: true) */
  enableCanvas?: boolean;
  /** Enable WebGL fingerprinting (default: true) */
  enableWebGL?: boolean;
  /** Enable audio fingerprinting (default: true) */
  enableAudio?: boolean;
  /** Enable font detection (default: true) */
  enableFonts?: boolean;
  /** Enable battery API (default: true) */
  enableBattery?: boolean;
  /** Enable media codec detection (default: true) */
  enableMedia?: boolean;
  /** Enable speech synthesis voices (default: true) */
  enableSpeech?: boolean;
  /** Enable input detection (default: true) */
  enableInput?: boolean;
  /** Enable permissions API (default: true) */
  enablePermissions?: boolean;
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
  engine: FingerprintEngine,
  options: CollectorOptions = {},
): Promise<CollectedSignals> {
  const {
    enableCanvas = true,
    enableWebGL = true,
    enableAudio = true,
    enableFonts = true,
    enableBattery = true,
    enableMedia = true,
    enableSpeech = true,
    enableInput = true,
    enablePermissions = true,
  } = options;

  const collectedFeatures: FeatureID[] = [];

  // ── Navigator signals (always collected) ──
  collectNavigatorSignals(engine, collectedFeatures);

  // ── Screen signals (always collected) ──
  collectScreenSignals(engine, collectedFeatures);

  // ── Locale & timezone ──
  collectLocaleSignals(engine, collectedFeatures);

  // ── Storage availability ──
  collectStorageSignals(engine, collectedFeatures);

  // ── Network info ──
  collectNetworkSignals(engine, collectedFeatures);

  // ── Crypto support ──
  engine.addBoolean(FeatureID.CryptoSupport, 'crypto' in window);
  engine.addBoolean(FeatureID.SubtleCrypto, 'subtle' in (window.crypto || {}));
  collectedFeatures.push(FeatureID.CryptoSupport, FeatureID.SubtleCrypto);

  // ── CSS features ──
  engine.addBoolean(FeatureID.CSSCustomProperties, CSS.supports('color', '--test: red'));
  engine.addBoolean(FeatureID.CSSGridSupport, CSS.supports('display', 'grid'));
  engine.addBoolean(FeatureID.CSSFlexboxSupport, CSS.supports('display', 'flex'));
  engine.addBoolean(FeatureID.CSSContainerQuery, CSS.supports('container-type', 'inline-size'));
  engine.addBoolean(FeatureID.CSSHasSelector, CSS.supports('selector(:has(*))'));
  collectedFeatures.push(
    FeatureID.CSSCustomProperties, FeatureID.CSSGridSupport,
    FeatureID.CSSFlexboxSupport, FeatureID.CSSContainerQuery,
    FeatureID.CSSHasSelector,
  );

  // ── Browser features ──
  engine.addBoolean(FeatureID.ServiceWorkerSupport, 'serviceWorker' in navigator);
  engine.addBoolean(FeatureID.WebWorkerSupport, 'Worker' in window);
  engine.addBoolean(FeatureID.SharedWorkerSupport, hasSharedWorker());
  engine.addBoolean(FeatureID.WebSocketSupport, 'WebSocket' in window);
  engine.addBoolean(FeatureID.WebRTCSupport, 'RTCPeerConnection' in window);
  collectedFeatures.push(
    FeatureID.ServiceWorkerSupport, FeatureID.WebWorkerSupport,
    FeatureID.SharedWorkerSupport, FeatureID.WebSocketSupport,
    FeatureID.WebRTCSupport,
  );

  // ── Permissions ──
  if (enablePermissions) {
    const perms = await collectPermissions();
    engine.addString(FeatureID.NotificationPermission, perms.notifications);
    engine.addString(FeatureID.GeolocationPermission, perms.geolocation);
    engine.addString(FeatureID.CameraPermission, perms.camera);
    engine.addString(FeatureID.MicrophonePermission, perms.microphone);
    collectedFeatures.push(
      FeatureID.NotificationPermission, FeatureID.GeolocationPermission,
      FeatureID.CameraPermission, FeatureID.MicrophonePermission,
    );
  }

  // ── Canvas fingerprinting ──
  if (enableCanvas) {
    const canvasData = collectCanvasFingerprint();
    if (canvasData) {
      engine.addBytes(FeatureID.CanvasHash, canvasData);
      collectedFeatures.push(FeatureID.CanvasHash);
    }
  }

  // ── WebGL fingerprinting ──
  if (enableWebGL) {
    const webglInfo = collectWebGLInfo();
    if (webglInfo) {
      engine.addString(FeatureID.WebGLVendor, webglInfo.vendor);
      engine.addString(FeatureID.WebGLRenderer, webglInfo.renderer);
      engine.addString(FeatureID.WebGLVersion, webglInfo.version);
      engine.addStringArray(FeatureID.WebGLExtensions, webglInfo.extensions);

      // Build parameters JSON
      const params = JSON.stringify({
        maxTextureSize: webglInfo.maxTextureSize,
        maxViewportDims: webglInfo.maxViewportDims,
        maxCombinedTextureUnits: webglInfo.maxCombinedTextureUnits,
      });
      engine.addString(FeatureID.WebGLParameters, params);

      collectedFeatures.push(
        FeatureID.WebGLVendor, FeatureID.WebGLRenderer,
        FeatureID.WebGLVersion, FeatureID.WebGLExtensions,
        FeatureID.WebGLParameters,
      );
    }
  }

  // ── Audio fingerprinting ──
  if (enableAudio) {
    const audioData = await collectAudioFingerprint();
    if (audioData) {
      engine.addBytes(FeatureID.AudioHash, audioData);
      collectedFeatures.push(FeatureID.AudioHash);
    }
  }

  // ── Font detection ──
  if (enableFonts) {
    const fonts = collectFonts();
    if (fonts.length > 0) {
      engine.addStringArray(FeatureID.FontsHash, fonts.map(f => f));
      collectedFeatures.push(FeatureID.FontsHash);
    }
  }

  // ── Battery ──
  if (enableBattery) {
    const battery = await collectBattery();
    if (battery) {
      engine.addFloat(FeatureID.BatteryLevel, battery.level);
      engine.addBoolean(FeatureID.BatteryCharging, battery.charging);
      engine.addInteger(FeatureID.BatteryChargingTime, battery.chargingTime);
      collectedFeatures.push(FeatureID.BatteryLevel, FeatureID.BatteryCharging, FeatureID.BatteryChargingTime);
    }
  }

  // ── Media codecs ──
  if (enableMedia) {
    const media = collectMediaInfo();
    engine.addStringArray(FeatureID.SupportedCodecs, [...media.videoCodecs, ...media.audioCodecs]);
    engine.addStringArray(FeatureID.MediaFormats, media.mediaFormats);
    engine.addStringArray(FeatureID.AudioFormats, media.audioFormats);
    engine.addBoolean(FeatureID.HDRSupport, media.hdrSupport);
    collectedFeatures.push(
      FeatureID.SupportedCodecs, FeatureID.MediaFormats,
      FeatureID.AudioFormats, FeatureID.HDRSupport,
    );
  }

  // ── Speech synthesis ──
  if (enableSpeech) {
    const voices = collectSpeechVoices();
    if (voices.length > 0) {
      engine.addStringArray(FeatureID.SpeechSynthesisVoices, voices);
      collectedFeatures.push(FeatureID.SpeechSynthesisVoices);
    }
  }

  // ── Input detection ──
  if (enableInput) {
    const keyboard = detectKeyboardLayout();
    engine.addString(FeatureID.KeyboardLayout, keyboard);

    const pointer = collectPointerInfo();
    engine.addBoolean(FeatureID.PointerEvents, pointer.supported);

    const gamepad = collectGamepadInfo();
    engine.addBoolean(FeatureID.GamepadSupport, gamepad);

    collectedFeatures.push(FeatureID.KeyboardLayout, FeatureID.PointerEvents, FeatureID.GamepadSupport);
  }

  // ── Metadata ──
  engine.addInteger(FeatureID.SchemaVersion, 1);
  engine.addString(FeatureID.SDKVersion, '0.1.0');
  engine.addInteger(FeatureID.CollectionTimestamp, Date.now());
  collectedFeatures.push(FeatureID.SchemaVersion, FeatureID.SDKVersion, FeatureID.CollectionTimestamp);

  // ── Compute ──
  const result = engine.compute();
  const hex = Array.from(result.digest).map(b => b.toString(16).padStart(2, '0')).join('');

  return {
    signalCount: collectedFeatures.length,
    result,
    hex,
    collectedAt: Date.now(),
    collectedFeatures,
  };
}

// ── Private collectors ──

function collectNavigatorSignals(engine: FingerprintEngine, features: FeatureID[]): void {
  engine.addString(FeatureID.UserAgent, navigator.userAgent);
  engine.addString(FeatureID.Language, navigator.language);
  engine.addStringArray(FeatureID.Languages, Array.from(navigator.languages));
  engine.addString(FeatureID.Platform, navigator.platform);
  engine.addString(FeatureID.Vendor, navigator.vendor);
  engine.addString(FeatureID.Product, navigator.product);
  engine.addString(FeatureID.ProductSub, (navigator as any).productSub || '');
  engine.addString(FeatureID.AppName, navigator.appName);
  engine.addString(FeatureID.AppVersion, navigator.appVersion);
  engine.addBoolean(FeatureID.CookieEnabled, navigator.cookieEnabled);
  engine.addString(FeatureID.DoNotTrack, navigator.doNotTrack || 'unspecified');
  engine.addInteger(FeatureID.HardwareConcurrency, navigator.hardwareConcurrency);
  engine.addInteger(FeatureID.MaxTouchPoints, navigator.maxTouchPoints);

  const nav = navigator as any;
  if (nav.deviceMemory) engine.addFloat(FeatureID.DeviceMemory, nav.deviceMemory);
  if (nav.pdfViewerEnabled !== undefined) engine.addBoolean(FeatureID.PdfViewerEnabled, nav.pdfViewerEnabled);
  if (nav.vendorSub) engine.addString(FeatureID.VendorSub, nav.vendorSub);
  if (nav.deviceMemory) engine.addInteger(FeatureID.DeviceRam, Math.round(nav.deviceMemory));

  features.push(
    FeatureID.UserAgent, FeatureID.Language, FeatureID.Languages,
    FeatureID.Platform, FeatureID.Vendor, FeatureID.Product,
    FeatureID.ProductSub, FeatureID.AppName, FeatureID.AppVersion,
    FeatureID.CookieEnabled, FeatureID.DoNotTrack,
    FeatureID.HardwareConcurrency, FeatureID.MaxTouchPoints,
  );
}

function collectScreenSignals(engine: FingerprintEngine, features: FeatureID[]): void {
  engine.addInteger(FeatureID.ScreenWidth, screen.width);
  engine.addInteger(FeatureID.ScreenHeight, screen.height);
  engine.addInteger(FeatureID.AvailableWidth, screen.availWidth);
  engine.addInteger(FeatureID.AvailableHeight, screen.availHeight);
  engine.addInteger(FeatureID.ColorDepth, screen.colorDepth);
  engine.addInteger(FeatureID.PixelDepth, screen.pixelDepth);
  engine.addFloat(FeatureID.DevicePixelRatio, window.devicePixelRatio);
  engine.addInteger(FeatureID.InnerWidth, window.innerWidth);
  engine.addInteger(FeatureID.InnerHeight, window.innerHeight);
  engine.addInteger(FeatureID.OuterWidth, window.outerWidth);
  engine.addInteger(FeatureID.OuterHeight, window.outerHeight);

  if (screen.orientation) {
    engine.addString(FeatureID.ScreenOrientation, screen.orientation.type);
  }

  features.push(
    FeatureID.ScreenWidth, FeatureID.ScreenHeight,
    FeatureID.AvailableWidth, FeatureID.AvailableHeight,
    FeatureID.ColorDepth, FeatureID.PixelDepth,
    FeatureID.DevicePixelRatio, FeatureID.InnerWidth, FeatureID.InnerHeight,
    FeatureID.OuterWidth, FeatureID.OuterHeight,
  );
}

function collectLocaleSignals(engine: FingerprintEngine, features: FeatureID[]): void {
  engine.addString(FeatureID.Locale, navigator.language);
  engine.addString(FeatureID.Timezone, Intl.DateTimeFormat().resolvedOptions().timeZone);
  engine.addInteger(FeatureID.TimezoneOffset, new Date().getTimezoneOffset());
  engine.addString(FeatureID.DateTimeFormat, new Intl.DateTimeFormat().resolvedOptions().locale);

  features.push(FeatureID.Locale, FeatureID.Timezone, FeatureID.TimezoneOffset, FeatureID.DateTimeFormat);
}

function collectStorageSignals(engine: FingerprintEngine, features: FeatureID[]): void {
  engine.addBoolean(FeatureID.LocalStorage, isStorageAvailable('localStorage'));
  engine.addBoolean(FeatureID.SessionStorage, isStorageAvailable('sessionStorage'));
  engine.addBoolean(FeatureID.IndexedDB, 'indexedDB' in window);
  engine.addBoolean(FeatureID.CacheStorage, 'caches' in window);
  engine.addBoolean(FeatureID.CookiesEnabled, navigator.cookieEnabled);

  features.push(
    FeatureID.LocalStorage, FeatureID.SessionStorage,
    FeatureID.IndexedDB, FeatureID.CacheStorage, FeatureID.CookiesEnabled,
  );
}

function collectNetworkSignals(engine: FingerprintEngine, features: FeatureID[]): void {
  const conn = (navigator as any).connection;
  if (conn) {
    engine.addString(FeatureID.ConnectionType, conn.type || 'unknown');
    engine.addFloat(FeatureID.ConnectionDownlink, conn.downlink || 0);
    engine.addString(FeatureID.ConnectionEffectiveType, conn.effectiveType || 'unknown');
    engine.addInteger(FeatureID.ConnectionRtt, conn.rtt || 0);
    engine.addBoolean(FeatureID.ConnectionSaveData, conn.saveData || false);

    features.push(
      FeatureID.ConnectionType, FeatureID.ConnectionDownlink,
      FeatureID.ConnectionEffectiveType, FeatureID.ConnectionRtt,
      FeatureID.ConnectionSaveData,
    );
  }
}

function isStorageAvailable(type: 'localStorage' | 'sessionStorage'): boolean {
  try {
    const storage = window[type];
    const testKey = '__fp_test__';
    storage.setItem(testKey, '1');
    storage.removeItem(testKey);
    return true;
  } catch {
    return false;
  }
}
