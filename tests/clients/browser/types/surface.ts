/**
 * Type-level public API contract (W4-D3).
 *
 * Compiled with `tsc --noEmit` against the built `dist/index.d.ts`. Any
 * signature change, required-field change, or symbol removal on the frozen
 * 1.0 surface fails this file. `@ts-expect-error` lines are negative contracts:
 * if the error disappears (e.g. a field is added), the test fails too.
 *
 * Run: npm run test:types (from src/clients/browser, after a build).
 *
 * story: m6-sdk-contract-tests
 */

import sdk, {
	configure,
	packageSignals,
	collect,
	assertAllowed,
	onSessionBlocked,
	getFeatureIDs,
	encodeSignalPackage,
	newPackageId,
	toHex,
	sendPackage,
	connectDecisionSocket,
	DecisionGate,
	FeatureID,
	FeatureType,
	MAGIC,
	SCHEMA_VERSION,
	SDK_VERSION,
} from "../../../../src/clients/browser/dist/index.js";
import type {
	Signal,
	SignalValue,
	CollectOptions,
	PackageResult,
	CollectResult,
	SendResult,
	SdkConfig,
	BlockDecision,
	WorkerReply,
} from "../../../../src/clients/browser/dist/index.js";

// ── Exact signatures ────────────────────────────────────────────────────────

const _configure: (options: Partial<SdkConfig>) => void = configure;
const _package: (options?: CollectOptions) => Promise<PackageResult> = packageSignals;
const _collect: (options?: CollectOptions) => Promise<CollectResult> = collect;
const _assertAllowed: () => BlockDecision = assertAllowed;
const _onSessionBlocked: (cb: (d: BlockDecision) => void) => () => void = onSessionBlocked;
const _getFeatureIDs: () => FeatureID[] = getFeatureIDs;

const _encode: (signals: Signal[], opts: {
	sdkVersion: string;
	collectedAt: number;
	packageId: Uint8Array;
}) => Uint8Array = encodeSignalPackage;
const _newPackageId: () => Uint8Array = newPackageId;
const _toHex: (bytes: Uint8Array) => string = toHex;
const _sendPackage: (
	bytes: Uint8Array,
	config: SdkConfig,
	headers: { schemaVersion: number; sdkVersion: string; packageId: Uint8Array },
) => Promise<SendResult> = sendPackage;
const _connect: (config: SdkConfig, cb: (d: BlockDecision) => void) => () => void =
	connectDecisionSocket;

// ── Default export mirrors the ergonomic surface ─────────────────────────────

const _dConfigure: typeof configure = sdk.configure;
const _dPackage: typeof packageSignals = sdk.packageSignals;
const _dCollect: typeof collect = sdk.collect;
const _dAssert: typeof assertAllowed = sdk.assertAllowed;
const _dOnBlocked: typeof onSessionBlocked = sdk.onSessionBlocked;
const _dFeatureIds: typeof getFeatureIDs = sdk.getFeatureIDs;

// ── Constants ───────────────────────────────────────────────────────────────

const _magic: "FNGR" = MAGIC;
const _schema: 2 = SCHEMA_VERSION;
const _sdkVersion: string = SDK_VERSION;

// ── Result shapes ───────────────────────────────────────────────────────────

declare const pkg: PackageResult;
const _packageId: Uint8Array = pkg.packageId;
const _bytes: Uint8Array = pkg.bytes;
const _hex: string = pkg.hex;
const _signalCount: number = pkg.signalCount;

// @ts-expect-error PackageResult has no transport outcome
pkg.sent;

declare const result: CollectResult;
const _resultIsPackage: PackageResult = result;
const _sent: boolean = result.sent;
const _status: number | undefined = result.status;
const _error: string | undefined = result.error;
const _reply: WorkerReply | undefined = result.reply;

// @ts-expect-error CollectResult does not expose the raw Signal[]
result.signals;

// @ts-expect-error `sent` is required on CollectResult
const _missingSent: CollectResult = {
	packageId: new Uint8Array(16),
	bytes: new Uint8Array(),
	hex: "",
	signalCount: 0,
};

declare const send: SendResult;
const _sendOk: boolean = send.ok;
const _sendStatus: number = send.status;

// ── Signals / options / decisions ───────────────────────────────────────────

const _signal: Signal = { id: FeatureID.UserAgent, type: FeatureType.String, value: "x" };
const _value: SignalValue = ["a", "b"];
const _options: CollectOptions = { enableCanvas: false, enableFonts: false };

// @ts-expect-error unknown collector group
const _badOptions: CollectOptions = { enableTelepathy: true };

const _config: SdkConfig = { ingressUrl: "https://example.test", sessionId: "s1" };

const gate = new DecisionGate();
const _decision: BlockDecision = gate.assertAllowed();
const _unsubscribe: () => void = gate.onSessionBlocked((d: BlockDecision) => {
	const _blocked: boolean = d.blocked;
});

// Keep the compiler from flagging the assertions as unused under stricter
// consumer tsconfigs; this file is only ever compiled with `noEmit`.
void [
	_configure, _package, _collect, _assertAllowed, _onSessionBlocked,
	_getFeatureIDs, _encode, _newPackageId, _toHex, _sendPackage, _connect,
	_dConfigure, _dPackage, _dCollect, _dAssert, _dOnBlocked, _dFeatureIds,
	_magic, _schema, _sdkVersion, _packageId, _bytes, _hex, _signalCount,
	_resultIsPackage, _sent, _status, _error, _reply, _missingSent,
	_sendOk, _sendStatus, _signal, _value, _options, _badOptions, _config,
	_decision, _unsubscribe,
];
