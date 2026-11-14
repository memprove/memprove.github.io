// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// The site is static and served by GitHub Pages at https://memprove.dev.
// Docs pages are generated into src/content/docs/ by scripts/sync-docs.mjs from
// the memprove/memprove repository; nothing there is edited by hand.
export default defineConfig({
  site: 'https://memprove.dev',
  // Keep whitespace between inline elements; the homepage relies on it.
  compressHTML: false,
  trailingSlash: 'always',
  build: { format: 'directory' },
  integrations: [
    starlight({
      title: 'memprove',
      description:
        'Agent memory that is checked, not trusted: every fact a coding agent records is bound to a commit, the worktree and a passing test run.',
      logo: { src: './src/assets/mark.svg', alt: '' },
      // Recorded transcripts are long; wrap them instead of scrolling sideways.
      expressiveCode: { defaultProps: { overridesByLang: { 'text,txt,plaintext': { wrap: true } } } },
      favicon: '/favicon.svg',
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/memprove/memprove' }],
      customCss: [
        '@fontsource/inter/latin-400.css',
        '@fontsource/inter/latin-500.css',
        '@fontsource/inter/latin-600.css',
        '@fontsource/inter/latin-700.css',
        '@fontsource-variable/source-serif-4/opsz.css',
        '@fontsource/ibm-plex-mono/latin-400.css',
        '@fontsource/ibm-plex-mono/latin-600.css',
        './src/styles/tokens.css',
        './src/styles/starlight.css',
      ],
      components: {
        SocialIcons: './src/components/starlight/SocialIcons.astro',
        Footer: './src/components/starlight/Footer.astro',
      },
      disable404Route: true,
      lastUpdated: false,
      pagination: true,
      tableOfContents: { minHeadingLevel: 2, maxHeadingLevel: 3 },
      sidebar: [
        { label: 'Quickstart', link: '/docs/' },
        {
          label: "The agent's guide",
          items: [{ label: 'Overview', link: '/docs/guide/' }, { autogenerate: { directory: 'docs/guide' } }],
        },
        { label: 'How it works', link: '/how-it-works/' },
        { label: 'Changelog', link: '/changelog/' },
        // An absolute URL, so Starlight does not add a trailing slash to a file.
        { label: 'For agents: llms.txt', link: 'https://memprove.dev/llms.txt' },
      ],
      head: [
        { tag: 'meta', attrs: { property: 'og:image', content: 'https://memprove.dev/og.png' } },
        { tag: 'meta', attrs: { name: 'twitter:card', content: 'summary_large_image' } },
        { tag: 'link', attrs: { rel: 'alternate', type: 'text/plain', title: 'llms.txt', href: '/llms.txt' } },
      ],
    }),
  ],
});
