/**
 * High-level signal orchestration (D14).
 *
 * Gathers all available browser signals and returns them as a plain
 * `Signal[]` — no WASM engine, no stateful buffer. The array feeds
 * package.ts, which serializes the SignalPackage v2 body for the ingress.
 * The canonical fingerprint is computed server-side by the workers.
 */

import type { CollectOptions, Signal } from "../types.js";
import { FeatureID, FeatureType } from "../generated/tables.js";
import { collectCanvasFingerprint } from "./canvas.js";
import { collectWebGLInfo } from "./webgl.js";
import { collectAudioFingerprint } from "./audio.js";
import { collectFonts } from "./fonts.js";
import { collectBattery } from "./battery.js";
import { collectMediaInfo } from "./media.js";
import { collectSpeechVoices } from "./speech.js";
import {
	detectKeyboardLayout,
	collectPointerInfo,
	collectGamepadInfo,
	hasSharedWorker,
} from "./input.js";
import { collectPermissions } from "./permissions.js";

/**
 * Collect all available browser signals into a plain Signal[].
 * The order of signals is deterministic; value collection may be async.
 */
export async function collectSignals(
	options: CollectOptions = {},
): Promise<Signal[]> {
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

	const signals: Signal[] = [];

	// ── Navigator (always collected) ──
	collectNavigatorSignals(signals);

	// ── Screen (always collected) ──
	collectScreenSignals(signals);

	// ── Locale & timezone ──
	collectLocaleSignals(signals);

	// ── Storage availability ──
	collectStorageSignals(signals);

	// ── Network info ──
	collectNetworkSignals(signals);

	// ── Crypto support ──
	signals.push(
		{ id: FeatureID.CryptoSupport, type: FeatureType.Boolean, value: "crypto" in window },
		{ id: FeatureID.SubtleCrypto, type: FeatureType.Boolean, value: "subtle" in (window.crypto || {}) },
	);

	// ── CSS features ──
	signals.push(
		{ id: FeatureID.CSSCustomProperties, type: FeatureType.Boolean, value: cssSupports("color", "--test: red") },
		{ id: FeatureID.CSSGridSupport, type: FeatureType.Boolean, value: cssSupports("display", "grid") },
		{ id: FeatureID.CSSFlexboxSupport, type: FeatureType.Boolean, value: cssSupports("display", "flex") },
		{ id: FeatureID.CSSContainerQuery, type: FeatureType.Boolean, value: cssSupports("container-type", "inline-size") },
		{ id: FeatureID.CSSHasSelector, type: FeatureType.Boolean, value: cssSupports("selector(:has(*))") },
	);

	// ── Browser features ──
	signals.push(
		{ id: FeatureID.ServiceWorkerSupport, type: FeatureType.Boolean, value: "serviceWorker" in navigator },
		{ id: FeatureID.WebWorkerSupport, type: FeatureType.Boolean, value: "Worker" in window },
		{ id: FeatureID.SharedWorkerSupport, type: FeatureType.Boolean, value: hasSharedWorker() },
		{ id: FeatureID.WebSocketSupport, type: FeatureType.Boolean, value: "WebSocket" in window },
		{ id: FeatureID.WebRTCSupport, type: FeatureType.Boolean, value: "RTCPeerConnection" in window },
	);

	// ── Permissions ──
	if (enablePermissions) {
		const perms = await collectPermissions();
		signals.push(
			{ id: FeatureID.NotificationPermission, type: FeatureType.String, value: perms.notifications },
			{ id: FeatureID.GeolocationPermission, type: FeatureType.String, value: perms.geolocation },
			{ id: FeatureID.CameraPermission, type: FeatureType.String, value: perms.camera },
			{ id: FeatureID.MicrophonePermission, type: FeatureType.String, value: perms.microphone },
		);
	}

	// ── Canvas ──
	if (enableCanvas) {
		const canvasData = collectCanvasFingerprint();
		if (canvasData) {
			signals.push({ id: FeatureID.CanvasHash, type: FeatureType.Bytes, value: canvasData });
		}
	}

	// ── WebGL ──
	if (enableWebGL) {
		const webglInfo = collectWebGLInfo();
		if (webglInfo) {
			const params = JSON.stringify({
				maxTextureSize: webglInfo.maxTextureSize,
				maxViewportDims: webglInfo.maxViewportDims,
				maxCombinedTextureUnits: webglInfo.maxCombinedTextureUnits,
			});
			signals.push(
				{ id: FeatureID.WebGLVendor, type: FeatureType.String, value: webglInfo.vendor },
				{ id: FeatureID.WebGLRenderer, type: FeatureType.String, value: webglInfo.renderer },
				{ id: FeatureID.WebGLVersion, type: FeatureType.String, value: webglInfo.version },
				{ id: FeatureID.WebGLExtensions, type: FeatureType.StringArray, value: webglInfo.extensions },
				{ id: FeatureID.WebGLParameters, type: FeatureType.String, value: params },
			);
		}
	}

	// ── Audio ──
	if (enableAudio) {
		const audioData = await collectAudioFingerprint();
		if (audioData) {
			signals.push({ id: FeatureID.AudioHash, type: FeatureType.Bytes, value: audioData });
		}
	}

	// ── Fonts ──
	if (enableFonts) {
		const fonts = collectFonts();
		if (fonts.length > 0) {
			signals.push({ id: FeatureID.FontsHash, type: FeatureType.StringArray, value: fonts });
		}
	}

	// ── Battery ──
	if (enableBattery) {
		const battery = await collectBattery();
		if (battery) {
			signals.push(
				{ id: FeatureID.BatteryLevel, type: FeatureType.Float, value: battery.level },
				{ id: FeatureID.BatteryCharging, type: FeatureType.Boolean, value: battery.charging },
				{ id: FeatureID.BatteryChargingTime, type: FeatureType.Integer, value: battery.chargingTime },
			);
		}
	}

	// ── Media codecs ──
	if (enableMedia) {
		const media = collectMediaInfo();
		signals.push(
			{ id: FeatureID.SupportedCodecs, type: FeatureType.StringArray, value: [...media.videoCodecs, ...media.audioCodecs] },
			{ id: FeatureID.MediaFormats, type: FeatureType.StringArray, value: media.mediaFormats },
			{ id: FeatureID.AudioFormats, type: FeatureType.StringArray, value: media.audioFormats },
			{ id: FeatureID.HDRSupport, type: FeatureType.Boolean, value: media.hdrSupport },
		);
	}

	// ── Speech synthesis ──
	if (enableSpeech) {
		const voices = collectSpeechVoices();
		if (voices.length > 0) {
			signals.push({ id: FeatureID.SpeechSynthesisVoices, type: FeatureType.StringArray, value: voices });
		}
	}

	// ── Input detection ──
	if (enableInput) {
		signals.push(
			{ id: FeatureID.KeyboardLayout, type: FeatureType.String, value: detectKeyboardLayout() },
			{ id: FeatureID.PointerEvents, type: FeatureType.Boolean, value: collectPointerInfo().supported },
			{ id: FeatureID.GamepadSupport, type: FeatureType.Boolean, value: collectGamepadInfo() },
		);
	}

	return signals;
}

/** CSS.supports wrapper that never throws. */
function cssSupports(property: string, value?: string): boolean {
	try {
		return value === undefined ? CSS.supports(property) : CSS.supports(property, value);
	} catch {
		return false;
	}
}

// ── Signal groups ──

function collectNavigatorSignals(signals: Signal[]): void {
	const nav = navigator as unknown as Record<string, unknown>;
	signals.push(
		{ id: FeatureID.UserAgent, type: FeatureType.String, value: navigator.userAgent },
		{ id: FeatureID.Language, type: FeatureType.String, value: navigator.language },
		{ id: FeatureID.Languages, type: FeatureType.StringArray, value: Array.from(navigator.languages) },
		{ id: FeatureID.Platform, type: FeatureType.String, value: navigator.platform },
		{ id: FeatureID.Vendor, type: FeatureType.String, value: navigator.vendor },
		{ id: FeatureID.Product, type: FeatureType.String, value: navigator.product },
		{ id: FeatureID.ProductSub, type: FeatureType.String, value: String(nav.productSub ?? "") },
		{ id: FeatureID.AppName, type: FeatureType.String, value: navigator.appName },
		{ id: FeatureID.AppVersion, type: FeatureType.String, value: navigator.appVersion },
		{ id: FeatureID.CookieEnabled, type: FeatureType.Boolean, value: navigator.cookieEnabled },
		{ id: FeatureID.DoNotTrack, type: FeatureType.String, value: String(nav.doNotTrack ?? "unspecified") },
		{ id: FeatureID.HardwareConcurrency, type: FeatureType.Integer, value: navigator.hardwareConcurrency },
		{ id: FeatureID.MaxTouchPoints, type: FeatureType.Integer, value: navigator.maxTouchPoints },
	);
	if (typeof nav.deviceMemory === "number") {
		signals.push({ id: FeatureID.DeviceMemory, type: FeatureType.Float, value: nav.deviceMemory as number });
	}
	if (typeof nav.pdfViewerEnabled === "boolean") {
		signals.push({ id: FeatureID.PdfViewerEnabled, type: FeatureType.Boolean, value: nav.pdfViewerEnabled as boolean });
	}
	if (typeof nav.vendorSub === "string" && (nav.vendorSub as string).length > 0) {
		signals.push({ id: FeatureID.VendorSub, type: FeatureType.String, value: nav.vendorSub as string });
	}
	if (typeof nav.deviceMemory === "number") {
		signals.push({ id: FeatureID.DeviceRam, type: FeatureType.Integer, value: Math.round(nav.deviceMemory as number) });
	}
}

function collectScreenSignals(signals: Signal[]): void {
	signals.push(
		{ id: FeatureID.ScreenWidth, type: FeatureType.Integer, value: screen.width },
		{ id: FeatureID.ScreenHeight, type: FeatureType.Integer, value: screen.height },
		{ id: FeatureID.AvailableWidth, type: FeatureType.Integer, value: screen.availWidth },
		{ id: FeatureID.AvailableHeight, type: FeatureType.Integer, value: screen.availHeight },
		{ id: FeatureID.ColorDepth, type: FeatureType.Integer, value: screen.colorDepth },
		{ id: FeatureID.PixelDepth, type: FeatureType.Integer, value: screen.pixelDepth },
		{ id: FeatureID.DevicePixelRatio, type: FeatureType.Float, value: window.devicePixelRatio },
		{ id: FeatureID.InnerWidth, type: FeatureType.Integer, value: window.innerWidth },
		{ id: FeatureID.InnerHeight, type: FeatureType.Integer, value: window.innerHeight },
		{ id: FeatureID.OuterWidth, type: FeatureType.Integer, value: window.outerWidth },
		{ id: FeatureID.OuterHeight, type: FeatureType.Integer, value: window.outerHeight },
	);
	const orientation = screen.orientation?.type;
	if (orientation) {
		signals.push({ id: FeatureID.ScreenOrientation, type: FeatureType.String, value: orientation });
	}
}

function collectLocaleSignals(signals: Signal[]): void {
	signals.push(
		{ id: FeatureID.Locale, type: FeatureType.String, value: navigator.language },
		{ id: FeatureID.Timezone, type: FeatureType.String, value: Intl.DateTimeFormat().resolvedOptions().timeZone },
		{ id: FeatureID.TimezoneOffset, type: FeatureType.Integer, value: new Date().getTimezoneOffset() },
		{ id: FeatureID.DateTimeFormat, type: FeatureType.String, value: new Intl.DateTimeFormat().resolvedOptions().locale },
	);
}

function collectStorageSignals(signals: Signal[]): void {
	signals.push(
		{ id: FeatureID.LocalStorage, type: FeatureType.Boolean, value: isStorageAvailable("localStorage") },
		{ id: FeatureID.SessionStorage, type: FeatureType.Boolean, value: isStorageAvailable("sessionStorage") },
		{ id: FeatureID.IndexedDB, type: FeatureType.Boolean, value: "indexedDB" in window },
		{ id: FeatureID.CacheStorage, type: FeatureType.Boolean, value: "caches" in window },
		{ id: FeatureID.CookiesEnabled, type: FeatureType.Boolean, value: navigator.cookieEnabled },
	);
}

function collectNetworkSignals(signals: Signal[]): void {
	const conn = (navigator as unknown as {
		connection?: {
			type?: string;
			downlink?: number;
			effectiveType?: string;
			rtt?: number;
			saveData?: boolean;
		};
	}).connection;
	if (conn) {
		signals.push(
			{ id: FeatureID.ConnectionType, type: FeatureType.String, value: conn.type || "unknown" },
			{ id: FeatureID.ConnectionDownlink, type: FeatureType.Float, value: conn.downlink || 0 },
			{ id: FeatureID.ConnectionEffectiveType, type: FeatureType.String, value: conn.effectiveType || "unknown" },
			{ id: FeatureID.ConnectionRtt, type: FeatureType.Integer, value: conn.rtt || 0 },
			{ id: FeatureID.ConnectionSaveData, type: FeatureType.Boolean, value: conn.saveData || false },
		);
	}
}

function isStorageAvailable(type: "localStorage" | "sessionStorage"): boolean {
	try {
		const storage = window[type];
		const testKey = "__fp_test__";
		storage.setItem(testKey, "1");
		storage.removeItem(testKey);
		return true;
	} catch {
		return false;
	}
}
