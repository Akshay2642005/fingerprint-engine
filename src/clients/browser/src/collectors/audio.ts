/**
 * AudioContext fingerprinting collector (deterministic).
 *
 * Uses OfflineAudioContext for a fully deterministic render — no live
 * AudioContext, no timer jitter, no autoplay gate. The rendered buffer
 * is hashed to a 32-byte SHA-256 digest that conforms to the model's
 * Bytes/64-byte bound.
 *
 * BUG-008: previous version sent raw 4 KB float data, tripping bytes_too_long.
 * BUG-010: previous version used live AudioContext + setTimeout jitter, yielding
 *          non-deterministic output across sessions.
 * BUG-015: collectAudioFingerprintSync called getChannelData on a Promise
 *          (always threw, always returned null, never called).
 */

export interface AudioFingerprintOptions {
	/** Sample rate for the offline context (default: 44100) */
	sampleRate?: number;
	/** Length of the render buffer in samples (default: 4410) */
	bufferLength?: number;
}

/**
 * Collect a deterministic audio fingerprint.
 * Renders audio through OfflineAudioContext, then SHA-256 hashes the output.
 * Returns null if OfflineAudioContext or SubtleCrypto is unavailable.
 */
export async function collectAudioFingerprint(
	options: AudioFingerprintOptions = {},
): Promise<Uint8Array | null> {
	const { sampleRate = 44100, bufferLength = 4410 } = options;

	try {
		const ctx = new OfflineAudioContext(1, bufferLength, sampleRate);

		const oscillator = ctx.createOscillator();
		oscillator.type = "triangle";
		oscillator.frequency.setValueAtTime(10000, 0);

		const compressor = ctx.createDynamicsCompressor();
		compressor.threshold.setValueAtTime(-50, 0);
		compressor.knee.setValueAtTime(40, 0);
		compressor.ratio.setValueAtTime(12, 0);
		compressor.attack.setValueAtTime(0, 0);
		compressor.release.setValueAtTime(0.25, 0);

		oscillator.connect(compressor);
		compressor.connect(ctx.destination);
		oscillator.start(0);

		// Deterministic render — no wall-clock dependency
		const rendered = await ctx.startRendering();
		const channelData = rendered.getChannelData(0);

		// Convert float32 samples to bytes, then SHA-256 hash
		const floatBytes = new Uint8Array(channelData.length * 4);
		const view = new DataView(floatBytes.buffer);
		for (let i = 0; i < channelData.length; i++) {
			view.setFloat32(i * 4, channelData[i], true);
		}
		return new Uint8Array(await crypto.subtle.digest("SHA-256", floatBytes));
	} catch {
		return null;
	}
}
