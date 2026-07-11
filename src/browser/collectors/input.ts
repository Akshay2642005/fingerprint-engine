/**
 * Input device collectors.
 * Detects keyboard layout, pointer type, and gamepad support.
 */

/**
 * Detect keyboard layout via key event geometry.
 * Uses key codes that differ between US and European layouts.
 */
export function detectKeyboardLayout(): string {
  try {
    // Test key that differs between layouts
    const testKeys: Record<string, string> = {};

    // Key positions that differ between layouts
    const layoutIndicators = [
      { key: 'KeyQ', qwerty: 'q', azerty: 'a' },
      { key: 'KeyW', qwerty: 'w', azerty: 'z' },
      { key: 'KeyZ', qwerty: 'z', azerty: 'w' },
      { key: 'KeyA', qwerty: 'a', azerty: 'q' },
      { key: 'Slash', qwerty: '/', azerty: '!' },
    ];

    // We can't directly test layout without user interaction,
    // so we return what navigator reports
    const nav = navigator as Navigator & { keyboard?: { layout?: string } };
    if (nav.keyboard?.layout) {
      return nav.keyboard.layout;
    }

    // Fallback: infer from language + platform
    return `${navigator.language}|${navigator.platform}`;
  } catch {
    return 'unknown';
  }
}

/**
 * Check if pointer events are supported and detect pointer type.
 */
export function collectPointerInfo(): { supported: boolean; type: string } {
  const supported = 'PointerEvent' in window;
  let type = 'none';

  if (supported) {
    try {
      if (window.matchMedia('(pointer: fine)').matches) type = 'fine';
      else if (window.matchMedia('(pointer: coarse)').matches) type = 'coarse';
      else type = 'none';
    } catch {
      // Not supported
    }
  }

  return { supported, type };
}

/**
 * Detect gamepad support.
 */
export function collectGamepadInfo(): boolean {
  return 'getGamepads' in navigator;
}

/**
 * Detect shared worker support.
 */
export function hasSharedWorker(): boolean {
  return typeof SharedWorker !== 'undefined';
}
