import { defineCollection, z } from 'astro:content'
import { glob } from 'astro/loaders'

const docs = defineCollection({
  loader: glob({ pattern: '**/*.{md,mdx}', base: './src/docs' }),
  schema: z.object({
    title: z.string(),
    description: z.string().optional(),
    // category drives sidebar highlight: start|concepts|guides|operating|architecture|reference|internals|contributing
    category: z.string(),
    // sidebar order within its category
    order: z.number().optional(),
    // breadcrumb trail (excluding the leading "docs"), e.g. ["concepts","signals"]
    crumbs: z.array(z.string()).optional(),
  }),
})

export const collections = { docs }
