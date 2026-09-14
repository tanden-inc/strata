import { defineConfig } from 'vitepress'
// Shiki 2.x (pinned by VitePress 1.6) does not bundle the MoonBit grammar; tm-grammars does.
import fs from 'node:fs'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const moonbit = require('tm-grammars/grammars/moonbit.json')

const repo = 'https://github.com/tanden-inc/strata'

export default defineConfig({
  title: 'Strata',
  description:
    'Event sourcing for MoonBit: deciders, advice, selections, dynamic consistency boundaries, projections and reactors',
  base: '/strata/',
  cleanUrls: true,
  lastUpdated: true,
  head: [['link', { rel: 'icon', type: 'image/svg+xml', href: '/strata/strata.svg' }]],

  markdown: {
    languages: [{ ...(moonbit as any), name: 'moonbit', aliases: ['mbt', 'mbti'] }],
    config(md) {
      // `<<< file#region` imports: resolve the region ourselves so that the blank line `moon fmt`
      // keeps after a `// #region` marker is not rendered as the snippet's first line.
      const fence = md.renderer.rules.fence!
      md.renderer.rules.fence = (tokens, idx, options, env, self) => {
        const token = tokens[idx] as any
        const [src, regionName] = (token.src ?? []) as [string?, string?]
        if (src && fs.existsSync(src) && fs.statSync(src).isFile()) {
          ;(env as any)?.includes?.push(src)
          let lines = fs.readFileSync(src, 'utf8').replace(/\r\n/g, '\n').split('\n')
          if (regionName) {
            const start = lines.findIndex((l) => new RegExp(`^\\s*// #region\\s+${regionName}\\s*$`).test(l))
            const end = lines.findIndex((l) => new RegExp(`^\\s*// #endregion\\s+${regionName}\\s*$`).test(l))
            if (start >= 0 && end > start) lines = lines.slice(start + 1, end)
          }
          while (lines.length && lines[0].trim() === '') lines.shift()
          while (lines.length && lines[lines.length - 1].trim() === '') lines.pop()
          token.content = lines.join('\n') + '\n'
          token.src = undefined
        }
        return fence(tokens, idx, options, env, self)
      }
    },
  },

  themeConfig: {
    logo: '/strata.svg',
    siteTitle: 'Strata',

    nav: [
      { text: 'Guide', link: '/guide/installation', activeMatch: '^/(guide|introduction)/' },
      { text: 'Tutorial', link: '/tutorial/01-your-first-decider', activeMatch: '^/tutorial/' },
      { text: 'Concepts', link: '/concepts/deciders', activeMatch: '^/concepts/' },
      { text: 'Design', link: '/design/principles', activeMatch: '^/(design|adr)/' },
      { text: 'Reference', link: '/reference/core', activeMatch: '^/reference/' },
      { text: 'Roadmap', link: '/ROADMAP' },
    ],

    sidebar: {
      '/introduction/': guideSidebar(),
      '/guide/': guideSidebar(),
      '/tutorial/': [
        {
          text: 'Tutorial',
          items: [
            { text: '1. Your first decider', link: '/tutorial/01-your-first-decider' },
            { text: '2. Specs: tests as specifications', link: '/tutorial/02-specs' },
            { text: '3. Running commands', link: '/tutorial/03-running-commands' },
            { text: '4. Read models', link: '/tutorial/04-read-models' },
            { text: '5. Advice', link: '/tutorial/05-advice' },
            { text: '6. Dynamic consistency boundaries', link: '/tutorial/06-dynamic-consistency-boundaries' },
            { text: '7. Reactors', link: '/tutorial/07-reactors' },
            { text: '8. Schema evolution', link: '/tutorial/08-schema-evolution' },
          ],
        },
      ],
      '/concepts/': [
        {
          text: 'Concepts',
          items: [
            { text: 'Deciders', link: '/concepts/deciders' },
            { text: 'Environment, identity, and time', link: '/concepts/environment-identity-and-time' },
            { text: 'Selections', link: '/concepts/selections' },
            { text: 'Idempotency and concurrency', link: '/concepts/idempotency-and-concurrency' },
            { text: 'Read models', link: '/concepts/read-models' },
            { text: 'Reactors and process managers', link: '/concepts/reactors-and-process-managers' },
            { text: 'Consistency boundaries', link: '/concepts/consistency-boundaries' },
            { text: 'Reversals', link: '/concepts/reversals' },
            { text: 'Schema evolution and storage', link: '/concepts/schema-evolution-and-storage' },
            { text: 'Preview', link: '/concepts/preview' },
            { text: 'Closing the books and snapshots', link: '/concepts/closing-and-snapshots' },
            { text: 'Sealing and shredding', link: '/concepts/sealing-and-shredding' },
            { text: 'Testing', link: '/concepts/testing' },
          ],
        },
      ],
      '/design/': designSidebar(),
      '/adr/': designSidebar(),
      '/reference/': [
        {
          text: 'Reference',
          items: [
            { text: 'core (@strata)', link: '/reference/core' },
            { text: 'codec', link: '/reference/codec' },
            { text: 'store', link: '/reference/store' },
            { text: 'runtime (@rt)', link: '/reference/runtime' },
            { text: 'testing', link: '/reference/testing' },
            { text: 'Errors', link: '/reference/errors' },
            { text: 'Stored format', link: '/reference/stored-format' },
            { text: 'Examples', link: '/reference/examples' },
            { text: 'API conventions', link: '/reference/conventions' },
          ],
        },
      ],
      '/project/': projectSidebar(),
      '/ROADMAP': projectSidebar(),
    },

    search: { provider: 'local' },
    editLink: {
      pattern: `${repo}/edit/main/docs/:path`,
      text: 'Edit this page on GitHub',
    },
    socialLinks: [{ icon: 'github', link: repo }],
    footer: {
      message: 'Released under the Apache-2.0 License.',
      copyright: 'Copyright © 2026 tanden inc.',
    },
    outline: { level: [2, 3] },
  },
})

function guideSidebar() {
  return [
    {
      text: 'Introduction',
      items: [
        { text: 'Why Strata', link: '/introduction/why-strata' },
        { text: 'Event sourcing in one page', link: '/introduction/event-sourcing-primer' },
        { text: 'Status and stability', link: '/introduction/status-and-stability' },
        { text: 'Compared to other tools', link: '/introduction/comparison' },
      ],
    },
    {
      text: 'Getting started',
      items: [
        { text: 'Installation', link: '/guide/installation' },
        { text: 'Quickstart', link: '/guide/quickstart' },
      ],
    },
  ]
}

function designSidebar() {
  return [
    {
      text: 'Design',
      items: [
        { text: 'Principles', link: '/design/principles' },
        { text: 'Architecture', link: '/design/architecture' },
        { text: 'HTTP and GraphQL (planned)', link: '/design/http-and-graphql' },
        { text: 'FAQ', link: '/design/faq' },
      ],
    },
    {
      text: 'Decision records',
      items: [
        { text: 'Index', link: '/adr/' },
        { text: '0001 Store as a trait', link: '/adr/0001-store-as-trait' },
        { text: '0002 JSON layout', link: '/adr/0002-json-layout' },
        { text: '0003 Ids, time, and system tags', link: '/adr/0003-ids-time-and-system-tags' },
        { text: '0004 Idempotency', link: '/adr/0004-idempotency' },
        { text: '0005 Atomic read-side commit', link: '/adr/0005-atomic-read-side-commit' },
        { text: '0006 Id batches and reactor failure', link: '/adr/0006-id-batches-and-reactor-failure' },
      ],
    },
  ]
}

function projectSidebar() {
  return [
    {
      text: 'Project',
      items: [
        { text: 'Roadmap', link: '/ROADMAP' },
        { text: 'Changelog', link: '/project/changelog' },
        { text: 'Contributing', link: '/project/contributing' },
      ],
    },
  ]
}
