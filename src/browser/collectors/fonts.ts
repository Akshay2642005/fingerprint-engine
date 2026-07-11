/**
 * Font detection collector.
 * Detects installed fonts by measuring text rendering dimensions
 * with candidate fonts. High-entropy signal — varies by OS, hardware, and user.
 */

/** Base fonts present on virtually every system */
const BASE_FONTS = ['Arial', 'Courier New', 'Georgia', 'Times New Roman', 'Verdana'];

/** Candidate fonts to probe — broad coverage across OSes */
const CANDIDATE_FONTS = [
  // Common Windows
  'Calibri', 'Cambria', 'Consolas', 'Constantia', 'Corbel', 'Segoe UI',
  'Segoe Print', 'Tahoma', 'Trebuchet MS', 'Palatino Linotype',
  // Common macOS
  'Helvetica Neue', 'Helvetica', 'SF Pro Text', 'SF Pro Display',
  'Menlo', 'Monaco', 'Lucida Grande', 'Geneva', 'Futura',
  // Common Linux
  'Ubuntu', 'DejaVu Sans', 'DejaVu Serif', 'Liberation Sans',
  'Noto Sans', 'Droid Sans', 'Cantarell',
  // Cross-platform
  'Roboto', 'Open Sans', 'Lato', 'Source Sans Pro', 'Noto Sans CJK SC',
  // Specialty
  'Webdings', 'Wingdings', 'Zapf Dingbats', 'Impact',
  'Comic Sans MS', 'Bradley Hand', 'Brush Script MT',
  // Monospace
  'Fira Code', 'JetBrains Mono', 'Source Code Pro', 'Cascadia Code',
  'Ubuntu Mono', 'Inconsolata', 'Hack', 'Menlo',
  // Serif extras
  'Baskerville', 'Garamond', 'Book Antiqua', 'Didot',
];

/**
 * Detect installed fonts by measuring rendered text width.
 * Returns a sorted array of detected font names.
 */
export function collectFonts(): string[] {
  try {
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    if (!ctx) return [];

    const testString = 'mmmmmmmmmmlli';
    const testSize = '72px';
    const span = document.createElement('span');
    span.style.position = 'absolute';
    span.style.left = '-9999px';
    span.style.fontSize = testSize;
    span.style.fontFamily = '';
    span.style.whiteSpace = 'nowrap';
    span.textContent = testString;
    document.body.appendChild(span);

    // Measure baseline width with a known font
    const baseFont = 'monospace';
    span.style.fontFamily = baseFont;
    const baseWidth = span.getBoundingClientRect().width;

    const detected: string[] = [];

    // Quick check with base fonts first
    for (const font of BASE_FONTS) {
      span.style.fontFamily = `"${font}", ${baseFont}`;
      const width = span.getBoundingClientRect().width;
      if (width !== baseWidth) {
        detected.push(font);
      }
    }

    // Probe candidate fonts against the base set
    const probeFonts = detected.length > 0 ? detected : [baseFont];
    const probeStr = probeFonts.map(f => `"${f}"`).join(', ');

    for (const font of CANDIDATE_FONTS) {
      span.style.fontFamily = `"${font}", ${probeStr}, ${baseFont}`;
      const width = span.getBoundingClientRect().width;
      // If width differs from all known fonts, this font is available
      let unique = true;
      span.style.fontFamily = probeStr + `, ${baseFont}`;
      const probeWidth = span.getBoundingClientRect().width;
      if (width === probeWidth) {
        unique = false;
      }
      if (unique && !detected.includes(font)) {
        detected.push(font);
      }
    }

    document.body.removeChild(span);
    detected.sort();
    return detected;
  } catch {
    return [];
  }
}

/**
 * Get font fingerprint as a hashable string.
 * Format: sorted comma-separated font names.
 */
export function getFontFingerprint(): string {
  return collectFonts().join(',');
}
