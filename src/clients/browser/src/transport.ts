/**
 * Transport layer for the browser SDK (D16/D17).
 *
 * - `sendPackage()` POSTs the raw SignalPackage v2 body to the ingress with
 *   metadata headers (DESIGN §9.4.5) and parses the relayed worker reply.
 *   RabbitMQ is never on this path — the ingress wraps the body in an FPKG
 *   request/response.
 * - `connectDecisionSocket()` opens the fraud-platform WebSocket for
 *   `session.blocked` push (best-effort fast path; the app enforces).
 */

import type { BlockDecision, SendResult, SdkConfig, WorkerReply } from "./types.js";
import { toHex } from "./package.js";

/** Headers the ingress uses to build the FPKG frame (DESIGN §9.4.5). */
export interface PackageHeaders {
	schemaVersion: number;
	sdkVersion: string;
	packageId: Uint8Array;
}

/** POSTs a serialized SignalPackage to the ingress and parses the reply. */
export async function sendPackage(
	bytes: Uint8Array,
	config: SdkConfig,
	headers: PackageHeaders,
): Promise<SendResult> {
	const h: Record<string, string> = {
		"content-type": "application/octet-stream",
		"x-fpkg-schema-version": String(headers.schemaVersion),
		"x-fpkg-sdk-version": headers.sdkVersion,
		"x-fpkg-package-id": toHex(headers.packageId),
	};
	const subtle = typeof crypto !== "undefined" ? crypto.subtle : undefined;
	if (subtle && typeof subtle.digest === "function") {
		try {
			const digest = await subtle.digest("SHA-256", bytes as unknown as BufferSource);
			h["x-fpkg-integrity"] = "sha256-" + toHex(new Uint8Array(digest));
		} catch {
			// Integrity header is best-effort; the ingress enforces it when present.
		}
	}

	let res: Response;
	try {
		res = await fetch(config.ingressUrl, {
			method: "POST",
			headers: h,
			body: bytes as unknown as BodyInit,
		});
	} catch (err) {
		return {
			ok: false,
			status: 0,
			error: err instanceof Error ? err.message : String(err),
		};
	}

	let reply: WorkerReply | undefined;
	try {
		const body = new Uint8Array(await res.arrayBuffer());
		reply = parseWorkerReply(body);
	} catch {
		// Non-binary reply (e.g. a JSON error page) — keep reply undefined.
	}

	return { ok: res.ok, status: res.status, reply };
}

/**
 * Parses the ingress-relayed worker reply frame payload:
 * `u8 status | engine result`. fingerprint_result bodies are
 * `{ digest: [32]u8, schema: u16, feature_count: u16 }` (DESIGN §5.1).
 */
export function parseWorkerReply(body: Uint8Array): WorkerReply | undefined {
	if (body.byteLength < 1) return undefined;
	const status = body[0];
	const reply: WorkerReply = { status };
	if (status === 0 && body.byteLength >= 1 + 32 + 2 + 2) {
		const view = new DataView(body.buffer, body.byteOffset, body.byteLength);
		reply.digestHex = toHex(body.subarray(1, 33));
		reply.schemaVersion = view.getUint16(33, true);
		reply.featureCount = view.getUint16(35, true);
	}
	return reply;
}

/** Opens the platform decision socket; returns a disconnect function. */
export function connectDecisionSocket(
	config: SdkConfig,
	onDecision: (decision: BlockDecision) => void,
): () => void {
	if (!config.wsUrl) return () => {};

	let ws: WebSocket | null = null;
	let closed = false;
	let attempts = 0;
	const maxAttempts = 5;

	const connect = (): void => {
		if (closed) return;
		try {
			ws = new WebSocket(config.wsUrl as string);
		} catch {
			return;
		}
		ws.onmessage = (event: MessageEvent): void => {
			let message: unknown;
			try {
				message = JSON.parse(String(event.data));
			} catch {
				return; // malformed frame — ignore
			}
			const m = message as {
				type?: string;
				reason?: string;
				expiresAt?: number;
			};
			if (m.type === "session.blocked") {
				onDecision({ blocked: true, reason: m.reason, expiresAt: m.expiresAt });
			}
		};
		ws.onclose = (): void => {
			if (closed) return;
			if (attempts < maxAttempts) {
				attempts += 1;
				setTimeout(connect, Math.min(1000 * 2 ** attempts, 30000));
			}
		};
		ws.onerror = (): void => {
			try {
				ws?.close();
			} catch {
				// ignore
			}
		};
	};

	connect();
	return () => {
		closed = true;
		try {
			ws?.close();
		} catch {
			// ignore
		}
	};
}
