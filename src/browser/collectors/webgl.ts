/**
 * WebGL fingerprinting collector.
 * Extracts GPU renderer and vendor information from WebGL context.
 * This is a high-entropy signal that identifies the graphics hardware.
 */

export interface WebGLInfo {
	vendor: string;
	renderer: string;
	version: string;
	shadingLanguageVersion: string;
	extensions: string[];
	/** Maximum texture size */
	maxTextureSize: number;
	/** Maximum viewport dimensions */
	maxViewportDims: [number, number];
	/** Maximum combined texture units */
	maxCombinedTextureUnits: number;
}

/**
 * Collect WebGL renderer and vendor information.
 * Returns null if WebGL is not available.
 */
export function collectWebGLInfo(): WebGLInfo | null {
	try {
		const canvas = document.createElement("canvas");
		const gl =
			(canvas.getContext("webgl") as WebGLRenderingContext | null) ||
			(canvas.getContext("experimental-webgl") as WebGLRenderingContext | null);
		if (!gl) return null;

		const debugInfo = gl.getExtension("WEBGL_debug_renderer_info");
		const vendor = debugInfo
			? gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL)
			: gl.getParameter(gl.VENDOR);
		const renderer = debugInfo
			? gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL)
			: gl.getParameter(gl.RENDERER);

		const extensions = gl.getSupportedExtensions() || [];

		return {
			vendor: String(vendor),
			renderer: String(renderer),
			version: String(gl.getParameter(gl.VERSION)),
			shadingLanguageVersion: String(
				gl.getParameter(gl.SHADING_LANGUAGE_VERSION),
			),
			extensions,
			maxTextureSize: gl.getParameter(gl.MAX_TEXTURE_SIZE) as number,
			maxViewportDims: gl.getParameter(gl.MAX_VIEWPORT_DIMS) as [
				number,
				number,
			],
			maxCombinedTextureUnits: gl.getParameter(
				gl.MAX_COMBINED_TEXTURE_IMAGE_UNITS,
			) as number,
		};
	} catch {
		return null;
	}
}

/**
 * Collect WebGL2-specific information if available.
 */
export function collectWebGL2Info(): Record<string, unknown> | null {
	try {
		const canvas = document.createElement("canvas");
		const gl = canvas.getContext("webgl2") as WebGL2RenderingContext | null;
		if (!gl) return null;

		return {
			version: String(gl.getParameter(gl.VERSION)),
			max3DTextureSize: gl.getParameter(gl.MAX_3D_TEXTURE_SIZE),
			maxArrayTextureLayers: gl.getParameter(gl.MAX_ARRAY_TEXTURE_LAYERS),
			maxColorAttachments: gl.getParameter(gl.MAX_COLOR_ATTACHMENTS),
			maxDrawBuffers: gl.getParameter(gl.MAX_DRAW_BUFFERS),
			maxSamples: gl.getParameter(gl.MAX_SAMPLES),
		};
	} catch {
		return null;
	}
}
