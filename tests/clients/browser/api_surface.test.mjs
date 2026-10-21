/**
 * SDK 1.0 public-surface contract tests (W4-D1 / W4-D3).
 *
 * The SDK is browser-targeted and its always-on collectors read `navigator`,
 * `screen`, and `window` directly. This file installs a minimal DOM shim and
 * disables the heavy collectors so the orchestration layer (`packageSignals`,
 * `collect`, error surfacing) can be exercised in Node.
 *
 * Everything is imported from `dist/index.js` — the published entry point —
 * so these tests fail if a symbol leaves the public surface.
 *
 * story: m6-sdk-api-freeze
 */

import { test, before } from "node:test";
import assert from "node:assert/strict";

let sdk;

function installDomShim() {
	const storage = () => {
		const map = new Map();
		return {
			setItem: (k, v) => map.set(k, String(v)),
			removeItem: (k) => map.delete(k),
			getItem: (k) => (map.has(k) ? map.get(k) : null),
			clear: () => map.clear(),
		};
	};

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

/** Disable every collector that needs a real rendering/DOM stack. */
const LIGHT = {
	enableCanvas: false,
	enableWebGL: false,
	enableAudio: false,
	enableFonts: false,
	enableBattery: false,
	enableMedia: false,
	enableSpeech: false,
	enableInput: false,
	enablePermissions: false,
};

before(async () => {
	installDomShim();
	sdk = await import("../../../src/clients/browser/dist/index.js");
});

test("public surface exports the frozen 1.0 symbols", () => {
	const functions = [
		"configure",
		"packageSignals",
		"collect",
		"assertAllowed",
		"onSessionBlocked",
		"getFeatureIDs",
		"encodeSignalPackage",
		"newPackageId",
		"toHex",
		"sendPackage",
		"connectDecisionSocket",
	];
	for (const name of functions) {
		assert.equal(typeof sdk[name], "function", `${name} must be a function`);
	}
	assert.equal(typeof sdk.DecisionGate, "function");
	assert.equal(typeof sdk.SDK_VERSION, "string");
	assert.equal(typeof sdk.SCHEMA_VERSION, "number");
	assert.equal(sdk.MAGIC, "FNGR");
	assert.equal(typeof sdk.FeatureID, "object");
	assert.equal(typeof sdk.FeatureType, "object");

	const ergonomic = ["configure", "packageSignals", "collect", "assertAllowed", "onSessionBlocked", "getFeatureIDs"];
	for (const name of ergonomic) {
		assert.equal(sdk.default[name], sdk[name], `default.${name} must alias the named export`);
	}
});

test("packageSignals() packages without sending", async () => {
	let fetchCalls = 0;
	const originalFetch = globalThis.fetch;
	globalThis.fetch = async () => {
		fetchCalls++;
		throw new Error("fetch must not be called by packageSignals()");
	};

	try {
		const pkg = await sdk.packageSignals(LIGHT);
		assert.ok(pkg.packageId instanceof Uint8Array);
		assert.equal(pkg.packageId.byteLength, 16);
		assert.ok(pkg.bytes instanceof Uint8Array);
		assert.ok(pkg.bytes.byteLength > 0);
		assert.equal(pkg.hex, sdk.toHex(pkg.bytes));
		assert.ok(pkg.signalCount > 0);
		assert.equal(fetchCalls, 0);
		assert.equal("sent" in pkg, false, "PackageResult has no transport fields");
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test("collect() surfaces a transport failure as sent=false + error", async () => {
	const originalFetch = globalThis.fetch;
	globalThis.fetch = async () => {
		throw new Error("network down");
	};

	try {
		sdk.configure({ ingressUrl: "https://ingress.invalid/v1/fingerprints" });
		const result = await sdk.collect(LIGHT);
		assert.equal(result.sent, false);
		assert.equal(result.status, 0);
		assert.equal(result.error, "network down");
		assert.ok(result.signalCount > 0);
		assert.ok(result.hex.length > 0);
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test("collect() reports an HTTP rejection via status, without throwing", async () => {
	const originalFetch = globalThis.fetch;
	globalThis.fetch = async () => new Response(new Uint8Array(0), { status: 503 });

	try {
		sdk.configure({ ingressUrl: "https://ingress.invalid/v1/fingerprints" });
		const result = await sdk.collect(LIGHT);
		assert.equal(result.sent, false);
		assert.equal(result.status, 503);
		assert.equal(result.error, undefined);
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test("collect() reports an accepted POST whose reply body cannot be read", async () => {
	const originalFetch = globalThis.fetch;
	globalThis.fetch = async () => ({
		ok: true,
		status: 200,
		arrayBuffer: async () => {
			throw new Error("socket closed");
		},
	});

	try {
		sdk.configure({ ingressUrl: "https://ingress.invalid/v1/fingerprints" });
		const result = await sdk.collect(LIGHT);
		assert.equal(result.sent, true);
		assert.equal(result.status, 200);
		assert.equal(result.reply, undefined);
		assert.match(result.error, /failed to read ingress reply: socket closed/);
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test("collect() reports a 2xx acceptance", async () => {
	const originalFetch = globalThis.fetch;
	globalThis.fetch = async () => new Response(new Uint8Array(0), { status: 202 });

	try {
		sdk.configure({ ingressUrl: "https://ingress.invalid/v1/fingerprints" });
		const result = await sdk.collect(LIGHT);
		assert.equal(result.sent, true);
		assert.equal(result.status, 202);
	} finally {
		globalThis.fetch = originalFetch;
	}
});
