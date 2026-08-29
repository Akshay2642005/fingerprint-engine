// Theme-aware Shiki theme for the Fingerprint Engine docs.
// Token colors are CSS variables resolved per light/dark theme (see
// global.css `.astro-code` + `:root` / `[data-theme="dark"]`), so the
// highlighted code adapts to the site theme instead of pinning a fixed
// background. Modeled on a warm monochrome + accent palette matching the
// iii-style design system.
export const fpTheme = {
  name: 'fingerprint-engine',
  type: 'light',
  fg: 'var(--code-ink)',
  bg: 'var(--code-bg)',
  colors: {},
  tokenColors: [
    { scope: ['comment', 'comment.block'], settings: { foreground: 'var(--code-com)' } },
    { scope: ['string', 'string.quoted', 'string.quoted.single', 'string.quoted.double'], settings: { foreground: 'var(--code-str)' } },
    { scope: ['keyword', 'keyword.control', 'storage', 'storage.type'], settings: { foreground: 'var(--code-kw)' } },
    { scope: ['constant', 'constant.numeric', 'constant.language'], settings: { foreground: 'var(--code-num)' } },
    { scope: ['function', 'entity.name.function', 'support.function'], settings: { foreground: 'var(--code-fn)' } },
    { scope: ['entity.name.class', 'entity.name.type', 'support.type'], settings: { foreground: 'var(--code-cls)' } },
    { scope: ['variable', 'variable.other', 'variable.parameter'], settings: { foreground: 'var(--code-ink)' } },
    { scope: ['property', 'support.property-value', 'entity.other.attribute-name'], settings: { foreground: 'var(--code-prop)' } },
    { scope: ['operator', 'punctuation', 'punctuation.definition'], settings: { foreground: 'var(--code-op)' } },
    { scope: ['constant.other'], settings: { foreground: 'var(--code-num)' } },
  ],
}
