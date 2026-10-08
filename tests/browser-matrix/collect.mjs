// Cross-browser golden matrix runner (W3-D2, m6-browser-runner).
//
// Launches Playwright x Chromium-family/Firefox/WebKit headless with a
// fixed context (viewport 1280x720, locale en-US, timezone UTC; screen/outer
// dims pinned to the viewport via init script because Firefox otherwise
// reports the host display), collects real signals via the SDK
// deep-imported from dist/, and writes one snapshot JSON per engine
// mirroring tests/fixtures/fingerprints/signal-package-v2.signals.json.
//
// The Chromium-family slot runs the locally installed BRAVE browser via
// executablePath (policy: no Chrome/Chromium downloads — `npx playwright
// install chromium` is intentionally never run). Brave is Chromium-based,
// so it exercises the same engine class; set FP_BRAVE=/path/to/brave to
// override the auto-detected executable.
//
// Snapshots committed here are PROVISIONAL: local macOS runs are
// informational only (fonts/GPU differ from the pinned CI image). D3's
// workflow_dispatch capture flow re-captures snapshots+pins in CI as the
// source of truth (specs/quality/browser-matrix-design.md).
//
// Local runs write to tests/browser-matrix/captures/ (git-ignored) by
// default so merely running the collector never overwrites the committed
// goldens. Promote to fixtures explicitly:
//   node collect.mjs --out=tests/fixtures/browser
//
// Usage: node collect.mjs [--engines=chromium,firefox,webkit]
//                          [--repeats=3] [--out=<dir>] [--strict]
import { createServer } from "node:http";
import { readFileSync, writeFileSync, mkdirSync, existsSync, statSync, accessSync } from "node:fs";
import { join, dirname, extname, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { chromium, firefox, webkit } from "playwright";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, "..", "..");
const distDir = join(repoRoot, "src", "clients", "browser", "dist");

// Chromium-family engine = the locally installed Brave (never Chrome).
// Override with FP_BRAVE=/path/to/brave.
function resolveBrave() {
	const candidates = [
		process.env.FP_BRAVE,
		"/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
		"/usr/bin/brave-browser",
		"/opt/brave.com/brave/brave-browser",
	].filter(Boolean);
	for (const p of candidates) {
		try {
			accessSync(p);
			return p;
		} catch { /* try next */ }
	}
	throw new Error(
		"Brave browser not found — install Brave or set FP_BRAVE=/path/to/brave " +
		"(this runner never uses Chrome/Chromium)",
	);
}

const ENGINES = {
	// `chromium` stays the engine-class key (snapshot/pin filename);
	// the executable is Brave, resolved lazily in collectOnce.
	// Brave randomizes canvas/audio/hardwareConcurrency per SESSION, but a
	// persistent profile seeds deterministically — so the Chromium slot
	// reuses tests/browser-matrix/.profiles/chromium/ (git-ignored).
	chromium: { type: chromium, isBrave: true, persistent: true },
	firefox: { type: firefox, isBrave: false, persistent: false },
	webkit: { type: webkit, isBrave: false, persistent: false },
};

// Fixed context — locale/timezone baked into snapshots (D2 default).
// Screen/outer dims are pinned to the viewport via PIN_SCREEN_SCRIPT:
// Playwright's viewport fixes innerWidth/innerHeight only, and Firefox
// reports the host display for screen.* (1366x768 on the author's machine),
// so display changes would otherwise alter golden signals.
const VIEWPORT = { width: 1280, height: 720 };
const CONTEXT_OPTS = {
	viewport: VIEWPORT,
	deviceScaleFactor: 1,
	locale: "en-US",
	timezoneId: "UTC",
};

// Runs before page scripts on every navigation. Best-effort: if a property
// refuses redefinition in some engine, collection still proceeds with real
// values (and the N-repeat report shows it).
const PIN_SCREEN_SCRIPT = `(() => {
	try {
		const w = ${VIEWPORT.width}, h = ${VIEWPORT.height};
		const pin = (obj, props) => {
			for (const [k, v] of Object.entries(props)) {
				try {
					Object.defineProperty(obj, k, { get: () => v, configurable: true });
				} catch { /* keep host value */ }
			}
		};
		pin(window.screen, {
			width: w, height: h, availWidth: w, availHeight: h,
			colorDepth: 24, pixelDepth: 24,
		});
		if (window.screen.orientation) {
			pin(window.screen.orientation, { type: "landscape-primary", angle: 0 });
		}
		pin(window, { outerWidth: w, outerHeight: h });
	} catch { /* keep host values */ }
})();`;

// Committed snapshots use fixed replay identity — the digest covers only
// the canonicalized feature buffer, so this never affects pins (W2-D5).
const FIXED_COLLECTED_AT = 1700000000123;
const FIXED_PACKAGE_ID = "0102030405060708090a0b0c0d0e0f10";

function parseArgs(argv) {
	const opts = { engines: Object.keys(ENGINES), repeats: 3, out: null, strict: false };
	for (const arg of argv) {
		if (arg.startsWith("--engines=")) {
			opts.engines = arg.slice("--engines=".length).split(",").filter((e) => e in ENGINES);
		} else if (arg.startsWith("--repeats=")) {
			opts.repeats = Math.max(1, parseInt(arg.slice("--repeats=".length), 10) || 1);
		} else if (arg.startsWith("--out=")) {
			opts.out = arg.slice("--out=".length);
		} else if (arg === "--strict") {
			opts.strict = true;
		}
	}
	if (opts.engines.length === 0) throw new Error("no valid engines requested");
	return opts;
}

function contentType(path) {
	switch (extname(path)) {
		case ".js": return "text/javascript";
		case ".html": return "text/html";
		case ".json": return "application/json";
		case ".d.ts": return "text/plain";
		default: return "application/octet-stream";
	}
}

// Minimal static server: / serves the harness, /dist/* serves the built
// SDK. Fails fast if dist/ is missing (run `zig build clients:browser`).
// FIXED port: Brave seeds per-origin state (shields settings, randomization
// seed) — a stable origin keeps the Chromium slot reproducible across runs.
const FIXED_PORT = 38917;
function startServer() {
	if (!existsSync(join(distDir, "collectors", "index.js"))) {
		throw new Error(`dist/ not built — run \`zig build clients:browser\` from the repo root (looked in ${distDir})`);
	}
	const harness = readFileSync(join(here, "harness.html"));
	const server = createServer((req, res) => {
		const url = new URL(req.url || "/", "http://localhost");
		if (url.pathname === "/" || url.pathname === "/harness.html") {
			res.writeHead(200, { "content-type": "text/html" }).end(harness);
			return;
		}
		if (url.pathname.startsWith("/dist/")) {
			const file = join(distDir, url.pathname.slice("/dist/".length));
			// Boundary-safe containment: a raw prefix check accepts
			// siblings like dist-evil/, so compare the relative path.
			const rel = relative(distDir, file);
			let isFile = false;
			try {
				isFile = statSync(file).isFile();
			} catch { /* missing — 404 below */ }
			if (rel === "" || rel.startsWith("..") || !isFile) {
				res.writeHead(404).end("not found");
				return;
			}
			res.writeHead(200, { "content-type": contentType(file) }).end(readFileSync(file));
			return;
		}
		res.writeHead(404).end("not found");
	});
	return new Promise((resolve, reject) => {
		server.once("error", reject);
		server.listen(FIXED_PORT, "127.0.0.1", () => resolve(server));
	});
}

function signalKey(s) {
	return `${s.id}:${s.type}:${JSON.stringify(s.value)}`;
}

// Deep-compare repeats 2..N against run 1; returns per-signal diff lines.
// Informational only unless --strict (D4 triages whatever shows up here).
function diffRepeats(runs) {
	const base = new Map(runs[0].map((s) => [s.id, s]));
	const lines = [];
	for (let i = 1; i < runs.length; i++) {
		const cur = new Map(runs[i].map((s) => [s.id, s]));
		const ids = new Set([...base.keys(), ...cur.keys()]);
		for (const id of [...ids].sort((a, b) => a - b)) {
			const a = base.get(id);
			const b = cur.get(id);
			if (!a) lines.push(`  run${i + 1}: signal id=${id} APPEARED (absent in run 1)`);
			else if (!b) lines.push(`  run${i + 1}: signal id=${id} (${a.type}) MISSING (present in run 1)`);
			else if (signalKey(a) !== signalKey(b)) {
				lines.push(`  run${i + 1}: signal id=${id} (${a.type}) differs:`);
				lines.push(`    run1: ${JSON.stringify(a.value)?.slice(0, 160)}`);
				lines.push(`    run${i + 1}: ${JSON.stringify(b.value)?.slice(0, 160)}`);
			}
		}
	}
	return lines;
}

// Brave seeds FP randomization per session for http origins, which made
// HardwareConcurrency/deviceMemory/CanvasHash/AudioHash drift every run
// (probed: data: URLs are stable, real origins are not). The one pref that
// pins it: brave.profile.managed_default_content_settings.
// brave_fingerprinting_v2 = 1 ("allow" — no randomization), verified 3/3
// identical launches. Applied once to the persistent profile below.
function seedBraveProfile(profileDir) {
	const prefsPath = join(profileDir, "Default", "Preferences");
	if (!existsSync(profileDir)) mkdirSync(profileDir, { recursive: true });
	if (!existsSync(prefsPath)) {
		// First run: let Brave create the profile, then patch on next call.
		return;
	}
	const prefs = JSON.parse(readFileSync(prefsPath, "utf8"));
	prefs.brave ??= {};
	prefs.brave.profile ??= {};
	prefs.brave.profile.managed_default_content_settings ??= {};
	const cds = prefs.brave.profile.managed_default_content_settings;
	if (cds.brave_fingerprinting_v2 === 1) return;
	cds.brave_fingerprinting_v2 = 1;
	writeFileSync(prefsPath, JSON.stringify(prefs));
}

async function collectOnce(engine, port) {
	if (engine.persistent) {
		// Brave: persistent profile (see ENGINES comment) — randomization
		// seed is stable per profile, unlike a throwaway context.
		const profileDir = join(here, ".profiles", "chromium");
		mkdirSync(profileDir, { recursive: true });
		if (!existsSync(join(profileDir, "Default", "Preferences"))) {
			// First run: bootstrap the profile so the FP pref can be
			// patched before any real collection.
			const boot = await engine.type.launchPersistentContext(profileDir, {
				executablePath: resolveBrave(),
				headless: true,
				...CONTEXT_OPTS,
			});
			await boot.close();
		}
		seedBraveProfile(profileDir);
		const context = await engine.type.launchPersistentContext(profileDir, {
			executablePath: resolveBrave(),
			headless: true,
			...CONTEXT_OPTS,
		});
		try {
			const version = braveVersion();
			await context.addInitScript({ content: PIN_SCREEN_SCRIPT });
			const page = context.pages()[0] ?? await context.newPage();
			await page.goto(`http://127.0.0.1:${port}/harness.html`);
			await page.waitForFunction(() => window.__fpReady === true, null, { timeout: 60000 });
			const err = await page.evaluate(() => window.__fpError);
			if (err) throw new Error(`in-page collection failed: ${err}`);
			const signals = await page.evaluate(() => window.__fpSignals);
			return { signals, version };
		} finally {
			await context.close();
		}
	}

	const browser = await engine.type.launch();
	try {
		const version = browser.version();
		const context = await browser.newContext(CONTEXT_OPTS);
		await context.addInitScript({ content: PIN_SCREEN_SCRIPT });
		const page = await context.newPage();
		await page.goto(`http://127.0.0.1:${port}/harness.html`);
		await page.waitForFunction(() => window.__fpReady === true, null, { timeout: 60000 });
		const err = await page.evaluate(() => window.__fpError);
		if (err) throw new Error(`in-page collection failed: ${err}`);
		const signals = await page.evaluate(() => window.__fpSignals);
		await context.close();
		return { signals, version };
	} finally {
		await browser.close();
	}
}

// Brave version for provenance (persistent contexts don't expose
// browser.version()).
function braveVersion() {
	try {
		const out = execFileSync(resolveBrave(), ["--version"], { encoding: "utf8" });
		return out.trim().replace(/^Brave Browser\s+/, "brave-");
	} catch {
		return "brave-unknown";
	}
}

async function main() {
	const opts = parseArgs(process.argv.slice(2));

	// Numeric FeatureType -> name reverse map (snapshot schema uses the
	// readable names, like signal-package-v2.signals.json).
	const { FeatureType } = await import(`file://${distDir}/generated/tables.js`);
	const typeName = Object.fromEntries(Object.entries(FeatureType).map(([k, v]) => [v, k]));

	// sdk_version tracks the real package version (deterministic per commit).
	const sdkVersion = JSON.parse(readFileSync(join(repoRoot, "src", "clients", "browser", "package.json"), "utf8")).version;

	// Default out is the git-ignored local captures dir: running the
	// collector must never silently overwrite the committed goldens.
	// Pass --out=tests/fixtures/browser to promote a run to fixtures.
	const outDir = opts.out || join(here, "captures");
	mkdirSync(outDir, { recursive: true });

	const server = await startServer();
	const port = server.address().port;
	console.log(`harness server on 127.0.0.1:${port} (sdk ${sdkVersion})`);

	let volatile = false;
	const versions = {};
	try {
		for (const name of opts.engines) {
			const runs = [];
			let version = "";
			for (let i = 0; i < opts.repeats; i++) {
				const { signals: raw, version: v } = await collectOnce(ENGINES[name], port);
				version = v;
				runs.push(raw.map((s) => ({ id: s.id, type: typeName[s.type] ?? `UNKNOWN(${s.type})`, value: s.value })));
			}
			console.log(`${name} (${version}): ${runs[0].length} signals x ${opts.repeats} repeats`);
			versions[name] = version;

			const diffs = diffRepeats(runs);
			if (diffs.length === 0) {
				console.log(`  stable across ${opts.repeats} repeats`);
			} else {
				volatile = true;
				console.log(`  VOLATILE signals (run-to-run drift within ${name}):`);
				for (const line of diffs) console.log(line);
			}

			const snapshot = {
				schema_version: 2,
				sdk_version: sdkVersion,
				collected_at: FIXED_COLLECTED_AT,
				package_id: FIXED_PACKAGE_ID,
				signals: runs[0],
			};
			const path = join(outDir, `${name}.signals.json`);
			writeFileSync(path, JSON.stringify(snapshot, null, "\t") + "\n");
			console.log(`  wrote ${path}`);
		}
	} finally {
		server.close();
	}

	// Machine-readable provenance for the capture workflow (pins.json).
	console.log("BROWSER_VERSIONS " + JSON.stringify(versions));

	if (volatile) {
		console.log(volatile && opts.strict
			? "FAIL: volatile signals with --strict"
			: "note: volatile signals present (informational; D4 triages)");
		if (opts.strict) process.exitCode = 1;
	}
}

await main();
