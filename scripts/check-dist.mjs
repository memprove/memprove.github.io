// Checks the built site in dist/ before it is deployed. Exits 1 on the first run with problems.
//   - the pages, raw Markdown copies, agent files and install.sh exist
//   - every internal link and #fragment in the HTML, and every link in llms.txt, resolves
//   - the homepage stays under its size budget (HTML + CSS + JS, fonts excluded)
//   - nothing from a build machine (home paths) leaked into the output
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const dist = new URL('../dist/', import.meta.url).pathname;
const SITE = 'https://memprove.dev';
const HOME_BUDGET = 150 * 1024;
const problems = [];
const fail = (msg) => problems.push(msg);

// ---- required files
const required = [
  'index.html',
  '404.html',
  'about/index.html',
  'roadmap/index.html',
  'benchmark/index.html',
  'zh/index.html',
  'tune/index.html',
  'zh/tune/index.html',
  'tune/install.sh',
  'docs/index.html',
  'docs/index.md',
  'docs/guide/index.html',
  'docs/guide/index.md',
  'how-it-works/index.html',
  'how-it-works.md',
  'changelog/index.html',
  'changelog.md',
  'llms.txt',
  'llms-full.txt',
  'robots.txt',
  'sitemap-index.xml',
  'favicon.svg',
  'og.png',
  'CNAME',
  'install.sh',
];
for (const f of required) if (!existsSync(join(dist, f))) fail(`missing ${f}`);
if (existsSync(join(dist, 'CNAME')) && readFileSync(join(dist, 'CNAME'), 'utf8').trim() !== 'memprove.dev') fail('CNAME is not memprove.dev');
// The installers are served as written: POSIX sh scripts whose last line runs main. scripts/test-install.sh tests
// memprove's; memprove-tune's is a copy of scripts/install.sh in its repository, which tests it there.
for (const f of ['install.sh', 'tune/install.sh']) {
  if (!existsSync(join(dist, f))) continue;
  const sh = readFileSync(join(dist, f), 'utf8');
  if (!sh.startsWith('#!/bin/sh\n') || !sh.endsWith('\nmain "$@"\n')) fail(`${f} does not start with #!/bin/sh or does not end with main "$@"`);
}

// ---- collect HTML pages and their ids
function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });
}
const files = walk(dist);
const html = files.filter((f) => f.endsWith('.html') && !f.includes('/pagefind/'));
const ids = new Map();
for (const f of html) {
  const src = readFileSync(f, 'utf8');
  ids.set(f, new Set([...src.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1])));
}

/** Maps a site path to the file that serves it, or null. */
function target(path) {
  const clean = decodeURIComponent(path.split('#')[0].split('?')[0]);
  if (clean === '' || clean === '/') return join(dist, 'index.html');
  const p = join(dist, clean);
  if (clean.endsWith('/')) return existsSync(join(p, 'index.html')) ? join(p, 'index.html') : null;
  if (existsSync(p) && statSync(p).isFile()) return p;
  return null;
}

// ---- internal links in HTML
let checked = 0;
for (const f of html) {
  const src = readFileSync(f, 'utf8');
  const page = '/' + relative(dist, f).replace(/index\.html$/, '');
  for (const m of src.matchAll(/\s(?:href|src)="([^"]+)"/g)) {
    let url = m[1].replace(/&amp;/g, '&');
    if (url.startsWith(SITE)) url = url.slice(SITE.length) || '/';
    if (url.startsWith('#')) url = page + url;
    if (!url.startsWith('/') || url.startsWith('//')) continue;
    checked += 1;
    const t = target(url);
    if (!t) {
      fail(`${relative(dist, f)}: broken link ${m[1]}`);
      continue;
    }
    const frag = url.split('#')[1];
    if (frag && t.endsWith('.html') && !ids.get(t)?.has(decodeURIComponent(frag))) fail(`${relative(dist, f)}: no #${frag} in ${relative(dist, t)}`);
  }
}

// ---- links in llms.txt
const llms = existsSync(join(dist, 'llms.txt')) ? readFileSync(join(dist, 'llms.txt'), 'utf8') : '';
if (!/^# memprove\n\n> /.test(llms)) fail('llms.txt does not start with "# memprove" and a summary blockquote');
for (const m of llms.matchAll(/https:\/\/memprove\.dev(\/[^\s)`"]*)/g)) {
  checked += 1;
  if (!target(m[1])) fail(`llms.txt: broken link ${m[0]}`);
}

// ---- homepage budget: the HTML and the CSS and JS it loads
const home = readFileSync(join(dist, 'index.html'), 'utf8');
let bytes = Buffer.byteLength(home);
const assets = new Set([...home.matchAll(/(?:href|src)="(\/_astro\/[^"]+\.(?:css|js))"/g)].map((m) => m[1]));
for (const a of assets) {
  const t = target(a);
  if (t) bytes += statSync(t).size;
  // follow static imports one level, so a script's chunks count too
  if (t && a.endsWith('.js')) {
    for (const m of readFileSync(t, 'utf8').matchAll(/from\s*"\.\/([^"]+\.js)"/g)) {
      const c = target('/_astro/' + m[1]);
      if (c && !assets.has('/_astro/' + m[1])) {
        assets.add('/_astro/' + m[1]);
        bytes += statSync(c).size;
      }
    }
  }
}
if (bytes > HOME_BUDGET) fail(`homepage is ${Math.round(bytes / 1024)} KB (HTML + CSS + JS), over the ${HOME_BUDGET / 1024} KB budget`);

// ---- nothing from the build machine
const leaks = [/\/Users\/[a-z]/, /\/home\/(?!user\b)[a-z]+\//, /\/home\/user\/work\//];
for (const f of files.filter((x) => /\.(html|md|txt|xml|json)$/.test(x) && !x.includes('/pagefind/'))) {
  const src = readFileSync(f, 'utf8');
  for (const re of leaks) if (re.test(src)) fail(`${relative(dist, f)}: contains a build-machine path (${re})`);
}

if (problems.length) {
  console.error(`check-dist: ${problems.length} problem(s)`);
  for (const p of problems) console.error('  ' + p);
  process.exit(1);
}
console.log(`check-dist: ${html.length} pages, ${checked} internal links, homepage ${Math.round(bytes / 1024)} KB of ${HOME_BUDGET / 1024} KB: OK`);
