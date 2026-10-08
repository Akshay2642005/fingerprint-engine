// Per-signal diff between live captures and committed snapshots (W3-D3;
// D4's raw material). Never gates by itself — drift stays visible as an
// uploaded artifact (browser-matrix-design.md, D3 fallback rule).
//
// Usage: node diff-snapshots.mjs [--live=dir] [--golden=dir] [--out=file]
import { readFileSync, existsSync, writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, "..", "..");
const ENGINES = ["chromium", "firefox", "webkit"];

const opts = { live: join(here, "captures"), golden: join(repoRoot, "tests", "fixtures", "browser"), out: null };
for (const arg of process.argv.slice(2)) {
	if (arg.startsWith("--live=")) opts.live = arg.slice("--live=".length);
	else if (arg.startsWith("--golden=")) opts.golden = arg.slice("--golden=".length);
	else if (arg.startsWith("--out=")) opts.out = arg.slice("--out=".length);
}

// Signal names for readable diffs (FeatureID table from the built SDK).
const { FeatureID } = await import(`file://${join(repoRoot, "src", "clients", "browser", "dist", "generated", "tables.js")}`);
const nameById = Object.fromEntries(Object.entries(FeatureID).map(([k, v]) => [v, k]));
const nameOf = (id) => nameById[id] ?? `id#${id}`;

function load(dir, engine) {
	const path = join(dir, `${engine}.signals.json`);
	if (!existsSync(path)) return null;
	return JSON.parse(readFileSync(path, "utf8"));
}

const lines = [];
let totalDrift = 0;

for (const engine of ENGINES) {
	const live = load(opts.live, engine);
	const golden = load(opts.golden, engine);
	if (!live || !golden) {
		lines.push(`## ${engine}: skipped (missing ${!live ? "live" : "golden"} snapshot)`);
		continue;
	}
	const liveById = new Map(live.signals.map((s) => [s.id, s]));
	const goldenById = new Map(golden.signals.map((s) => [s.id, s]));
	const drift = [];

	for (const [id, g] of goldenById) {
		const l = liveById.get(id);
		if (!l) {
			drift.push(`- ${nameOf(id)} (id ${id}): MISSING in live (golden has ${JSON.stringify(g.value)?.slice(0, 80)})`);
		} else if (JSON.stringify(l.value) !== JSON.stringify(g.value) || l.type !== g.type) {
			drift.push(`- ${nameOf(id)} (id ${id}, ${g.type}):`);
			drift.push(`    golden: ${JSON.stringify(g.value)?.slice(0, 120)}`);
			drift.push(`    live:   ${JSON.stringify(l.value)?.slice(0, 120)}`);
		}
	}
	for (const [id, l] of liveById) {
		if (!goldenById.has(id)) {
			drift.push(`- ${nameOf(id)} (id ${id}): NEW in live (not in golden) ${JSON.stringify(l.value)?.slice(0, 80)}`);
		}
	}

	totalDrift += drift.length;
	lines.push(`## ${engine}: ${drift.length === 0 ? "no drift vs committed snapshot" : `${drift.length} drifted entries`}`);
	lines.push(...drift, "");
}

const report = lines.join("\n");
console.log(report);
if (opts.out) {
	mkdirSync(dirname(opts.out), { recursive: true });
	writeFileSync(opts.out, report);
	console.log(`report written to ${opts.out}`);
}
// Informational by design — exit 0 always (the digest pin is the gate).
