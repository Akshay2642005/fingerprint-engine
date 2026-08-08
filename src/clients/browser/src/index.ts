/**
 * Fingerprint Engine — Browser SDK (D14).
 *
 * The browser never computes the canonical fingerprint. It collects
 * browser signals, serializes them into a versioned SignalPackage v2 body
 * (package.ts), and POSTs them to the configured ingress (transport.ts).
 * Workers validate, normalize, hash, score entropy/risk, and publish events
 * to the fraud platform; the SDK surfaces the last-known decision via
 * assertAllowed()/onSessionBlocked() (D17).
 */

import { collectSignals } from "./collectors/index.js";
import { encodeSignalPackage, newPackageId, toHex, MAGIC, SCHEMA_VERSION } from "./package.js";
import { sendPackage, connectDecisionSocket } from "./transport.js";
import { DecisionGate } from "./middleware.js";
import { SDK_VERSION, DEFAULT_INGRESS_URL } from "./generated/config.js";
import { FeatureID, FeatureType } from "./generated/tables.js";
import type { BlockDecision, CollectOptions, CollectResult, SdkConfig } from "./types.js";

/** Current runtime configuration (overridable via configure()). */
let config: SdkConfig = { ingressUrl: DEFAULT_INGRESS_URL };

/** Last-known-decision gate used by assertAllowed()/onSessionBlocked(). */
const gate = new DecisionGate();

let wsDisconnect: (() => void) | undefined;

/**
 * Configures the SDK. Must be called before collect() when a custom
 * ingress URL is required (the build-time default comes from
 * `--ingress-url` / `FINGERPRINT_INGRESS_URL`).
 */
export function configure(options: Partial<SdkConfig>): void {
	config = { ...config, ...options };
	if (config.wsUrl) {
		wsDisconnect = connectDecisionSocket(config, (decision: BlockDecision) => {
			gate.update(decision);
		});
	}
}

/**
 * Collects signals, serializes the SignalPackage v2 body, and POSTs it to
 * the ingress. Never computes a fingerprint — the reply, when present,
 * carries the worker's canonical digest.
 */
export async function collect(options: CollectOptions = {}): Promise<CollectResult> {
	const signals = await collectSignals(options);
	const packageId = newPackageId();
	const bytes = encodeSignalPackage(signals, {
		sdkVersion: SDK_VERSION,
		collectedAt: Date.now(),
		packageId,
	});
	const sent = await sendPackage(bytes, config, {
		schemaVersion: SCHEMA_VERSION,
		sdkVersion: SDK_VERSION,
		packageId,
	});
	return {
		packageId,
		bytes,
		hex: toHex(bytes),
		signalCount: signals.length,
		sent: sent.ok,
		reply: sent.reply,
	};
}

/** All known feature ids (numeric). */
export function getFeatureIDs(): FeatureID[] {
	return Object.values(FeatureID).filter(
		(v): v is FeatureID => typeof v === "number",
	);
}

/** Last-known decision; blocked === true means the session was flagged. */
export function assertAllowed(): BlockDecision {
	return gate.assertAllowed();
}

/** Registers a session.blocked callback; returns an unsubscribe function. */
export function onSessionBlocked(
	callback: (decision: BlockDecision) => void,
): () => void {
	return gate.onSessionBlocked(callback);
}

export { FeatureID, FeatureType, MAGIC, SCHEMA_VERSION, SDK_VERSION };
export { encodeSignalPackage, newPackageId, toHex } from "./package.js";
export { sendPackage, connectDecisionSocket } from "./transport.js";
export { DecisionGate } from "./middleware.js";
export type {
	Signal,
	SignalValue,
	CollectOptions,
	CollectResult,
	SendResult,
	SdkConfig,
	BlockDecision,
	WorkerReply,
} from "./types.js";

export default { configure, collect, assertAllowed, onSessionBlocked, getFeatureIDs };
