import { defineConfig } from 'astro/config'
import mdx from '@astrojs/mdx'
import remarkGfm from 'remark-gfm'
import { fpTheme } from './src/theme.ts'

// Static documentation + landing site for the Fingerprint Engine.
// Built with `npm install && npm run build` inside the website/ dir.
// Output is fully static under website/dist for hosting on any static host
// or GitHub Pages.
export default defineConfig({
  site: 'https://fingerprint-engine.dev',
  trailingSlash: 'ignore',
  build: {
    format: 'directory',
  },
  markdown: {
    syntaxHighlight: 'shiki',
    shikiConfig: {
      theme: fpTheme,
      wrap: false,
    },
    remarkPlugins: [remarkGfm],
  },
  integrations: [mdx()],
  vite: {
    optimizeDeps: {
      // Mermaid lazy-loads its per-diagram renderers (flowDiagram,
      // sequenceDiagram, …) via dynamic import. Pre-bundle mermaid so the
      // dev server resolves those chunks instead of 404-ing
      // ("Failed to fetch dynamically imported module").
      include: ['mermaid'],
    },
  },
})
