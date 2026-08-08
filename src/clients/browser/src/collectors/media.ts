/**
 * Media capabilities collector.
 * Detects supported codecs, media formats, and HDR support.
 */

export interface MediaInfo {
	videoCodecs: string[];
	audioCodecs: string[];
	mediaFormats: string[];
	audioFormats: string[];
	hdrSupport: boolean;
}

const VIDEO_CODECS = [
	'video/mp4; codecs="avc1.42E01E"', // H.264 Baseline
	'video/mp4; codecs="avc1.640028"', // H.264 High
	'video/mp4; codecs="hev1.1.6.L93.B0"', // HEVC
	'video/webm; codecs="vp8"', // VP8
	'video/webm; codecs="vp9"', // VP9
	'video/webm; codecs="av01.0.08M.08"', // AV1
	'video/ogg; codecs="theora"', // Theora
	'video/mp4; codecs="av01.0.04M.08"', // AV1 (4K)
];

const AUDIO_CODECS = [
	'audio/mp4; codecs="mp4a.40.2"', // AAC
	'audio/webm; codecs="opus"', // Opus
	'audio/ogg; codecs="vorbis"', // Vorbis
	'audio/mp3; codecs="mp3"', // MP3 (legacy)
	'audio/wav; codecs="1"', // PCM WAV
	'audio/mp4; codecs="mp4a.40.02"', // AAC-LC
	"audio/flac", // FLAC
];

const MEDIA_FORMATS = [
	"video/mp4",
	"video/webm",
	"video/ogg",
	"video/quicktime",
	"video/x-msvideo",
	"video/x-matroska",
];

const AUDIO_FORMATS = [
	"audio/mpeg",
	"audio/mp4",
	"audio/webm",
	"audio/ogg",
	"audio/wav",
	"audio/flac",
	"audio/aac",
];

/**
 * Check if a media type is supported.
 */
function isTypeSupported(mimeType: string): boolean {
	try {
		const video = document.createElement("video");
		return video.canPlayType(mimeType) !== "";
	} catch {
		return false;
	}
}

/**
 * Collect media capability information.
 */
export function collectMediaInfo(): MediaInfo {
	const videoCodecs = VIDEO_CODECS.filter((c) => isTypeSupported(c));
	const audioCodecs = AUDIO_CODECS.filter((c) => isTypeSupported(c));
	const mediaFormats = MEDIA_FORMATS.filter((f) => isTypeSupported(f));
	const audioFormats = AUDIO_FORMATS.filter((f) => isTypeSupported(f));

	// Check HDR support
	let hdrSupport = false;
	try {
		hdrSupport = window.matchMedia("(dynamic-range: high)").matches;
	} catch {
		// Not supported
	}

	return {
		videoCodecs,
		audioCodecs,
		mediaFormats,
		audioFormats,
		hdrSupport,
	};
}
