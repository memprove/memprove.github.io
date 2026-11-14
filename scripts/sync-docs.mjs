#!/usr/bin/env node
// Generates the documentation pages, their raw Markdown and llms.txt from the
// memprove/memprove repository, so the site and the repository never fork.
//
//   MEMPROVE_REPO=../memprove node scripts/sync-docs.mjs   # a local checkout
//   node scripts/sync-docs.mjs                             # clones main into .cache/memprove
//   MEMPROVE_REF=v0.1.0 node scripts/sync-docs.mjs         # another branch or tag
//   SYNC_OFFLINE=1 ...                                     # no GitHub API calls (releases, stars)
//
// Writes (all git-ignored): src/content/docs/**, public/docs/**.md,
// public/llms.txt, public/llms-full.txt, src/data/generated/*.json.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const site = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SITE_URL = 'https://memprove.dev';
const REPO_URL = 'https://github.com/memprove/memprove';
const release = JSON.parse(readFileSync(join(site, 'src/data/release.json'), 'utf8'));

// ---------------------------------------------------------------- source
function sourceDir() {
  if (process.env.MEMPROVE_REPO) return resolve(process.env.MEMPROVE_REPO);
  const dir = join(site, '.cache/memprove');
  const ref = process.env.MEMPROVE_REF || 'main';
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dirname(dir), { recursive: true });
  execFileSync('git', ['clone', '--quiet', '--depth', '1', '--branch', ref, `${REPO_URL}.git`, dir], {
    stdio: 'inherit',
  });
  return dir;
}

const src = sourceDir();
const read = (p) => readFileSync(join(src, p), 'utf8');
let commit = 'unknown';
try {
  commit = execFileSync('git', ['-C', src, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
} catch {
  /* a source directory without .git */
}

// ---------------------------------------------------------------- markdown helpers
/** Splits Markdown into a preface and its sections at headings of `level`, outside code fences. */
function splitSections(md, level) {
  const marker = '#'.repeat(level) + ' ';
  const lines = md.split('\n');
  const out = { preface: [], sections: [] };
  let fence = null;
  let cur = null;
  for (const line of lines) {
    const f = line.match(/^(\s*)(`{3,}|~{3,})/);
    if (f) {
      if (!fence) fence = f[2];
      else if (line.trim().startsWith(fence)) fence = null;
    }
    if (!fence && line.startsWith(marker)) {
      cur = { heading: line.slice(marker.length).trim(), body: [] };
      out.sections.push(cur);
      continue;
    }
    (cur ? cur.body : out.preface).push(line);
  }
  const trim = (a) => a.join('\n').replace(/^\n+|\n+$/g, '');
  return {
    preface: trim(out.preface),
    sections: out.sections.map((s) => ({ heading: s.heading, body: trim(s.body) })),
  };
}

const plain = (s) => s.replace(/`/g, '').trim();
function slugify(heading) {
  return plain(heading)
    .replace(/\(.*?\)/g, '')
    .replace(/:.*$/, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

/** The first sentence of the first paragraph, as plain text, for a page description. */
function describe(body) {
  const para = body
    .split(/\n\s*\n/)
    .find((p) => p.trim() && !/^\s*(```|\||[-*] |\d+\. |#)/.test(p));
  if (!para) return undefined;
  const text = para
    .replace(/\s+/g, ' ')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/[`*_]/g, '')
    .trim();
  const m = text.match(/^(.+?[.:])(\s|$)/);
  let d = (m ? m[1] : text).replace(/:$/, '.');
  if (d.length > 200) d = d.slice(0, 197).replace(/\s+\S*$/, '') + '…';
  return d;
}

// docs/takeover-eval.md still speaks the project's internal language (task numbers, Owner
// decisions, ADRs). It gets a page of its own once it is rewritten for readers; until then
// links to it go to GitHub. See the Roadmap page.
const PUBLISH_TAKEOVER_EVAL = false;

/** Links between the repository's own files become links to this site or to GitHub. */
function rewriteLinks(md) {
  const map = {
    'guide.md': '/docs/guide/',
    'docs/guide.md': '/docs/guide/',
    'architecture.md': '/how-it-works/',
    'docs/architecture.md': '/how-it-works/',
    ...(PUBLISH_TAKEOVER_EVAL ? { 'takeover-eval.md': '/docs/takeover-eval/', 'docs/takeover-eval.md': '/docs/takeover-eval/' } : {}),
    'CHANGELOG.md': '/changelog/',
  };
  return md.replace(/\]\(([^)\s]+)\)/g, (all, target) => {
    if (/^[a-z]+:|^#|^\//.test(target)) return all;
    const clean = target.replace(/^\.\//, '').replace(/^\.\.\//, '');
    if (map[clean]) return `](${map[clean]})`;
    return `](${REPO_URL}/blob/${commit}/${clean})`;
  });
}

/** Moves every heading down `by` levels (outside code fences). */
function demoteHeadings(md, by) {
  let fence = null;
  return md
    .split('\n')
    .map((line) => {
      const f = line.match(/^\s*(`{3,}|~{3,})/);
      if (f) {
        if (!fence) fence = f[1];
        else if (line.trim().startsWith(fence)) fence = null;
        return line;
      }
      if (fence) return line;
      return line.replace(/^(#{1,5}) /, (h, hashes) => '#'.repeat(Math.min(6, hashes.length + by)) + ' ');
    })
    .join('\n');
}

const yaml = (v) => JSON.stringify(v);
function frontmatter(fields) {
  const lines = ['---'];
  for (const [k, v] of Object.entries(fields)) {
    if (v === undefined) continue;
    if (typeof v === 'object') {
      lines.push(`${k}:`);
      for (const [k2, v2] of Object.entries(v)) lines.push(`  ${k2}: ${yaml(v2)}`);
    } else lines.push(`${k}: ${yaml(v)}`);
  }
  lines.push('---', '');
  return lines.join('\n');
}

// ---------------------------------------------------------------- output
const contentDir = join(site, 'src/content/docs');
const rawDir = join(site, 'public');
const genDir = join(site, 'src/data/generated');
for (const d of [contentDir, join(rawDir, 'docs'), genDir]) rmSync(d, { recursive: true, force: true });
mkdirSync(contentDir, { recursive: true });
mkdirSync(genDir, { recursive: true });

/** Every page written, for llms.txt and llms-full.txt, in reading order. */
const pages = [];

/**
 * route: the page's URL path ('/docs/guide/context-pack/').
 * raw: where its Markdown is served ('/docs/guide/context-pack.md').
 */
function writePage({ route, file, title, body, description, sidebar, group, sourcePath }) {
  const source = sourcePath ? `${REPO_URL}/blob/${commit}/${sourcePath}` : undefined;
  const fm = frontmatter({ title, description, sidebar, editUrl: false });
  const note = sourcePath
    ? `\n\n<p class="mp-source">From <a href="${source}"><code>${sourcePath}</code></a> at <code>${commit.slice(0, 12)}</code> · <a href="${rawPath(route)}">Markdown</a></p>\n`
    : '';
  const out = join(contentDir, file);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, fm + body + note);
  const raw = rawPath(route);
  const rawOut = join(rawDir, raw);
  mkdirSync(dirname(rawOut), { recursive: true });
  writeFileSync(rawOut, `# ${title}\n\n${body}\n`);
  pages.push({ route, raw, title, description, group, body });
}
function rawPath(route) {
  const r = route.replace(/\/$/, '');
  return r === '/docs' || r.endsWith('/guide') ? `${r}/index.md` : `${r}.md`;
}

// ---- Quickstart, from the README and the release
const readme = splitSections(read('README.md'), 2);
const readmeSection = (name) => {
  const s = readme.sections.find((x) => x.heading === name);
  if (!s) throw new Error(`README.md has no section "${name}"`);
  return s.body;
};
const fragment = (name) => readFileSync(join(site, 'src/fragments', name), 'utf8');
const fill = (text) =>
  text
    .replace(/\{\{version\}\}/g, release.version)
    .replace(/\{\{tag\}\}/g, release.tag)
    .replace(/\{\{base\}\}/g, release.base)
    .replace(/\{\{readme:([^}]+)\}\}/g, (_, name) => rewriteLinks(readmeSection(name.trim())))
    .replace(/\{\{readme-intro\}\}/g, () => rewriteLinks(readme.preface.replace(/^# .*\n+/, '')))
    .replace(/\{\{demo:([^}]+)\}\}/g, (_, name) => demo(name.trim()));
function demo(name) {
  const p = join(site, 'src/data/demo', `${name}.txt`);
  return readFileSync(p, 'utf8').replace(/\n+$/, '');
}

writePage({
  route: '/docs/',
  file: 'docs/index.md',
  title: 'Quickstart',
  description: `Install memprove ${release.version}, enable a repository with memprove init, and record a first fact on a passing test run.`,
  body: fill(fragment('quickstart.md')),
  group: 'Docs',
});

// ---- The agent's guide, one page per ## section
const guide = splitSections(read('docs/guide.md'), 2);
const guideIntro = guide.preface.replace(/^# .*\n+/, '');
const guidePages = guide.sections.map((s, i) => ({
  ...s,
  slug: slugify(s.heading),
  order: i + 1,
  title: plain(s.heading),
}));
const toc = guidePages.map((g) => `- [${g.title}](/docs/guide/${g.slug}/)`).join('\n');
writePage({
  route: '/docs/guide/',
  file: 'docs/guide/index.md',
  title: "The agent's guide",
  description: describe(guideIntro),
  body: rewriteLinks(guideIntro) + '\n\n## Sections\n\n' + toc,
  sidebar: { hidden: true },
  group: "The agent's guide",
  sourcePath: 'docs/guide.md',
});
for (const g of guidePages) {
  writePage({
    route: `/docs/guide/${g.slug}/`,
    file: `docs/guide/${g.slug}.md`,
    title: g.title,
    description: describe(g.body),
    body: rewriteLinks(g.body),
    sidebar: { order: g.order },
    group: "The agent's guide",
    sourcePath: 'docs/guide.md',
  });
}

// ---- How it works: real output first, then architecture.md
const arch = read('docs/architecture.md').replace(/^# .*\n+/, '');
writePage({
  route: '/how-it-works/',
  file: 'how-it-works.md',
  title: 'How it works',
  description:
    'How memprove decides whether a fact still holds: a recorded session in a real repository, then the daemon, the ledger, Evidence and verdicts.',
  body: fill(fragment('how-it-works.md')) + '\n\n' + demoteHeadings(rewriteLinks(arch), 1),
  group: 'Docs',
  sourcePath: 'docs/architecture.md',
});

// ---- Takeover evaluation, one page (see PUBLISH_TAKEOVER_EVAL)
const eva = read('docs/takeover-eval.md').replace(/^# .*\n+/, '');
if (PUBLISH_TAKEOVER_EVAL) writePage({
  route: '/docs/takeover-eval/',
  file: 'docs/takeover-eval.md',
  title: 'Takeover evaluation',
  description: describe(eva),
  body: rewriteLinks(eva),
  group: 'Docs',
  sourcePath: 'docs/takeover-eval.md',
});

// ---- Changelog: the GitHub Releases, then CHANGELOG.md
async function githubJson(path) {
  if (process.env.SYNC_OFFLINE) return null;
  const headers = { accept: 'application/vnd.github+json', 'user-agent': 'memprove-site-build' };
  if (process.env.GITHUB_TOKEN) headers.authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  try {
    const res = await fetch(`https://api.github.com${path}`, { headers, signal: AbortSignal.timeout(10000) });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.json();
  } catch (err) {
    // A machine with the GitHub CLI signed in (or behind a proxy that serves it) can still answer.
    try {
      return JSON.parse(execFileSync('gh', ['api', path], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }));
    } catch {
      console.warn(`sync-docs: GET ${path} failed (${err.message}); using the fallback`);
      return null;
    }
  }
}
const apiReleases = await githubJson('/repos/memprove/memprove/releases?per_page=20');
const releases = (apiReleases ?? [])
  .filter((r) => !r.draft)
  .map((r) => ({ tag: r.tag_name, name: r.name || r.tag_name, date: (r.published_at || '').slice(0, 10), url: r.html_url, body: r.body || '' }));
if (releases.length === 0) {
  releases.push({ tag: release.tag, name: `memprove ${release.version}`, date: release.date, url: `${REPO_URL}/releases/tag/${release.tag}`, body: '' });
}
const repoInfo = await githubJson('/repos/memprove/memprove');
writeFileSync(
  join(genDir, 'repo.json'),
  JSON.stringify({ stars: repoInfo?.stargazers_count ?? null, commit, releases: releases.map(({ body, ...r }) => r) }, null, 2),
);

const releaseNotes = releases
  .map((r) => `## [${r.name}](${r.url}) · ${r.date}\n\n${r.body ? demoteHeadings(r.body.trim(), 1) : `Release notes: [${r.tag} on GitHub](${r.url}).`}`)
  .join('\n\n');
const changelog = read('CHANGELOG.md').replace(/^# .*\n+/, '');
writePage({
  route: '/changelog/',
  file: 'changelog.md',
  title: 'Changelog',
  description: 'Releases of memprove and the changes in the repository since.',
  body: `${releaseNotes}\n\n## CHANGELOG.md\n\nThe repository's own record, as it stands on \`main\`.\n\n${demoteHeadings(rewriteLinks(changelog), 1)}`,
  group: 'Docs',
  sourcePath: 'CHANGELOG.md',
});

// ---------------------------------------------------------------- llms.txt
const absolute = (p) => `${SITE_URL}${p}`;
const listed = pages
  .map((p) => `- [${p.title}](${absolute(p.raw)})${p.description ? `: ${p.description}` : ''}`)
  .join('\n');
const llms = fill(fragment('llms.md')).replace('{{pages}}', listed).replace('{{commit}}', commit.slice(0, 12));
writeFileSync(join(rawDir, 'llms.txt'), llms.replace(/\n+$/, '') + '\n');

const full = [
  `# memprove documentation (full text)\n\n> Every page of ${SITE_URL}/docs/ as Markdown, from ${REPO_URL} at ${commit.slice(0, 12)}. The setup steps for an agent are in ${SITE_URL}/llms.txt.`,
  ...pages.map((p) => `# ${p.title}\n\nSource: ${absolute(p.route)}\n\n${p.body}`),
].join('\n\n---\n\n');
writeFileSync(join(rawDir, 'llms-full.txt'), full + '\n');

writeFileSync(join(genDir, 'pages.json'), JSON.stringify(pages.map(({ body, ...p }) => p), null, 2));
console.log(`sync-docs: ${pages.length} pages from ${src} at ${commit.slice(0, 12)}; releases ${releases.map((r) => r.tag).join(', ')}; stars ${repoInfo?.stargazers_count ?? 'unknown'}`);
