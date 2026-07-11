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

export { collectFingerprint } from "./collector";
export type { CollectorOptions, CollectedSignals } from "./collector";
