#!/usr/bin/env node
/**
 * @fingerprint/sdk — Build script
 *
 * Compiles WASM, inlines it as base64, and produces:
 *   dist/fingerprint.umd.js   — UMD bundle (global: Fingerprint)
 *   dist/fingerprint.esm.js   — ES module
 *   dist/index.d.ts           — TypeScript declarations
 *   dist/demo.html            — Browser demo
 */

import {
	readFileSync,
	writeFileSync,
	mkdirSync,
	copyFileSync,
	existsSync,
} from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { execSync } from "child_process";
import { createHash } from "crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "../..");
const DIST = join(__dirname, "dist");
const WASM_PATH = join(ROOT, "zig-out/bin/fingerprint.wasm");

console.log("Building @fingerprint/sdk...\n");

// Step 1: Build WASM with ReleaseSmall for minimal binary size
console.log("1. Compiling WASM (ReleaseSmall)...");
try {
	execSync("zig build wasm -Doptimize=ReleaseSmall", {
		cwd: ROOT,
		stdio: "inherit",
	});
} catch (e) {
	console.error("WASM build failed:", e.message);
	process.exit(1);
}

const wasmBytes = readFileSync(WASM_PATH);
const wasmBase64 = wasmBytes.toString("base64");
const wasmHash = createHash("sha256")
	.update(wasmBytes)
	.digest("hex")
	.slice(0, 8);
console.log(
	"   WASM: " +
		(wasmBytes.length / 1024).toFixed(1) +
		" KB (sha256:" +
		wasmHash +
		")",
);

// Step 2: Read package meta
console.log("2. Reading package metadata...");
let pkg;
try {
	pkg = JSON.parse(readFileSync(join(__dirname, "package.json"), "utf8"));
} catch (e) {
	console.error("Failed to read package.json:", e.message);
	process.exit(1);
}
const version = pkg.version;
console.log("   Version: " + version);

// Step 3: Create dist/
console.log("3. Creating dist/...");
mkdirSync(DIST, { recursive: true });

// Step 4: Read template
console.log("4. Reading template...");
let template = readFileSync(
	join(__dirname, "scripts", "fingerprint-umd-template.js"),
	"utf8",
);
template = template.replace(/__WASM_BASE64__/g, wasmBase64);
template = template.replace(/__VERSION__/g, version);

// Step 5: Write UMD bundle
console.log("5. Writing UMD bundle...");
writeFileSync(join(DIST, "fingerprint.umd.js"), template);
console.log(
	"   UMD: dist/fingerprint.umd.js (" +
		(template.length / 1024).toFixed(1) +
		" KB)",
);

// Step 6: Generate ESM bundle
console.log("6. Generating ESM bundle...");
// We extract the factory body from the template, wrap as a named function,
// then export members at module scope (not inside the function).
var markerLine = "// Inlined WASM binary (base64)";
var factoryStart = template.indexOf(markerLine);
var lastReturn = template.lastIndexOf("return sdk;");
if (factoryStart === -1 || lastReturn === -1) {
	console.error("Could not parse template for ESM generation");
	process.exit(1);
}
var factoryBody = template.slice(
	factoryStart,
	lastReturn + "return sdk;".length,
);
var esmSdkName = "fingerprintSdk";
var esmCode =
	"/**\n" +
	" * @fingerprint/sdk v" +
	version +
	" (ES Module)\n" +
	" */\n" +
	"function " +
	esmSdkName +
	"() {\n" +
	factoryBody.trim() +
	"\n" +
	"}\n" +
	"\n" +
	"const { collect, reset, FeatureID, FeatureType, ErrorCode, getFeatureIDs } = " +
	esmSdkName +
	"();\n" +
	"\n" +
	"export { collect, reset, FeatureID, FeatureType, ErrorCode, getFeatureIDs };\n" +
	"export { collect as getFingerprint };\n" +
	"export default collect;\n";

writeFileSync(join(DIST, "fingerprint.esm.js"), esmCode);
console.log(
	"   ESM: dist/fingerprint.esm.js (" +
		(esmCode.length / 1024).toFixed(1) +
		" KB)",
);

// Step 7: Write type declarations
console.log("7. Writing type declarations...");
var dtsContent = [
	"/**",
	" * @fingerprint/sdk v" + version + " — TypeScript declarations",
	" */",
	"",
	"export interface CollectResult {",
	"  hex: string;",
	"  digest: Uint8Array;",
	"  risk: number;",
	"  entropy: number;",
	"  warnings: number;",
	"  signals: number;",
	"  collectedAt: number;",
	"}",
	"",
	"export declare const FeatureID: {",
];
var fidEntries = [
	["UserAgent", 0],
	["Language", 1],
	["Languages", 2],
	["Platform", 3],
	["Vendor", 4],
	["Product", 5],
	["ProductSub", 6],
	["AppName", 7],
	["AppVersion", 8],
	["CookieEnabled", 9],
	["DoNotTrack", 10],
	["HardwareConcurrency", 11],
	["MaxTouchPoints", 12],
	["DeviceMemory", 13],
	["PdfViewerEnabled", 14],
	["VendorSub", 15],
	["DeviceRam", 16],
	["ScreenWidth", 17],
	["ScreenHeight", 18],
	["AvailableWidth", 19],
	["AvailableHeight", 20],
	["ColorDepth", 21],
	["PixelDepth", 22],
	["DevicePixelRatio", 23],
	["InnerWidth", 24],
	["InnerHeight", 25],
	["OuterWidth", 26],
	["OuterHeight", 27],
	["ScreenOrientation", 28],
	["CpuClass", 29],
	["CpuCores", 30],
	["CpuArchitecture", 31],
	["PlatformArchitecture", 32],
	["HardwareAcceleration", 33],
	["TouchSupport", 34],
	["CanvasHash", 35],
	["WebGLVendor", 36],
	["WebGLRenderer", 37],
	["WebGLVersion", 38],
	["WebGLHash", 39],
	["WebGLExtensions", 40],
	["WebGLParameters", 41],
	["WebGLShaderPrecision", 42],
	["AudioHash", 43],
	["FontsHash", 44],
	["OperatingSystem", 45],
	["OSVersion", 46],
	["LocalStorage", 47],
	["SessionStorage", 48],
	["IndexedDB", 49],
	["CacheStorage", 50],
	["CookiesEnabled", 51],
	["NotificationPermission", 52],
	["GeolocationPermission", 53],
	["CameraPermission", 54],
	["MicrophonePermission", 55],
	["AudioInputDevices", 56],
	["AudioOutputDevices", 57],
	["VideoInputDevices", 58],
	["SupportedCodecs", 59],
	["MediaFormats", 60],
	["AudioFormats", 61],
	["ConnectionType", 62],
	["ConnectionDownlink", 63],
	["ConnectionEffectiveType", 64],
	["ConnectionRtt", 65],
	["ConnectionSaveData", 66],
	["Locale", 67],
	["Timezone", 68],
	["TimezoneOffset", 69],
	["DateTimeFormat", 70],
	["BatteryLevel", 71],
	["BatteryCharging", 72],
	["BatteryChargingTime", 73],
	["DecodeCapability", 74],
	["EncodeCapability", 75],
	["HDRSupport", 76],
	["CryptoSupport", 77],
	["SubtleCrypto", 78],
	["SpeechSynthesisVoices", 79],
	["GPUVendor", 80],
	["GPURenderer", 81],
	["GPUDriverVersion", 82],
	["HardwareConcurrencyPerformance", 83],
	["DeviceMemoryPerformance", 84],
	["TimePrecision", 85],
	["CSSCustomProperties", 86],
	["CSSGridSupport", 87],
	["CSSFlexboxSupport", 88],
	["CSSContainerQuery", 89],
	["CSSHasSelector", 90],
	["ServiceWorkerSupport", 91],
	["WebWorkerSupport", 92],
	["SharedWorkerSupport", 93],
	["WebSocketSupport", 94],
	["WebRTCSupport", 95],
	["KeyboardLayout", 96],
	["PointerEvents", 97],
	["GamepadSupport", 98],
	["SchemaVersion", 99],
	["SDKVersion", 100],
	["CollectionTimestamp", 101],
];
for (var i = 0; i < fidEntries.length; i++) {
	dtsContent.push(
		"  readonly " + fidEntries[i][0] + ": " + fidEntries[i][1] + ";",
	);
}
dtsContent.push("};");
dtsContent.push("");
dtsContent.push("export declare const FeatureType: {");
var ftEntries = [
	["Boolean", 0],
	["Integer", 1],
	["Float", 2],
	["String", 3],
	["Bytes", 4],
	["StringArray", 5],
	["IntegerArray", 6],
	["FloatArray", 7],
	["BytesArray", 8],
];
for (var i = 0; i < ftEntries.length; i++) {
	dtsContent.push(
		"  readonly " + ftEntries[i][0] + ": " + ftEntries[i][1] + ";",
	);
}
dtsContent.push("};");
dtsContent.push("");
dtsContent.push("export declare function collect(): Promise<CollectResult>;");
dtsContent.push("export declare function reset(): void;");
dtsContent.push("export declare function getFeatureIDs(): typeof FeatureID;");
dtsContent.push("export { collect as getFingerprint };");
dtsContent.push("export default collect;");
dtsContent.push("");
writeFileSync(join(DIST, "index.d.ts"), dtsContent.join("\n"));
console.log("   Types: dist/index.d.ts");

// Step 8: Copy demo
console.log("8. Demo...");
const demoSrc = join(ROOT, "src/browser/bindings/demo.html");
if (existsSync(demoSrc)) {
	copyFileSync(demoSrc, join(DIST, "demo.html"));
	console.log("   Demo: dist/demo.html");
}

console.log("\nBuild complete!");
console.log("\nDistribution files:");
console.log("  dist/fingerprint.umd.js  -- UMD (window.Fingerprint)");
console.log("  dist/fingerprint.esm.js  -- ES Module");
console.log("  dist/index.d.ts          -- TypeScript");
console.log("  dist/demo.html           -- Demo");
console.log("\nPublish: cd " + __dirname + " && npm publish");
console.log("\nCDN:");
console.log(
	'  <script src="https://cdn.jsdelivr.net/npm/@fingerprint/sdk@' +
		version +
		'"></script>',
);
console.log(
	"  <script>const fp = await Fingerprint.collect(); console.log(fp.hex);</script>",
);
