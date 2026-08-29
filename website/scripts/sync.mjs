// Pre-build sync: pull canonical content from the repo root into the
// website docs collection so the built site always mirrors the current
// CONTRIBUTING, CONVENTIONS, and SECURITY docs.
//
// Usage: node scripts/sync.mjs  (run automatically before `astro build`).
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { join, dirname } from 'node:path'

const root = fileURLToPath(new URL('../../', import.meta.url)) // repo root
const out = fileURLToPath(new URL('../src/docs/', import.meta.url))

const src = {
  'contributing.md': {
    file: 'CONTRIBUTING.md',
    title: 'Contributing',
    category: 'contributing',
    order: 1,
    description: 'How to contribute: workflow, standards, and testing.',
  },
  'reference/conventions.md': {
    file: 'CONVENTIONS.md',
    title: 'Conventions',
    category: 'reference',
    order: 2,
    crumbs: ['reference', 'conventions'],
    description: 'Style guide, safety rules, and engineering practices.',
  },
  'security.md': {
    file: 'SECURITY.md',
    title: 'Security',
    category: 'contributing',
    order: 2,
    description: 'Security policy and vulnerability reporting.',
  },
}

for (const [rel, cfg] of Object.entries(src)) {
  const body = await readFile(join(root, cfg.file), 'utf8')
  const fm = [
    '---',
    `title: ${JSON.stringify(cfg.title)}`,
    `description: ${JSON.stringify(cfg.description)}`,
    `category: ${JSON.stringify(cfg.category)}`,
    `order: ${cfg.order}`,
    ...[cfg.crumbs ? `crumbs: [${cfg.crumbs.map((c) => `"${c}"`).join(', ')}]` : []],
    '---',
    '',
  ].join('\n')
  const target = join(out, rel)
  await mkdir(dirname(target), { recursive: true })
  await writeFile(target, fm + '\n' + body, 'utf8')
  console.log('synced', rel, '<-', cfg.file)
}

console.log('sync complete')
