/**
 * Canvas fingerprinting collector.
 * Renders text and shapes to a canvas, extracts pixel data, and returns a
 * 32-byte SHA-256 digest that conforms to the model's Bytes/64-byte bound.
 *
 * BUG-008: previous version returned raw pixel data (40 KB), tripping
 * bytes_too_long on every real package. This version hashes in-browser.
 */

export interface CanvasOptions {
	/** Text to render (default: fingerprint engine branding) */
	text?: string;
	/** Font size (default: 14) */
	fontSize?: number;
	/** Canvas width (default: 200) */
	width?: number;
	/** Canvas height (default: 50) */
	height?: number;
}

/**
 * Collect canvas fingerprint by rendering text, extracting pixel data, and
 * returning a 32-byte SHA-256 digest. Returns null if canvas or SubtleCrypto
 * is unavailable.
 */
export async function collectCanvasFingerprint(
	options: CanvasOptions = {},
): Promise<Uint8Array | null> {
	const {
		text = "fingerprint引擎 🎨",
		fontSize = 14,
		width = 200,
		height = 50,
	} = options;

	try {
		const canvas = document.createElement("canvas");
		canvas.width = width;
		canvas.height = height;

		const ctx = canvas.getContext("2d");
		if (!ctx) return null;

		// Clear canvas
		ctx.fillStyle = "#f60";
		ctx.fillRect(0, 0, width, height);

		// Draw text with various styles
		ctx.textBaseline = "top";
		ctx.font = `${fontSize}px Arial`;
		ctx.fillStyle = "#069";
		ctx.fillText(text, 2, 15);

		// Draw additional shapes for more entropy
		ctx.fillStyle = "rgba(102, 204, 0, 0.7)";
		ctx.fillRect(100, 5, 80, 30);

		// Draw a gradient
		const gradient = ctx.createLinearGradient(0, 0, width, 0);
		gradient.addColorStop(0, "red");
		gradient.addColorStop(0.5, "green");
		gradient.addColorStop(1, "blue");
		ctx.fillStyle = gradient;
		ctx.fillRect(0, 40, width, 10);

		// Extract pixel data and hash to 32-byte SHA-256 digest
		const imageData = ctx.getImageData(0, 0, width, height);
		const pixelBytes = new Uint8Array(imageData.data.buffer);
		return new Uint8Array(await crypto.subtle.digest("SHA-256", pixelBytes));
	} catch {
		// Canvas not supported or SubtleCrypto unavailable
		return null;
	}
}

/**
 * Get a string representation of canvas capabilities.
 * This can be used as an additional signal.
 */
export function getCanvasCapabilities(): string[] {
	const caps: string[] = [];

	try {
		const canvas = document.createElement("canvas");
		const ctx = canvas.getContext("2d");
		if (ctx) caps.push("2d");
	} catch {
		// 2d context not available
	}

	try {
		const canvas = document.createElement("canvas");
		const ctx = canvas.getContext("webgl");
		if (ctx) caps.push("webgl");
	} catch {
		// webgl not available
	}

	try {
		const canvas = document.createElement("canvas");
		const ctx = canvas.getContext("webgl2");
		if (ctx) caps.push("webgl2");
	} catch {
		// webgl2 not available
	}

	try {
		const canvas = document.createElement("canvas");
		const ctx = canvas.getContext("experimental-webgl");
		if (ctx) caps.push("experimental-webgl");
	} catch {
		// experimental-webgl not available
	}

	return caps;
}
