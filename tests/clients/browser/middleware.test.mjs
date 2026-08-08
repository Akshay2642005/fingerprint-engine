// DecisionGate unit tests (D17): last-known-decision cache and
// session.blocked callback fan-out. Purely client-side UX gate — the app
// enforces server-side.
import { test } from "node:test";
import assert from "node:assert/strict";
import { DecisionGate } from "../../../src/clients/browser/dist/middleware.js";

test("default decision is allowed", () => {
	const gate = new DecisionGate();
	assert.deepEqual(gate.assertAllowed(), { blocked: false });
});

test("update records the decision and notifies listeners", () => {
	const gate = new DecisionGate();
	const seen = [];
	const unsubscribe = gate.onSessionBlocked((d) => seen.push(d));

	gate.update({ blocked: true, reason: "too many sessions", expiresAt: 1000 });

	assert.equal(gate.assertAllowed().blocked, true);
	assert.equal(gate.assertAllowed().reason, "too many sessions");
	assert.equal(gate.assertAllowed().expiresAt, 1000);
	assert.deepEqual(seen, [{ blocked: true, reason: "too many sessions", expiresAt: 1000 }]);

	unsubscribe();
	gate.update({ blocked: false });
	assert.equal(seen.length, 1, "unsubscribed listeners are not called");
});

test("allow-after-block overwrites the last-known decision", () => {
	const gate = new DecisionGate();
	gate.update({ blocked: true });
	gate.update({ blocked: false });
	assert.equal(gate.assertAllowed().blocked, false);
});
