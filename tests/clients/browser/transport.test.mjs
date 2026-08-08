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
	view.setUint16(33, 2, true); // schema_version
	view.setUint16(35, 3, true); // feature_count
	const reply = parseWorkerReply(body);
	assert.equal(reply.status, 0);
	assert.equal(reply.schemaVersion, 2);
	assert.equal(reply.featureCount, 3);
	assert.match(reply.digestHex, /^[0-9a-f]{64}$/);
});

test("parseWorkerReply: truncated ok reply yields status only", () => {
	assert.deepEqual(parseWorkerReply(new Uint8Array([0, 1, 2, 3])), { status: 0 });
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
