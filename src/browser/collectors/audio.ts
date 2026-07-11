/**
 * AudioContext fingerprinting collector.
 * Generates a unique audio fingerprint by processing audio through
 * various nodes and extracting the output.
 */

export interface AudioFingerprintOptions {
	/** Sample rate for the audio context (default: 44100) */
	sampleRate?: number;
	/** Number of oscillator iterations (default: 5) */
	oscillatorIterations?: number;
}

/**
 * Collect AudioContext fingerprint.
 * Creates an audio context, processes audio through various nodes,
 * and returns the rendered audio data as a hash.
 *
 * Returns null if AudioContext is not supported.
 */
export async function collectAudioFingerprint(
	options: AudioFingerprintOptions = {},
): Promise<Uint8Array | null> {
	const { sampleRate = 44100, oscillatorIterations = 5 } = options;

	try {
		const AudioContextClass =
			window.AudioContext ||
			(window as unknown as Record<string, typeof AudioContext>)
				.webkitAudioContext;
		if (!AudioContextClass) return null;

		const ctx = new AudioContextClass({ sampleRate });

		// Create oscillator for audio generation
		const oscillator = ctx.createOscillator();
		oscillator.type = "triangle";
		oscillator.frequency.setValueAtTime(10000, ctx.currentTime);

		// Create dynamics compressor for audio processing
		const compressor = ctx.createDynamicsCompressor();
		compressor.threshold.setValueAtTime(-50, ctx.currentTime);
		compressor.knee.setValueAtTime(40, ctx.currentTime);
		compressor.ratio.setValueAtTime(12, ctx.currentTime);
		compressor.attack.setValueAtTime(0, ctx.currentTime);
		compressor.release.setValueAtTime(0.25, ctx.currentTime);

		// Create analyser for frequency data
		const analyser = ctx.createAnalyser();
		analyser.fftSize = 2048;

		// Connect nodes: oscillator -> compressor -> analyser -> destination
		oscillator.connect(compressor);
		compressor.connect(analyser);
		analyser.connect(ctx.destination);

		// Start oscillator
		oscillator.start(0);

		// Collect frequency data over multiple iterations
		const frequencyData = new Float32Array(analyser.frequencyBinCount);

		for (let i = 0; i < oscillatorIterations; i++) {
			analyser.getFloatFrequencyData(frequencyData);
			// Small delay between iterations
			await new Promise((resolve) => setTimeout(resolve, 10));
		}

		// Stop oscillator and close context
		oscillator.stop();
		await ctx.close();

		// Convert frequency data to bytes
		const bytes = new Uint8Array(frequencyData.length * 4);
		const view = new DataView(bytes.buffer);
		for (let i = 0; i < frequencyData.length; i++) {
			view.setFloat32(i * 4, frequencyData[i], true);
		}

		return bytes;
	} catch {
		return null;
	}
}

/**
 * Synchronous audio fingerprint using offline audio context.
 * This is an alternative that doesn't require async operations.
 */
export function collectAudioFingerprintSync(): Uint8Array | null {
	try {
		const AudioContextClass =
			window.AudioContext ||
			(window as unknown as Record<string, typeof AudioContext>)
				.webkitAudioContext;
		if (!AudioContextClass) return null;

		// Create offline context for synchronous rendering
		const ctx = new OfflineAudioContext(1, 4410, 44100);

		const oscillator = ctx.createOscillator();
		oscillator.type = "sine";
		oscillator.frequency.setValueAtTime(10000, 0);

		const compressor = ctx.createDynamicsCompressor();

		oscillator.connect(compressor);
		compressor.connect(ctx.destination);
		oscillator.start(0);

		// Render synchronously (will block)
		const buffer = ctx.startRendering() as unknown as AudioBuffer;

		// Extract channel data
		const data = buffer.getChannelData(0);
		const bytes = new Uint8Array(data.length * 4);
		const view = new DataView(bytes.buffer);
		for (let i = 0; i < data.length; i++) {
			view.setFloat32(i * 4, data[i], true);
		}

		return bytes;
	} catch {
		return null;
	}
}
