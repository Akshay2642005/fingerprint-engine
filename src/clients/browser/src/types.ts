/**
 * Fingerprint Engine — Browser SDK type definitions (D14).
 *
 * The browser never computes a fingerprint: it collects signals, packages
 * them (package.ts), and ships the package to the ingress (transport.ts).
 * The canonical digest is produced server-side by the fingerprint workers.
 */

import type { FeatureID, FeatureType } from "./generated/tables.js";

/** Raw value carried by a collected signal, shaped by its FeatureType. */
export type SignalValue =
	| boolean
	| number
	| string
	| Uint8Array
	| string[]
	| number[];

/** One collected signal: feature id, declared type, and value. */
export interface Signal {
	id: FeatureID;
	type: FeatureType;
	value: SignalValue;
}

/** Options for the SignalPackage v2 serializer (DESIGN §5.1 / §9.4.4). */
export interface SignalPackageOptions {
	/** SDK version string (injected at build time). */
	sdkVersion: string;
	/** Client-provided collection timestamp (ms epoch) — the engine never clocks. */
	collectedAt: number;
	/** 16 bytes of replay-identity randomness for correlation. */
	packageId: Uint8Array;
}

/** Which signal groups to collect. All default to enabled. */
export interface CollectOptions {
	enableCanvas?: boolean;
	enableWebGL?: boolean;
	enableAudio?: boolean;
	enableFonts?: boolean;
	enableBattery?: boolean;
	enableMedia?: boolean;
	enableSpeech?: boolean;
	enableInput?: boolean;
	enablePermissions?: boolean;
}

/** Result of a collect() — the package that was shipped to the ingress. */
export interface CollectResult {
	/** Replay-identity bytes used as the package correlation id. */
	packageId: Uint8Array;
	/** The serialized SignalPackage v2 body (exact bytes POSTed). */
	bytes: Uint8Array;
	/** Hex of `bytes`. */
	hex: string;
	/** Number of signals in the package. */
	signalCount: number;
	/** Whether the ingress accepted the package (HTTP 2xx). */
	sent: boolean;
	/** Server-computed reply, when the ingress relayed a worker frame. */
	reply?: WorkerReply;
}

/** Worker reply relayed by the ingress (FPKG fingerprint_result payload). */
export interface WorkerReply {
	/** Engine status byte: 0 = ok, nonzero = engine Status enum value. */
	status: number;
	/** Canonical digest hex (status = 0 only). */
	digestHex?: string;
	/** Schema version of the computed package (status = 0 only). */
	schemaVersion?: number;
	/** Feature count used by the worker (status = 0 only). */
	featureCount?: number;
}

/** Result of one POST to the ingress. */
export interface SendResult {
	ok: boolean;
	status: number;
	reply?: WorkerReply;
	error?: string;
}

/** SDK runtime configuration. */
export interface SdkConfig {
	/** Ingress URL the SDK POSTs SignalPackages to (default: generated). */
	ingressUrl: string;
	/** Fraud-platform WebSocket URL for session.blocked push (optional). */
	wsUrl?: string;
	/** Session id used to correlate decisions (optional). */
	sessionId?: string;
}

/** Last-known decision for a session (D17 — UX gate; app enforces). */
export interface BlockDecision {
	blocked: boolean;
	/** Machine-readable reason, when provided by the platform. */
	reason?: string;
	/** Block expiry (ms epoch), when provided. */
	expiresAt?: number;
}
