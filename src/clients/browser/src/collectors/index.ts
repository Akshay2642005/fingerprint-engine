/**
 * Browser signal collectors for fingerprint gathering (D14).
 * Each collector extracts specific browser signals that contribute to the
 * SignalPackage shipped to the ingress.
 */

export { collectSignals } from "./collector.js";
export type { CollectOptions } from "../types.js";

export { collectCanvasFingerprint, getCanvasCapabilities } from "./canvas.js";
export type { CanvasOptions } from "./canvas.js";

export { collectWebGLInfo, collectWebGL2Info } from "./webgl.js";
export type { WebGLInfo } from "./webgl.js";

export { collectAudioFingerprint, collectAudioFingerprintSync } from "./audio.js";
export type { AudioFingerprintOptions } from "./audio.js";

export { collectFonts, getFontFingerprint } from "./fonts.js";

export { collectBattery } from "./battery.js";
export type { BatteryInfo } from "./battery.js";

export { collectMediaInfo } from "./media.js";
export type { MediaInfo } from "./media.js";

export { collectSpeechVoices, getSpeechFingerprint } from "./speech.js";

export {
	detectKeyboardLayout,
	collectPointerInfo,
	collectGamepadInfo,
	hasSharedWorker,
} from "./input.js";

export { collectPermissions } from "./permissions.js";
export type { PermissionStates } from "./permissions.js";
