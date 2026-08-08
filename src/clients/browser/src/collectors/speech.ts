/**
 * Speech synthesis voices collector.
 * Detects available TTS voices — varies by OS, browser, and installed languages.
 */

/**
 * Collect available speech synthesis voices.
 * Returns sorted voice names.
 */
export function collectSpeechVoices(): string[] {
	try {
		if (!window.speechSynthesis) return [];

		const voices = window.speechSynthesis.getVoices();
		return voices
			.map((v) => v.name)
			.filter((n) => n.length > 0)
			.sort();
	} catch {
		return [];
	}
}

/**
 * Get voice fingerprint as a hashable string.
 */
export function getSpeechFingerprint(): string {
	return collectSpeechVoices().join(",");
}
