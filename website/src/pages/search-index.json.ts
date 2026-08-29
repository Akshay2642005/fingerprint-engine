import type { APIRoute } from 'astro'
import { getCollection } from 'astro:content'

// Build-time search index: a flat JSON blob (id, title, description, category,
// url, text) consumed by the client-side docs search component. Excludes the
// heavy body but keeps a searchable substring slice.
export const GET: APIRoute = async () => {
  const docs = await getCollection('docs')
  const index = docs.map((d) => {
    const isReadme = /readme$/i.test(d.id)
    const url = isReadme ? `/docs/${d.id.replace(/\/[^/]*readme$/i, '')}/` : `/docs/${d.id}/`
    const text = (d.body ?? '')
      .replace(/```[\s\S]*?```/g, ' ')
      .replace(/[#*`>|_-]/g, ' ')
      .replace(/\s+/g, ' ')
      .slice(0, 4000)
    return {
      id: d.id,
      title: d.data.title,
      description: d.data.description ?? '',
      category: d.data.category,
      url,
      text: `${d.data.title} ${d.data.description ?? ''} ${text}`,
    }
  })
  return new Response(JSON.stringify(index), {
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  })
}
