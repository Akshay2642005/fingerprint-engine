/**
 * Fingerprint Engine — WebAssembly bindings for browser JavaScript.
 *
 * Architecture: JS collects raw device data → Zig processes + hashes
 *
 * Usage:
 *   const engine = await FingerprintEngine.create(wasmUrl);
 *   engine.collect();  // Gathers all device signals
 *   const result = engine.compute();  // Zig hashes everything
 *   console.log(result.digest);
 */

import { FeatureID, ErrorCode, type ComputeResult } from "./types";

// ── Engine ──

export class FingerprintEngine {
	private readonly exports: WebAssembly.Exports & {
		fingerprint_init: () => number;
		fingerprint_reset: () => void;
		fingerprint_feature_count: () => number;
		fingerprint_get_error: () => number;
		fingerprint_add_boolean: (id: number, value: number) => number;
		fingerprint_add_integer: (id: number, value: bigint) => number;
		fingerprint_add_float: (id: number, value: number) => number;
		fingerprint_add_string: (id: number, ptr: number, len: number) => number;
		fingerprint_add_bytes: (id: number, ptr: number, len: number) => number;
		fingerprint_compute: () => number;
		fingerprint_get_digest_ptr: () => number;
		fingerprint_normalize: () => number;
		fingerprint_risk: () => number;
		fingerprint_entropy: () => number;
		memory: WebAssembly.Memory;
	};
	private readonly textEncoder: TextEncoder;
	private scratchOffset = 0;

	private constructor(instance: WebAssembly.Instance) {
		this.exports = instance.exports as typeof this.exports;
		this.textEncoder = new TextEncoder();
	}

	/** Create and initialize the engine from a WASM URL. */
	static async create(wasmUrl: string | URL): Promise<FingerprintEngine> {
		const module = await WebAssembly.instantiateStreaming(fetch(wasmUrl));
		const engine = new FingerprintEngine(module.instance);
		engine.init();
		return engine;
	}

	/** Create from an already-instantiated WASM instance. */
	static fromInstance(instance: WebAssembly.Instance): FingerprintEngine {
		const engine = new FingerprintEngine(instance);
		engine.init();
		return engine;
	}

	private init(): void {
		const code = this.exports.fingerprint_init();
		if (code !== ErrorCode.Success) {
			throw new Error(`fingerprint_init failed: ${this.getError()}`);
		}
	}

	/** Reset all features. */
	reset(): void {
		this.exports.fingerprint_reset();
	}

	/** Get number of added features. */
	featureCount(): number {
		return this.exports.fingerprint_feature_count();
	}

	// ── Raw data collection methods ──

	/** Collect all available device signals. */
	collect(): void {
		this.collectNavigator();
		this.collectScreen();
		this.collectHardware();
		this.collectStorage();
		this.collectNetwork();
		this.collectLocale();
		this.collectCapabilities();
	}

	private collectNavigator(): void {
		this.addString(FeatureID.UserAgent, navigator.userAgent);
		this.addString(FeatureID.Language, navigator.language);
		this.addStringArray(FeatureID.Languages, Array.from(navigator.languages));
		this.addString(FeatureID.Platform, navigator.platform);
		this.addString(FeatureID.Vendor, navigator.vendor);
		this.addString(FeatureID.Product, navigator.product);
		this.addString(FeatureID.AppName, navigator.appName);
		this.addString(FeatureID.AppVersion, navigator.appVersion);
		this.addBoolean(FeatureID.CookieEnabled, navigator.cookieEnabled);
		this.addString(FeatureID.DoNotTrack, navigator.doNotTrack ?? "unspecified");
		this.addInteger(
			FeatureID.HardwareConcurrency,
			navigator.hardwareConcurrency,
		);
		this.addInteger(FeatureID.MaxTouchPoints, navigator.maxTouchPoints);

		const nav = navigator as Navigator & { deviceMemory?: number };
		if (nav.deviceMemory) {
			this.addFloat(FeatureID.DeviceMemory, nav.deviceMemory);
		}
	}

	private collectScreen(): void {
		this.addInteger(FeatureID.ScreenWidth, screen.width);
		this.addInteger(FeatureID.ScreenHeight, screen.height);
		this.addInteger(FeatureID.AvailableWidth, screen.availWidth);
		this.addInteger(FeatureID.AvailableHeight, screen.availHeight);
		this.addInteger(FeatureID.ColorDepth, screen.colorDepth);
		this.addInteger(FeatureID.PixelDepth, screen.pixelDepth);
		this.addFloat(FeatureID.DevicePixelRatio, window.devicePixelRatio);
		this.addInteger(FeatureID.InnerWidth, window.innerWidth);
		this.addInteger(FeatureID.InnerHeight, window.innerHeight);
		this.addInteger(FeatureID.OuterWidth, window.outerWidth);
		this.addInteger(FeatureID.OuterHeight, window.outerHeight);

		const orientation = screen.orientation;
		if (orientation) {
			this.addString(FeatureID.ScreenOrientation, orientation.type);
		}
	}

	private collectHardware(): void {
		const nav = navigator as Navigator & { cpuClass?: string };
		if (nav.cpuClass) {
			this.addString(FeatureID.CpuClass, nav.cpuClass);
		}

		this.addBoolean(FeatureID.TouchSupport, navigator.maxTouchPoints > 0);
	}

	private collectStorage(): void {
		this.addBoolean(
			FeatureID.LocalStorage,
			this.isStorageAvailable("localStorage"),
		);
		this.addBoolean(
			FeatureID.SessionStorage,
			this.isStorageAvailable("sessionStorage"),
		);
		this.addBoolean(FeatureID.IndexedDB, "indexedDB" in window);
		this.addBoolean(FeatureID.CacheStorage, "caches" in window);
	}

	private collectNetwork(): void {
		const conn = (navigator as Navigator & { connection?: NetworkInformation })
			.connection;
		if (conn) {
			this.addString(FeatureID.ConnectionType, conn.type ?? "unknown");
			this.addFloat(FeatureID.ConnectionDownlink, conn.downlink ?? 0);
			this.addString(
				FeatureID.ConnectionEffectiveType,
				conn.effectiveType ?? "unknown",
			);
			this.addInteger(FeatureID.ConnectionRtt, conn.rtt ?? 0);
			this.addBoolean(FeatureID.ConnectionSaveData, conn.saveData ?? false);
		}
	}

	private collectLocale(): void {
		this.addString(FeatureID.Locale, navigator.language);
		this.addString(
			FeatureID.Timezone,
			Intl.DateTimeFormat().resolvedOptions().timeZone,
		);
		this.addInteger(FeatureID.TimezoneOffset, new Date().getTimezoneOffset());
		this.addString(
			FeatureID.DateTimeFormat,
			new Intl.DateTimeFormat().resolvedOptions().locale,
		);
	}

	private collectCapabilities(): void {
		this.addBoolean(FeatureID.CryptoSupport, "crypto" in window);
		this.addBoolean(FeatureID.SubtleCrypto, "subtle" in (window.crypto || {}));

		// GPU info from WebGL
		const canvas = document.createElement("canvas");
		const gl = canvas.getContext("webgl");
		if (gl) {
			const debugInfo = gl.getExtension("WEBGL_debug_renderer_info");
			if (debugInfo) {
				this.addString(
					FeatureID.WebGLVendor,
					gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL),
				);
				this.addString(
					FeatureID.WebGLRenderer,
					gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL),
				);
			}
			this.addString(FeatureID.WebGLVersion, gl.getParameter(gl.VERSION));
		}

		// Workers
		this.addBoolean(
			FeatureID.ServiceWorkerSupport,
			"serviceWorker" in navigator,
		);
		this.addBoolean(FeatureID.WebWorkerSupport, "Worker" in window);
		this.addBoolean(FeatureID.WebRTCSupport, "RTCPeerConnection" in window);

		// CSS features
		this.addBoolean(
			FeatureID.CSSGridSupport,
			this.supportsCSS("display", "grid"),
		);
		this.addBoolean(
			FeatureID.CSSFlexboxSupport,
			this.supportsCSS("display", "flex"),
		);
	}

	// ── Low-level add methods ──

	addBoolean(id: FeatureID, value: boolean): void {
		const code = this.exports.fingerprint_add_boolean(id, value ? 1 : 0);
		if (code !== ErrorCode.Success)
			throw new Error(`add_boolean failed: ${this.getError()}`);
	}

	addInteger(id: FeatureID, value: number): void {
		const code = this.exports.fingerprint_add_integer(id, BigInt(value));
		if (code !== ErrorCode.Success)
			throw new Error(`add_integer failed: ${this.getError()}`);
	}

	addFloat(id: FeatureID, value: number): void {
		const code = this.exports.fingerprint_add_float(id, value);
		if (code !== ErrorCode.Success)
			throw new Error(`add_float failed: ${this.getError()}`);
	}

	addString(id: FeatureID, value: string): void {
		const encoded = this.textEncoder.encode(value);
		const ptr = this.writeToMemory(encoded);
		const code = this.exports.fingerprint_add_string(id, ptr, encoded.length);
		if (code !== ErrorCode.Success)
			throw new Error(`add_string failed: ${this.getError()}`);
	}

	addBytes(id: FeatureID, value: Uint8Array): void {
		const ptr = this.writeToMemory(value);
		const code = this.exports.fingerprint_add_bytes(id, ptr, value.length);
		if (code !== ErrorCode.Success)
			throw new Error(`add_bytes failed: ${this.getError()}`);
	}

	addStringArray(id: FeatureID, values: string[]): void {
		// Encode as null-separated strings
		const parts: Uint8Array[] = values.map((s) => this.textEncoder.encode(s));
		const totalLen = parts.reduce((acc, p) => acc + p.length, 0) + parts.length;
		const buf = new Uint8Array(totalLen);
		let offset = 0;
		for (const part of parts) {
			buf.set(part, offset);
			offset += part.length;
			buf[offset] = 0;
			offset += 1;
		}
		this.addBytes(id, buf);
	}

	// ── Compute ──

	compute(): ComputeResult {
		const ptr = this.exports.fingerprint_compute();
		if (ptr === 0) {
			throw new Error(`fingerprint_compute failed: ${this.getError()}`);
		}
		const memory = this.exports.memory.buffer;
		const digest = new Uint8Array(memory.slice(ptr, ptr + 32));
		return {
			digest: digest as ComputeResult["digest"],
			featureCount: this.featureCount(),
		};
	}

	/** Collect all signals, compute digest, and return result. */
	collectAndCompute(): ComputeResult {
		this.collect();
		return this.compute();
	}

	// ── Processing ──

	normalize(): number {
		return this.exports.fingerprint_normalize();
	}

	risk(): number {
		return this.exports.fingerprint_risk();
	}

	entropy(): number {
		return this.exports.fingerprint_entropy();
	}

	// ── Private helpers ──

	private writeToMemory(data: Uint8Array): number {
		const memory = this.exports.memory;
		const needed = this.scratchOffset + data.length;
		const pagesNeeded = Math.ceil(needed / 65536);
		const currentPages = memory.buffer.byteLength / 65536;
		if (pagesNeeded > currentPages) {
			memory.grow(pagesNeeded - currentPages);
		}
		const view = new Uint8Array(memory.buffer);
		view.set(data, this.scratchOffset);
		const ptr = this.scratchOffset;
		this.scratchOffset += data.length;
		return ptr;
	}

	private getError(): string {
		const ptr = this.exports.fingerprint_get_error();
		if (ptr === 0) return "";
		const memory = this.exports.memory.buffer;
		const view = new Uint8Array(memory);
		let end = ptr;
		while (end < view.length && view[end] !== 0) end++;
		return new TextDecoder().decode(view.slice(ptr, end));
	}

	private isStorageAvailable(type: "localStorage" | "sessionStorage"): boolean {
		try {
			const storage = window[type];
			const testKey = "__fingerprint_test__";
			storage.setItem(testKey, "1");
			storage.removeItem(testKey);
			return true;
		} catch {
			return false;
		}
	}

	private supportsCSS(property: string, value: string): boolean {
		return CSS.supports(property, value);
	}
}

// NetworkInformation type for TypeScript
interface NetworkInformation extends EventTarget {
	type?: string;
	downlink?: number;
	effectiveType?: string;
	rtt?: number;
	saveData?: boolean;
}
