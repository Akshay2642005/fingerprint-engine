/**
 * Runtime API contract — collect → package → POST, and the wire/error edges.
 *
 * Complements `api_surface.test.mjs` (symbol list, packaging) by pinning the
 * full round trip: the exact bytes handed to `fetch`, the metadata headers, the
 * body/package-id agreement, and the worker-reply parsing on both 2xx and
 * non-2xx responses. A breaking change to any of these fails CI.
 *
 * story: m6-sdk-contract-tests
 */

import { test, before, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { installDomShim, LIGHT } from "./dom_shim.mjs";

let sdk;
const INGRESS = "https://ingress.test/v1/fingerprints";
const originalFetch = globalThis.fetch;
let calls;

before(async () => {
	installDomShim();
	sdk = await import("../../../src/clients/browser/dist/index.js");
});

beforeEach(() => {
	calls = [];
	sdk.configure({ ingressUrl: INGRESS });
});

afterEach(() => {
	globalThis.fetch = originalFetch;
});

/** Builds an ingress-relayed worker reply frame (DESIGN §5.1). */
function workerReply({ status = 0, digest, featureCount = 42, schemaVersion = 2 } = {}) {
	if (status !== 0) return Uint8Array.of(status);
	const d = digest ?? Uint8Array.from({ length: 32 }, (_, i) => i);
	const body = new Uint8Array(1 + 32 + 2 + 2);
	body[0] = status;
	body.set(d, 1);
	const view = new DataView(body.buffer);
	view.setUint16(33, featureCount, true);
	view.setUint16(35, schemaVersion, true);
	return body;
}

function mockFetch(response) {
	globalThis.fetch = async (url, init) => {
		calls.push({ url, init });
		return response;
	};
}

test("collect() posts the packaged bytes with contract headers and parses the reply", async () => {
	mockFetch(new Response(workerReply(), { status: 200 }));

	const result = await sdk.collect(LIGHT);

	assert.equal(calls.length, 1);
	const { url, init } = calls[0];
	assert.equal(url, INGRESS);
	assert.equal(init.method, "POST");
	assert.equal(init.headers["content-type"], "application/octet-stream");
	assert.equal(init.headers["x-fpkg-schema-version"], String(sdk.SCHEMA_VERSION));
	assert.equal(init.headers["x-fpkg-sdk-version"], sdk.SDK_VERSION);
	assert.match(init.headers["x-fpkg-integrity"], /^sha256-[0-9a-f]{64}$/);

	// The POSTed body is the package returned to the caller — not a re-encode.
	assert.equal(init.body, result.bytes);

	// Header/body agreement: same package id, same signal count.
	assert.equal(init.headers["x-fpkg-package-id"], sdk.toHex(result.packageId));
	assert.equal(init.headers["x-fpkg-package-id"].length, 32);

	const body = result.bytes;
	assert.equal(new TextDecoder().decode(body.subarray(0, 4)), sdk.MAGIC);
	const view = new DataView(body.buffer, body.byteOffset, body.byteLength);
	assert.equal(view.getUint16(4, true), sdk.SCHEMA_VERSION);
	const sdkLen = view.getUint16(6, true);
	const packageIdOffset = 8 + sdkLen + 8; // magic+schema+sdklen | sdk | collected_at
	assert.deepEqual(body.subarray(packageIdOffset, packageIdOffset + 16), result.packageId);
	assert.equal(view.getUint16(packageIdOffset + 16, true), result.signalCount);

	// Transport outcome + relayed reply.
	assert.equal(result.sent, true);
	assert.equal(result.status, 200);
	assert.equal(result.reply.status, 0);
	assert.equal(
		result.reply.digestHex,
		Array.from({ length: 32 }, (_, i) => i.toString(16).padStart(2, "0")).join(""),
	);
	assert.equal(result.reply.featureCount, 42);
	assert.equal(result.reply.schemaVersion, 2);
});

test("collect() keeps sent=true when the worker rejects the package", async () => {
	mockFetch(new Response(workerReply({ status: 5 }), { status: 200 }));

	const result = await sdk.collect(LIGHT);

	assert.equal(result.sent, true);
	assert.equal(result.status, 200);
	assert.equal(result.reply.status, 5);
	assert.equal(result.reply.digestHex, undefined);
});

test("collect() reports a non-2xx ingress response with its parsed reply", async () => {
	mockFetch(new Response(workerReply({ status: 5 }), { status: 503 }));

	const result = await sdk.collect(LIGHT);

	assert.equal(result.sent, false);
	assert.equal(result.status, 503);
	assert.equal(result.reply.status, 5);
	assert.equal(result.error, undefined);
});

test("collect() resolves (does not throw) when fetch rejects", async () => {
	globalThis.fetch = async () => {
		throw new Error("connection reset");
	};

	const result = await sdk.collect(LIGHT);

	assert.equal(result.sent, false);
	assert.equal(result.status, 0);
	assert.equal(result.error, "connection reset");
	assert.equal(result.reply, undefined);
});

test("packageSignals() emits a body collect() can POST unchanged", async () => {
	const pkg = await sdk.packageSignals(LIGHT);
	let posted;
	globalThis.fetch = async (_url, init) => {
		posted = init.body;
		return new Response(workerReply(), { status: 202 });
	};

	const result = await sdk.collect(LIGHT);

	// Same wire shape from both entry points (ids/timestamps differ per call).
	assert.equal(posted, result.bytes);
	assert.equal(sdk.toHex(result.bytes.subarray(0, 4)), sdk.toHex(pkg.bytes.subarray(0, 4)));
	assert.equal(new DataView(result.bytes.buffer).getUint16(4, true), sdk.SCHEMA_VERSION);
});
