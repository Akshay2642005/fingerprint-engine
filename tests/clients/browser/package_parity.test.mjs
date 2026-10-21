// Golden parity test (DESIGN §9.4.6): rebuilds the canonical SignalPackage
// v2 bytes from the JSON manifest via the browser serializer and asserts
// byte equality with the Zig-produced .bin fixture — cross-language proof
// that the TS package encoder mirrors serialization/binary.zig exactly.
//
// Requires dist/ to be built first: run `zig build clients:browser` from the
// repository root before `npm test` (or `node --test tests/clients/browser/`).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { encodeSignalPackage } from "../../../src/clients/browser/dist/package.js";
import { FeatureType } from "../../../src/clients/browser/dist/generated/tables.js";

const here = dirname(fileURLToPath(import.meta.url));
const fixtureDir = join(here, "..", "..", "fixtures", "fingerprints");

function hexToBytes(hex) {
	const bytes = new Uint8Array(hex.length / 2);
	for (let i = 0; i < bytes.length; i++) {
		bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
	}
	return bytes;
}

function decodeValue(signal) {
	// Byte payloads travel as lowercase hex in the manifest.
	if (signal.type === "Bytes" || signal.type === "BytesArray") {
		if (Array.isArray(signal.value)) return signal.value.map(hexToBytes);
		return hexToBytes(signal.value);
	}
	return signal.value;
}

// The manifest names types for readability; the serializer wants the numeric
// FeatureType values from the generated table.
function toType(name) {
	return FeatureType[name];
}

test("TS serializer reproduces the canonical Zig fixture bytes", () => {
	const manifest = JSON.parse(
		readFileSync(join(fixtureDir, "signal-package-v2.signals.json"), "utf8"),
	);
	const golden = readFileSync(join(fixtureDir, "signal-package-v2.bin"));

	const signals = manifest.signals.map((s) => ({
		id: s.id,
		type: toType(s.type),
		value: decodeValue(s),
	}));
	const bytes = encodeSignalPackage(signals, {
		sdkVersion: manifest.sdk_version,
		collectedAt: manifest.collected_at,
		packageId: hexToBytes(manifest.package_id),
	});

	assert.equal(manifest.schema_version, 2);
	assert.deepEqual(Buffer.from(bytes), golden);
});

test("wire layout: magic, schema, header fields, TLV framing", () => {
	const signals = [
		{ id: 0, type: FeatureType.String, value: "ab" },
		{ id: 9, type: FeatureType.Boolean, value: true },
	];
	const bytes = encodeSignalPackage(signals, {
		sdkVersion: "0.2.0",
		collectedAt: 123,
		packageId: new Uint8Array(16),
	});
	const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);

	assert.equal(new TextDecoder().decode(bytes.subarray(0, 4)), "FNGR");
	assert.equal(view.getUint16(4, true), 2, "schema version");

	const sdkLen = view.getUint16(6, true);
	const headerLen = 4 + 2 + 2 + sdkLen + 8 + 16;
	assert.equal(view.getUint16(headerLen, true), 2, "feature count");

	// First feature TLV: id 0 (u16), type 3 = String (u8), payload_len 6 (u32),
	// payload = u32 len 2 + "ab".
	assert.equal(view.getUint16(headerLen + 2, true), 0, "first feature id");
	assert.equal(view.getUint8(headerLen + 4), 3, "first feature type");
	assert.equal(view.getUint32(headerLen + 5, true), 6, "first payload length");
	assert.equal(view.getUint32(headerLen + 9, true), 2, "string length prefix");
	assert.equal(
		new TextDecoder().decode(bytes.subarray(headerLen + 13, headerLen + 15)),
		"ab",
	);

	// Second feature TLV: id 9 (u16), type 0 = Boolean (u8), payload_len 1
	// (u32), payload `01` — starts right after the first TLV (13 bytes).
	assert.equal(view.getUint16(headerLen + 15, true), 9, "second feature id");
	assert.equal(view.getUint8(headerLen + 17), 0, "second feature type");
	assert.equal(view.getUint32(headerLen + 18, true), 1, "second payload length");
	assert.equal(view.getUint8(headerLen + 22), 1, "second payload byte");

	// ADR-012 capability tail follows the last TLV (DESIGN §9.4.7):
	// signals_count(2) | ids 0, 9 — always emitted, little-endian u16s.
	// story: m6-sdk-signals
	const tailOff = headerLen + 23;
	assert.equal(
		view.getUint16(tailOff, true),
		2,
		"capability tail signals count",
	);
	assert.equal(view.getUint16(tailOff + 2, true), 0, "capability tail first id");
	assert.equal(view.getUint16(tailOff + 4, true), 9, "capability tail second id");
	assert.equal(bytes.byteLength, tailOff + 6, "capability tail ends the package");
});

test("capability tail: sorted ascending, deduplicated", () => {
	const signals = [
		{ id: 11, type: FeatureType.Integer, value: 8 },
		{ id: 0, type: FeatureType.String, value: "a" },
		{ id: 11, type: FeatureType.Integer, value: 9 },
		{ id: 9, type: FeatureType.Boolean, value: true },
	];
	const bytes = encodeSignalPackage(signals, {
		sdkVersion: "0.2.0",
		collectedAt: 123,
		packageId: new Uint8Array(16),
	});

	// Tail: signals_count 3 | ids 0, 9, 11 (u16 little-endian).
	assert.deepEqual(
		Buffer.from(bytes.subarray(bytes.length - 8)),
		Buffer.from([3, 0, 0, 0, 9, 0, 11, 0]),
	);
});

test("capability tail: empty signal set still emits a count", () => {
	const bytes = encodeSignalPackage([], {
		sdkVersion: "0.2.0",
		collectedAt: 123,
		packageId: new Uint8Array(16),
	});
	assert.deepEqual(
		Buffer.from(bytes.subarray(bytes.length - 2)),
		Buffer.from([0, 0]),
	);
});
