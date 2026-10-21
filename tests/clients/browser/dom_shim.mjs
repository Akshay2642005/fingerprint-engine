/**
 * Minimal DOM shim for exercising the browser SDK's orchestration layer in
 * Node. The SDK's always-on collectors read `navigator`, `screen`, and
 * `window` directly; this shim supplies just enough for them and lets callers
 * disable the rendering-heavy collectors with `LIGHT`.
 */

/** Disable every collector that needs a real rendering/DOM stack. */
export const LIGHT = Object.freeze({
	enableCanvas: false,
	enableWebGL: false,
	enableAudio: false,
	enableFonts: false,
	enableBattery: false,
	enableMedia: false,
	enableSpeech: false,
	enableInput: false,
	enablePermissions: false,
});

function storage() {
	const map = new Map();
	return {
		setItem: (k, v) => map.set(k, String(v)),
		removeItem: (k) => map.delete(k),
		getItem: (k) => (map.has(k) ? map.get(k) : null),
		clear: () => map.clear(),
	};
}

/** Installs deterministic `window` / `navigator` / `screen` globals. */
export function installDomShim() {
	const win = {
		devicePixelRatio: 2,
		innerWidth: 1280,
		innerHeight: 720,
		outerWidth: 1440,
		outerHeight: 900,
		crypto: globalThis.crypto,
		localStorage: storage(),
		sessionStorage: storage(),
		indexedDB: {},
		caches: {},
		Worker: function Worker() {},
		WebSocket: function WebSocket() {},
		RTCPeerConnection: function RTCPeerConnection() {},
	};

	const nav = {
		userAgent: "Mozilla/5.0 (contract-test) FingerprintEngine",
		language: "en-US",
		languages: ["en-US", "en"],
		platform: "MacIntel",
		vendor: "Test",
		product: "Gecko",
		productSub: "20100101",
		appName: "Netscape",
		appVersion: "5.0 (contract-test)",
		cookieEnabled: true,
		doNotTrack: null,
		hardwareConcurrency: 8,
		maxTouchPoints: 0,
	};

	const scr = {
		width: 1440,
		height: 900,
		availWidth: 1440,
		availHeight: 860,
		colorDepth: 24,
		pixelDepth: 24,
		orientation: { type: "landscape-primary" },
	};

	Object.defineProperty(globalThis, "window", { value: win, configurable: true, writable: true });
	Object.defineProperty(globalThis, "navigator", { value: nav, configurable: true, writable: true });
	Object.defineProperty(globalThis, "screen", { value: scr, configurable: true, writable: true });
}
