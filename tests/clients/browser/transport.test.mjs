// Transport tests (D16/D17): worker-reply parsing and the ingress POST leg
// with mocked fetch. Requires dist/ to be built first (`zig build
// clients:browser`), like the other tests in this directory.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
	parseWorkerReply,
	sendPackage,
} from "../../../src/clients/browser/dist/transport.js";

test("parseWorkerReply: status-only reply", () => {
	assert.deepEqual(parseWorkerReply(new Uint8Array([7])), { status: 7 });
});

test("parseWorkerReply: empty body yields undefined", () => {
	assert.equal(parseWorkerReply(new Uint8Array(0)), undefined);
});

test("parseWorkerReply: ok reply carries digest, schema, feature count", () => {
	const body = new Uint8Array(1 + 32 + 2 + 2);
	const view = new DataView(body.buffer);
	view.setUint16(33, 3, true); // feature_count
	view.setUint16(35, 2, true); // schema_version
	const reply = parseWorkerReply(body);
	assert.equal(reply.status, 0);
	assert.equal(reply.schemaVersion, 2);
	assert.equal(reply.featureCount, 3);
	assert.match(reply.digestHex, /^[0-9a-f]{64}$/);
});

test("parseWorkerReply: layout pinned against the worker reply golden", () => {
	// Golden from src/integration_tests.zig `expectHashReply`: the worker
	// writes `status ok | sha256 digest | u16 feature_count | u16
	// schema_version` for the signal-package-v2 fixture (digest
	// db29fc13..., features=3, schema=2). If this test breaks, the SDK
	// layout drifted from the worker — fix both sides together.
	const digest = "db29fc13d8dad5dc0bd7b1f997155cff411f3da88a597619f5e0d67a251e6c75";
	const digestBytes = new Uint8Array(digest.length / 2);
	for (let i = 0; i < digestBytes.length; i += 1) {
		digestBytes[i] = Number.parseInt(digest.slice(i * 2, i * 2 + 2), 16);
	}
	const body = new Uint8Array(1 + 32 + 2 + 2);
	body.set(digestBytes, 1);
	const view = new DataView(body.buffer);
	view.setUint16(33, 3, true); // feature_count
	view.setUint16(35, 2, true); // schema_version
	const reply = parseWorkerReply(body);
	assert.equal(reply.status, 0);
	assert.equal(reply.digestHex, digest);
	assert.equal(reply.featureCount, 3);
	assert.equal(reply.schemaVersion, 2);
});

test("parseWorkerReply: truncated ok reply yields status only", () => {
	assert.deepEqual(parseWorkerReply(new Uint8Array([0, 1, 2, 3])), { status: 0 });
});

test("parseWorkerReply: a 72-byte v2 reply is read through the 36-byte v1 path", () => {
	// ADR-013 §3: `fingerprint_result` appends the stable-core triple
	// (`core_digest[32]`, `core_feature_count u16`, `core_version u16`) after
	// the untouched v1 prefix. The SDK 1.0 parse must therefore see exactly
	// the same fields as a 36-byte v1 body and ignore the trailing bytes — no
	// new public symbol, no changed value. This is the compatibility gate for
	// the append-extend.
	const digest = "db29fc13d8dad5dc0bd7b1f997155cff411f3da88a597619f5e0d67a251e6c75";
	const v1 = new Uint8Array(1 + 32 + 2 + 2);
	v1.set(
		Uint8Array.from(Buffer.from(digest, "hex")),
		1,
	);
	new DataView(v1.buffer).setUint16(33, 3, true); // feature_count
	new DataView(v1.buffer).setUint16(35, 2, true); // schema_version

	const v2 = new Uint8Array(v1.byteLength + 32 + 2 + 2);
	v2.set(v1);
	v2.fill(0xab, v1.byteLength, v1.byteLength + 32); // core_digest
	new DataView(v2.buffer).setUint16(v1.byteLength + 32, 23, true); // core_feature_count
	new DataView(v2.buffer).setUint16(v1.byteLength + 34, 1, true); // core_version

	assert.deepEqual(parseWorkerReply(v2), parseWorkerReply(v1));
	assert.deepEqual(parseWorkerReply(v2), {
		status: 0,
		digestHex: digest,
		featureCount: 3,
		schemaVersion: 2,
	});
	// The core triple is engine metadata for the ledger, not part of the SDK
	// surface: it must not leak into the parsed reply.
	assert.equal("coreDigestHex" in parseWorkerReply(v2), false);
});

test("parseWorkerReply: trailing bytes beyond a v2 reply are ignored", () => {
	// Forward compatibility: a future append-extend may lengthen the result
	// again. The SDK's contract is "gate on at least the v1 length, ignore the
	// rest", so an unknown tail must not change or break parsing.
	const body = new Uint8Array(1 + 32 + 2 + 2 + 12);
	new DataView(body.buffer).setUint16(33, 5, true);
	new DataView(body.buffer).setUint16(35, 2, true);
	body.fill(0xcd, 37);
	const reply = parseWorkerReply(body);
	assert.equal(reply.status, 0);
	assert.equal(reply.featureCount, 5);
	assert.equal(reply.schemaVersion, 2);
	assert.match(reply.digestHex, /^[0-9a-f]{64}$/);
});

test("sendPackage: posts raw body with headers and parses the reply", async () => {
	const originalFetch = globalThis.fetch;
	try {
		let captured;
		globalThis.fetch = async (url, init) => {
			captured = { url, init };
			return new Response(new Uint8Array(1 + 32 + 2 + 2), { status: 200 });
		};

		const result = await sendPackage(
			new Uint8Array([1, 2, 3]),
			{ ingressUrl: "https://ingress.test/v1/fingerprints" },
			{
				schemaVersion: 2,
				sdkVersion: "0.2.0",
				packageId: new Uint8Array(16),
			},
		);

		assert.equal(result.ok, true);
		assert.equal(result.status, 200);
		assert.equal(result.reply.status, 0);
		assert.equal(captured.url, "https://ingress.test/v1/fingerprints");
		assert.equal(captured.init.headers["content-type"], "application/octet-stream");
		assert.equal(captured.init.headers["x-fpkg-schema-version"], "2");
		assert.equal(captured.init.headers["x-fpkg-sdk-version"], "0.2.0");
		assert.equal(
			captured.init.headers["x-fpkg-package-id"],
			"00000000000000000000000000000000",
		);
		assert.match(captured.init.headers["x-fpkg-integrity"], /^sha256-[0-9a-f]{64}$/);
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test("sendPackage: network failure is reported, not thrown", async () => {
	const originalFetch = globalThis.fetch;
	try {
		globalThis.fetch = async () => {
			throw new TypeError("ECONNREFUSED");
		};
		const result = await sendPackage(
			new Uint8Array(0),
			{ ingressUrl: "https://ingress.test" },
			{
				schemaVersion: 2,
				sdkVersion: "0.2.0",
				packageId: new Uint8Array(16),
			},
		);
		assert.equal(result.ok, false);
		assert.equal(result.status, 0);
		assert.equal(result.error, "ECONNREFUSED");
		assert.equal(result.reply, undefined);
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test("sendPackage: non-binary reply is tolerated", async () => {
	const originalFetch = globalThis.fetch;
	try {
		globalThis.fetch = async () => new Response("", { status: 502 });
		const result = await sendPackage(
			new Uint8Array([1]),
			{ ingressUrl: "https://ingress.test" },
			{
				schemaVersion: 2,
				sdkVersion: "0.2.0",
				packageId: new Uint8Array(16),
			},
		);
		assert.equal(result.ok, false);
		assert.equal(result.status, 502);
		assert.equal(result.reply, undefined);
	} finally {
		globalThis.fetch = originalFetch;
	}
});
