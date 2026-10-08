// Layer 1 — static codec regression (W3-D3, m6-golden-digest-ci).
//
// Replays each committed browser snapshot through the SDK serializer
// (encodeSignalPackage, deep-imported from dist/) and hashes the result
// with the engine's in-process hash op via `zig build scripts -- hash`,
// then asserts the digest equals that engine's pin in pins.json.
//
// No browsers needed — this is the Layer 1 half of the two-layer golden
// contract (specs/quality/browser-matrix-design.md).
//
// Usage: node hash-verify.mjs [--check]        assert vs pins.json (default)
//                             [--print]        print digests for capture
//                             [--snapshots=dir] input dir (default: committed fixtures)
//                             [--live]         Layer 2 mode: mismatches are
//                                              warnings while pins.json is
//                                              provisional, gating once CI
//                                              capture marks it authoritative
//                             [--engines=...]
import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, "..", "..");
const distDir = join(repoRoot, "src", "clients", "browser", "dist");
const fixturesDir = join(repoRoot, "tests", "fixtures", "browser");
const pinsPath = join(fixturesDir, "pins.json");
const ENGINES = ["chromium", "firefox", "webkit"];

function parseArgs(argv) {
	const opts = { check: false, print: false, engines: ENGINES, snapshots: null, live: false };
	for (const arg of argv) {
		if (arg === "--check") opts.check = true;
		else if (arg === "--print") opts.print = true;
		else if (arg === "--live") opts.live = true;
		else if (arg.startsWith("--snapshots=")) opts.snapshots = arg.slice("--snapshots=".length);
		else if (arg.startsWith("--engines=")) {
			opts.engines = arg.slice("--engines=".length).split(",").filter((e) => ENGINES.includes(e));
		}
	}
	if (!opts.check && !opts.print) opts.check = true;
	return opts;
}

function hexToBytes(hex) {
	return new Uint8Array(hex.match(/../g).map((b) => parseInt(b, 16)));
}

// Snapshot -> Signal[] as the serializer wants them: numeric FeatureType,
// byte payloads hex-decoded. Mirrors tests/clients/browser/package_parity.
async function loadSignals(snapshot) {
	const { FeatureType } = await import(`file://${distDir}/generated/tables.js`);
	return snapshot.signals.map((s) => ({
		id: s.id,
		type: FeatureType[s.type],
		value: s.type === "Bytes" ? hexToBytes(s.value)
			: s.type === "BytesArray" ? s.value.map(hexToBytes)
			: s.value,
	}));
}

async function digestFor(engine, snapshotsDir) {
	const path = join(snapshotsDir, `${engine}.signals.json`);
	if (!existsSync(path)) throw new Error(`missing snapshot: ${path}`);
	const snapshot = JSON.parse(readFileSync(path, "utf8"));
	const { encodeSignalPackage } = await import(`file://${distDir}/package.js`);
	const signals = await loadSignals(snapshot);
	const bytes = encodeSignalPackage(signals, {
		sdkVersion: snapshot.sdk_version,
		collectedAt: snapshot.collected_at,
		packageId: hexToBytes(snapshot.package_id),
	});

	const { writeFileSync, mkdtempSync, rmSync } = await import("node:fs");
	const { tmpdir } = await import("node:os");
	const dir = mkdtempSync(join(tmpdir(), "fp-hash-"));
	const bin = join(dir, `${engine}.bin`);
	try {
		writeFileSync(bin, Buffer.from(bytes));
		const out = execFileSync("zig", ["build", "scripts", "--", "hash", bin], {
			cwd: repoRoot,
			encoding: "utf8",
		});
		const m = out.match(/^digest: ([0-9a-f]{64})$/m);
		if (!m) throw new Error(`unexpected hash output:\n${out}`);
		return { digest: m[1], signalCount: snapshot.signals.length };
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

async function main() {
	const opts = parseArgs(process.argv.slice(2));
	const snapshotsDir = opts.snapshots || fixturesDir;
	const results = {};
	let failed = false;

	for (const engine of opts.engines) {
		const { digest, signalCount } = await digestFor(engine, snapshotsDir);
		results[engine] = { digest, signal_count: signalCount };
		console.log(`${engine}: ${digest} (${signalCount} signals)`);
	}

	if (opts.print) {
		// Capture flow consumes this to write pins.json.
		console.log("PIN_JSON " + JSON.stringify(results));
	}

	if (opts.check) {
		if (!existsSync(pinsPath)) {
			console.log("pins.json not found — capture pending (run golden-capture workflow)");
			process.exitCode = 0;
			return;
		}
		const pins = JSON.parse(readFileSync(pinsPath, "utf8"));
		// Layer 2 (--live) collects on a different machine than the pin
		// capture while pins are provisional (local macOS vs CI image) —
		// mismatches are reported, not fatal, until the golden-capture
		// workflow marks pins authoritative. Layer 1 (static replay of the
		// committed snapshots) always gates: it is self-consistent by
		// construction on any machine.
		const lenient = opts.live && pins.provisional === true;
		for (const [engine, got] of Object.entries(results)) {
			const pin = pins.engines?.[engine];
			if (!pin) {
				if (lenient) {
					console.warn(`warn ${engine}: no pin in pins.json (provisional)`);
					continue;
				}
				console.error(`FAIL ${engine}: no pin in pins.json`);
				failed = true;
				continue;
			}
			if (pin.digest === got.digest) {
				console.log(`ok   ${engine}: digest matches pin`);
			} else if (lenient) {
				console.warn(`warn ${engine}: digest ${got.digest} != provisional pin ${pin.digest} (informational until capture)`);
			} else {
				console.error(`FAIL ${engine}: digest ${got.digest} != pin ${pin.digest}`);
				failed = true;
			}
			if (pin.signal_count !== undefined && pin.signal_count !== got.signal_count) {
				const line = `warn ${engine}: signal_count ${got.signal_count} != pin ${pin.signal_count}`;
				if (lenient) console.warn(line); else { console.error("FAIL " + line); failed = true; }
			}
		}
		if (pins.provisional) {
			console.warn("note: pins.json is provisional (local capture) — run golden-capture for authoritative pins");
		}
	}

	if (failed) process.exitCode = 1;
}

await main();
