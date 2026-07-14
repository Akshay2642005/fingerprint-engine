/**
 * @akshay2642005/fingerprint-sdk v__VERSION__
 * Browser fingerprinting SDK — 102 signals, WASM-powered
 *
 * Usage:
 *   <script src="https://cdn.jsdelivr.net/npm/@akshay2642005/fingerprint-sdk"></script>
 *   <script>const result = await Fingerprint.collect(); console.log(result.hex);</script>
 */
((global, factory) => {
	typeof exports === "object" && typeof module !== "undefined"
		? (module.exports = factory())
		: typeof define === "function" && define.amd
			? define(factory)
			: ((global = global || self), (global.Fingerprint = factory()));
})(
	typeof globalThis !== "undefined"
		? globalThis
		: typeof self !== "undefined"
			? self
			: this,
	() => {
		// Inlined WASM binary (base64)
		const WASM_BASE64 = "__WASM_BASE64__";

		// FeatureID enum — 102 browser fingerprint signals
		const FeatureID = {
			UserAgent: 0,
			Language: 1,
			Languages: 2,
			Platform: 3,
			Vendor: 4,
			Product: 5,
			ProductSub: 6,
			AppName: 7,
			AppVersion: 8,
			CookieEnabled: 9,
			DoNotTrack: 10,
			HardwareConcurrency: 11,
			MaxTouchPoints: 12,
			DeviceMemory: 13,
			PdfViewerEnabled: 14,
			VendorSub: 15,
			DeviceRam: 16,
			ScreenWidth: 17,
			ScreenHeight: 18,
			AvailableWidth: 19,
			AvailableHeight: 20,
			ColorDepth: 21,
			PixelDepth: 22,
			DevicePixelRatio: 23,
			InnerWidth: 24,
			InnerHeight: 25,
			OuterWidth: 26,
			OuterHeight: 27,
			ScreenOrientation: 28,
			CpuClass: 29,
			CpuCores: 30,
			CpuArchitecture: 31,
			PlatformArchitecture: 32,
			HardwareAcceleration: 33,
			TouchSupport: 34,
			CanvasHash: 35,
			WebGLVendor: 36,
			WebGLRenderer: 37,
			WebGLVersion: 38,
			WebGLHash: 39,
			WebGLExtensions: 40,
			WebGLParameters: 41,
			WebGLShaderPrecision: 42,
			AudioHash: 43,
			FontsHash: 44,
			OperatingSystem: 45,
			OSVersion: 46,
			LocalStorage: 47,
			SessionStorage: 48,
			IndexedDB: 49,
			CacheStorage: 50,
			CookiesEnabled: 51,
			NotificationPermission: 52,
			GeolocationPermission: 53,
			CameraPermission: 54,
			MicrophonePermission: 55,
			AudioInputDevices: 56,
			AudioOutputDevices: 57,
			VideoInputDevices: 58,
			SupportedCodecs: 59,
			MediaFormats: 60,
			AudioFormats: 61,
			ConnectionType: 62,
			ConnectionDownlink: 63,
			ConnectionEffectiveType: 64,
			ConnectionRtt: 65,
			ConnectionSaveData: 66,
			Locale: 67,
			Timezone: 68,
			TimezoneOffset: 69,
			DateTimeFormat: 70,
			BatteryLevel: 71,
			BatteryCharging: 72,
			BatteryChargingTime: 73,
			DecodeCapability: 74,
			EncodeCapability: 75,
			HDRSupport: 76,
			CryptoSupport: 77,
			SubtleCrypto: 78,
			SpeechSynthesisVoices: 79,
			GPUVendor: 80,
			GPURenderer: 81,
			GPUDriverVersion: 82,
			HardwareConcurrencyPerformance: 83,
			DeviceMemoryPerformance: 84,
			TimePrecision: 85,
			CSSCustomProperties: 86,
			CSSGridSupport: 87,
			CSSFlexboxSupport: 88,
			CSSContainerQuery: 89,
			CSSHasSelector: 90,
			ServiceWorkerSupport: 91,
			WebWorkerSupport: 92,
			SharedWorkerSupport: 93,
			WebSocketSupport: 94,
			WebRTCSupport: 95,
			KeyboardLayout: 96,
			PointerEvents: 97,
			GamepadSupport: 98,
			SchemaVersion: 99,
			SDKVersion: 100,
			CollectionTimestamp: 101,
		};

		const FeatureType = {
			Boolean: 0,
			Integer: 1,
			Float: 2,
			String: 3,
			Bytes: 4,
			StringArray: 5,
			IntegerArray: 6,
			FloatArray: 7,
			BytesArray: 8,
		};

		const ErrorCode = {
			Success: 0,
			BufferFull: 1,
			InvalidFeature: 2,
			InvalidType: 3,
			NotInitialized: 4,
			InvalidInput: 5,
		};

		// WASM decoding & instantiation
		let _module = null;
		let _instance = null;
		let _scratchPtr = 0;

		async function ensureWasm() {
			if (_instance) return _instance;
			if (!_module) {
				const bytes = Uint8Array.from(atob(WASM_BASE64), (c) =>
					c.charCodeAt(0),
				);
				_module = await WebAssembly.instantiate(bytes);
			}
			_instance = _module.instance;
			const code = _instance.exports.fingerprint_init();
			if (code !== 0) throw new Error("fingerprint_init failed: " + code);
			_scratchPtr = _instance.exports.fingerprint_get_scratch_ptr();
			return _instance;
		}

		// WASM helpers
		var _scratchOffset = 0;
		var _encoder = new TextEncoder();

		function writeToMemory(data) {
			var exp = _instance.exports;
			var mem = exp.memory;
			var needed = _scratchOffset + data.length + 8;
			var pagesNeeded = Math.ceil(needed / 65536);
			var currentPages = mem.buffer.byteLength / 65536;
			if (pagesNeeded > currentPages) mem.grow(pagesNeeded - currentPages);
			new Uint8Array(mem.buffer).set(data, _scratchPtr + _scratchOffset);
			var ptr = _scratchPtr + _scratchOffset;
			_scratchOffset += data.length;
			return ptr;
		}

		function addBoolean(id, value) {
			_instance.exports.fingerprint_add_boolean(id, value ? 1 : 0);
		}

		function addInteger(id, value) {
			_instance.exports.fingerprint_add_integer(id, BigInt(Math.round(value)));
		}

		function addFloat(id, value) {
			_instance.exports.fingerprint_add_float(id, value);
		}

		function addString(id, value) {
			if (!value) return;
			var encoded = _encoder.encode(String(value));
			var ptr = writeToMemory(encoded);
			_instance.exports.fingerprint_add_string(id, ptr, encoded.length);
		}

		function addBytes(id, data) {
			if (!data || data.length === 0) return;
			var ptr = writeToMemory(data);
			_instance.exports.fingerprint_add_bytes(id, ptr, data.length);
		}

		function addStringArray(id, values) {
			if (!values || values.length === 0) return;
			var parts = values.map((v) => _encoder.encode(String(v)));
			var totalLen = parts.reduce((a, p) => a + p.length, 0) + parts.length;
			var buf = new Uint8Array(totalLen);
			var offset = 0;
			for (var i = 0; i < parts.length; i++) {
				buf.set(parts[i], offset);
				offset += parts[i].length;
				buf[offset] = 0;
				offset += 1;
			}
			addBytes(id, buf);
		}

		// --- Browser signal collectors ---

		function isStorageAvailable(type) {
			try {
				var s = window[type];
				var k = "__fp__";
				s.setItem(k, "1");
				s.removeItem(k);
				return true;
			} catch (e) {
				return false;
			}
		}

		function collectNavigator() {
			addString(0, navigator.userAgent);
			addString(1, navigator.language);
			addStringArray(2, Array.from(navigator.languages));
			addString(3, navigator.platform);
			addString(4, navigator.vendor);
			addString(5, navigator.product);
			addString(6, navigator.productSub || "");
			addString(7, navigator.appName);
			addString(8, navigator.appVersion);
			addBoolean(9, navigator.cookieEnabled);
			addString(10, navigator.doNotTrack || "unspecified");
			addInteger(11, navigator.hardwareConcurrency);
			addInteger(12, navigator.maxTouchPoints);
			if (navigator.deviceMemory) addFloat(13, navigator.deviceMemory);
		}

		function collectScreen() {
			addInteger(17, screen.width);
			addInteger(18, screen.height);
			addInteger(19, screen.availWidth);
			addInteger(20, screen.availHeight);
			addInteger(21, screen.colorDepth);
			addInteger(22, screen.pixelDepth);
			addFloat(23, window.devicePixelRatio);
			addInteger(24, window.innerWidth);
			addInteger(25, window.innerHeight);
			addInteger(26, window.outerWidth);
			addInteger(27, window.outerHeight);
			if (screen.orientation) addString(28, screen.orientation.type);
		}

		function collectCanvas() {
			try {
				var canvas = document.createElement("canvas");
				canvas.width = 200;
				canvas.height = 50;
				var ctx = canvas.getContext("2d");
				if (!ctx) return;
				ctx.fillStyle = "#f60";
				ctx.fillRect(0, 0, 200, 50);
				ctx.textBaseline = "top";
				ctx.font = "14px Arial";
				ctx.fillStyle = "#069";
				ctx.fillText("fingerprint-engine", 2, 15);
				ctx.fillStyle = "rgba(102, 204, 0, 0.7)";
				ctx.fillRect(100, 5, 80, 30);
				var grad = ctx.createLinearGradient(0, 0, 200, 0);
				grad.addColorStop(0, "red");
				grad.addColorStop(0.5, "green");
				grad.addColorStop(1, "blue");
				ctx.fillStyle = grad;
				ctx.fillRect(0, 40, 200, 10);
				var data = ctx.getImageData(0, 0, 200, 50);
				addBytes(35, new Uint8Array(data.data.buffer));
			} catch (e) {}
		}

		function collectWebGL() {
			try {
				var canvas = document.createElement("canvas");
				var gl =
					canvas.getContext("webgl") || canvas.getContext("experimental-webgl");
				if (!gl) return;
				var info = gl.getExtension("WEBGL_debug_renderer_info");
				if (info) {
					addString(36, gl.getParameter(info.UNMASKED_VENDOR_WEBGL));
					addString(37, gl.getParameter(info.UNMASKED_RENDERER_WEBGL));
				}
				addString(38, gl.getParameter(gl.VERSION));
				var exts = gl.getSupportedExtensions() || [];
				addStringArray(40, exts);
			} catch (e) {}
		}

		function collectStorage() {
			addBoolean(47, isStorageAvailable("localStorage"));
			addBoolean(48, isStorageAvailable("sessionStorage"));
			addBoolean(49, "indexedDB" in window);
			addBoolean(50, "caches" in window);
			addBoolean(51, navigator.cookieEnabled);
		}

		function collectNetwork() {
			var conn = navigator.connection;
			if (conn) {
				addString(62, conn.type || "unknown");
				addFloat(63, conn.downlink || 0);
				addString(64, conn.effectiveType || "unknown");
				addInteger(65, conn.rtt || 0);
				addBoolean(66, conn.saveData || false);
			}
		}

		function collectLocale() {
			addString(67, navigator.language);
			try {
				addString(68, Intl.DateTimeFormat().resolvedOptions().timeZone);
			} catch (e) {}
			addInteger(69, new Date().getTimezoneOffset());
			addString(70, new Intl.DateTimeFormat().resolvedOptions().locale);
		}

		function collectCapabilities() {
			addBoolean(77, "crypto" in window);
			addBoolean(78, "subtle" in (window.crypto || {}));
			try {
				addBoolean(86, CSS.supports("color", "--test:red"));
			} catch (e) {}
			try {
				addBoolean(87, CSS.supports("display", "grid"));
			} catch (e) {}
			try {
				addBoolean(88, CSS.supports("display", "flex"));
			} catch (e) {}
			try {
				addBoolean(89, CSS.supports("container-type", "inline-size"));
			} catch (e) {}
			try {
				addBoolean(90, CSS.supports("selector(:has(*))"));
			} catch (e) {}
			addBoolean(91, "serviceWorker" in navigator);
			addBoolean(92, "Worker" in window);
			addBoolean(93, typeof SharedWorker !== "undefined");
			addBoolean(94, "WebSocket" in window);
			addBoolean(95, "RTCPeerConnection" in window);
			addBoolean(97, "PointerEvent" in window);
			addBoolean(98, "getGamepads" in navigator);
		}

		function collectMetadata() {
			addInteger(99, 1);
			addString(100, "0.1.0");
			addInteger(101, Date.now());
		}

		// --- Async collectors ---

		async function collectBattery() {
			try {
				if (!navigator.getBattery) return;
				var b = await navigator.getBattery();
				addFloat(71, Math.round(b.level * 100));
				addBoolean(72, b.charging);
				addInteger(
					73,
					b.chargingTime === Infinity ? -1 : Math.round(b.chargingTime),
				);
			} catch (e) {}
		}

		async function collectAudio() {
			try {
				var AC = window.AudioContext || window.webkitAudioContext;
				if (!AC) return;
				var ctx = new AC({ sampleRate: 44100 });
				var osc = ctx.createOscillator();
				osc.type = "triangle";
				osc.frequency.setValueAtTime(10000, ctx.currentTime);
				var comp = ctx.createDynamicsCompressor();
				comp.threshold.setValueAtTime(-50, ctx.currentTime);
				comp.knee.setValueAtTime(40, ctx.currentTime);
				comp.ratio.setValueAtTime(12, ctx.currentTime);
				comp.attack.setValueAtTime(0, ctx.currentTime);
				comp.release.setValueAtTime(0.25, ctx.currentTime);
				osc.connect(comp);
				var analyser = ctx.createAnalyser();
				analyser.fftSize = 2048;
				comp.connect(analyser);
				analyser.connect(ctx.destination);
				osc.start(0);
				var buf = new Float32Array(analyser.frequencyBinCount);
				analyser.getFloatFrequencyData(buf);
				var bytes = new Uint8Array(buf.length * 4);
				var view = new DataView(bytes.buffer);
				for (var i = 0; i < buf.length; i++)
					view.setFloat32(i * 4, buf[i], true);
				addBytes(43, bytes);
				osc.stop();
				ctx.close();
			} catch (e) {}
		}

		async function collectMedia() {
			try {
				var video = document.createElement("video");
				var codecs = [
					["H264", 'video/mp4; codecs="avc1.42E01E"'],
					["VP8", 'video/webm; codecs="vp8"'],
					["VP9", 'video/webm; codecs="vp9"'],
					["AV1", 'video/webm; codecs="av01.0.08M.08"'],
					["AAC", 'audio/mp4; codecs="mp4a.40.2"'],
					["Opus", 'audio/webm; codecs="opus"'],
				];
				var supported = codecs
					.filter((c) => video.canPlayType(c[1]))
					.map((c) => c[0]);
				addStringArray(59, supported);
				try {
					addBoolean(76, window.matchMedia("(dynamic-range: high)").matches);
				} catch (e) {}
			} catch (e) {}
		}

		async function collectSpeech() {
			try {
				if (!window.speechSynthesis) return;
				var voices = window.speechSynthesis.getVoices();
				if (voices.length > 0) {
					addStringArray(
						79,
						voices.map((v) => v.name),
					);
				}
			} catch (e) {}
		}

		async function collectPermissions() {
			if (!navigator.permissions) return;
			async function q(name) {
				try {
					var s = await navigator.permissions.query({ name: name });
					return s.state;
				} catch (e) {
					return "unsupported";
				}
			}
			addString(52, await q("notifications"));
			addString(53, await q("geolocation"));
			addString(54, await q("camera"));
			addString(55, await q("microphone"));
		}

		// --- Public API ---

		async function collect() {
			await ensureWasm();
			_scratchOffset = 0;

			// Synchronous collectors
			collectNavigator();
			collectScreen();
			collectCanvas();
			collectWebGL();
			collectStorage();
			collectNetwork();
			collectLocale();
			collectCapabilities();
			collectMetadata();

			// Async collectors
			await Promise.all([
				collectBattery(),
				collectAudio(),
				collectMedia(),
				collectSpeech(),
				collectPermissions(),
			]);

			// Compute digest
			const ptr = _instance.exports.fingerprint_compute();
			const memBuf = _instance.exports.memory.buffer;
			const digest = new Uint8Array(memBuf.slice(ptr, ptr + 32));
			var hex = "";
			for (var i = 0; i < digest.length; i++) {
				hex += digest[i].toString(16).padStart(2, "0");
			}

			return {
				hex: hex,
				digest: digest,
				risk: _instance.exports.fingerprint_risk(),
				entropy: _instance.exports.fingerprint_entropy() / 100,
				warnings: _instance.exports.fingerprint_normalize(),
				signals: _instance.exports.fingerprint_feature_count(),
				collectedAt: Date.now(),
			};
		}

		function reset() {
			if (_instance) _instance.exports.fingerprint_reset();
			_scratchOffset = 0;
		}

		function getFeatureIDs() {
			return FeatureID;
		}

		// Exports
		const sdk = {
			collect: collect,
			reset: reset,
			FeatureID: FeatureID,
			FeatureType: FeatureType,
			ErrorCode: ErrorCode,
			getFeatureIDs: getFeatureIDs,
			getFingerprint: collect,
		};

		return sdk;
	},
);
