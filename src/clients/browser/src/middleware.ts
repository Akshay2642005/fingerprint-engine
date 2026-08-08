/**
 * Middleware for the browser SDK (D17).
 *
 * Enforces the last-known decision client-side as a UX gate. The app
 * remains the authority: the sync decision API is checked server-side and
 * sensitive actions are rejected by the app regardless of this gate.
 */

import type { BlockDecision } from "./types.js";

/** Tracks the last-known decision and fans out session.blocked callbacks. */
export class DecisionGate {
	#decision: BlockDecision | undefined;
	#listeners = new Set<(decision: BlockDecision) => void>();

	/** Records a decision from the platform (WS push or sync fetch). */
	update(decision: BlockDecision): void {
		this.#decision = decision;
		for (const listener of this.#listeners) {
			listener(decision);
		}
	}

	/**
	 * Returns the last-known decision for the session. Call before running a
	 * sensitive action; treat `blocked === true` as "do not proceed".
	 */
	assertAllowed(): BlockDecision {
		return this.#decision ?? { blocked: false };
	}

	/** Registers a callback for session.blocked; returns an unsubscribe fn. */
	onSessionBlocked(callback: (decision: BlockDecision) => void): () => void {
		this.#listeners.add(callback);
		return () => {
			this.#listeners.delete(callback);
		};
	}
}
