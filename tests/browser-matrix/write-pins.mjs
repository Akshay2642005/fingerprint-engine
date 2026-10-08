// Writes tests/fixtures/browser/pins.json from a capture run (W3-D3,
// m6-golden-digest-ci). Consumes the machine-readable lines printed by
// collect.mjs (BROWSER_VERSIONS) and hash-verify.mjs (PIN_JSON).
//
// Usage: node write-pins.mjs '<versions-json>' '<digests-json>' [--provisional]
// Called by the golden-capture workflow with pins marked authoritative
// (default). Local test runs pass --provisional.
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, "..", "..");
const pinsPath = join(repoRoot, "tests", "fixtures", "browser", "pins.json");

const [versionsArg, digestsArg, ...flags] = process.argv.slice(2);
if (!versionsArg || !digestsArg) {
	console.error("usage: node write-pins.mjs '<versions-json>' '<digests-json>' [--provisional]");
	process.exit(1);
}
const versions = JSON.parse(versionsArg);
const digests = JSON.parse(digestsArg);
const provisional = flags.includes("--provisional");

// Existing pins carry provenance (runner image, playwright pin) that the
// capture reuses; digests/signal_counts are always replaced.
let prior = {};
try {
	prior = JSON.parse(readFileSync(pinsPath, "utf8"));
} catch { /* first capture */ }

const playwrightVersion = JSON.parse(
	readFileSync(join(here, "package.json"), "utf8"),
).devDependencies.playwright;

const engines = {};
for (const [engine, got] of Object.entries(digests)) {
	engines[engine] = {
		browser: versions[engine] ?? "unknown",
		browser_family: engine === "chromium" ? "chromium" : engine,
		digest: got.digest,
		signal_count: got.signal_count,
	};
}

const pins = {
	schema: 1,
	provisional,
	note: provisional
		? "Local capture — informational only. The golden-capture workflow (workflow_dispatch) re-captures snapshots+pins on the pinned CI image; that run is the source of truth (specs/quality/browser-matrix-design.md)."
		: "Captured on the pinned CI image — authoritative (specs/quality/browser-matrix-design.md).",
	playwright_version: playwrightVersion,
	captured_at: Date.now(),
	runner: process.env.GOLDEN_RUNNER_IMAGE || prior.runner || "local (unspecified)",
	engines,
};

writeFileSync(pinsPath, JSON.stringify(pins, null, "\t") + "\n");
console.log(`wrote ${pinsPath} (provisional=${provisional}, runner=${pins.runner})`);
