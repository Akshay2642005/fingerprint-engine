/**
 * Browser signal collectors for fingerprint gathering.
 * Each collector extracts specific browser signals that contribute
 * to the overall fingerprint.
 */

export { collectCanvasFingerprint, getCanvasCapabilities } from "./canvas";
export type { CanvasOptions } from "./canvas";

export { collectWebGLInfo, collectWebGL2Info } from "./webgl";
export type { WebGLInfo } from "./webgl";

export { collectAudioFingerprint, collectAudioFingerprintSync } from "./audio";
export type { AudioFingerprintOptions } from "./audio";

export { collectFonts, getFontFingerprint } from "./fonts";

export { collectBattery } from "./battery";
export type { BatteryInfo } from "./battery";

export { collectMediaInfo } from "./media";
export type { MediaInfo } from "./media";

export { collectSpeechVoices, getSpeechFingerprint } from "./speech";

export {
	detectKeyboardLayout,
	collectPointerInfo,
	collectGamepadInfo,
	hasSharedWorker,
} from "./input";

export { collectPermissions } from "./permissions";
export type { PermissionStates } from "./permissions";

export { collectFingerprint } from "./collector";
export type { CollectorOptions, CollectedSignals } from "./collector";
