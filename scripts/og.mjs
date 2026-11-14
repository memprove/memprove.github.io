// Renders public/og.png (1200 x 630), the image link previews show.
// Run it after changing the headline or the verdict colours: node scripts/og.mjs
// Needs Playwright with Chromium; the PNG is committed, so the site build does not.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';

// Playwright is not a dependency of the site: use a global install (NODE_PATH=$(npm root -g)) or npx.
const { chromium } = createRequire(import.meta.url)('playwright');

const root = new URL('../', import.meta.url).pathname;
const font = (p) => `url(data:font/woff2;base64,${readFileSync(root + 'node_modules/' + p).toString('base64')}) format('woff2')`;
const mark = readFileSync(root + 'src/assets/mark.svg', 'utf8').replace('width="24" height="24"', 'width="44" height="44"');
const release = JSON.parse(readFileSync(root + 'src/data/release.json', 'utf8'));

const html = `<!doctype html><html><head><meta charset="utf-8"><style>
@font-face { font-family: Inter; font-weight: 600; src: ${font('@fontsource/inter/files/inter-latin-600-normal.woff2')}; }
@font-face { font-family: Inter; font-weight: 700; src: ${font('@fontsource/inter/files/inter-latin-700-normal.woff2')}; }
@font-face { font-family: Serif; src: ${font('@fontsource-variable/source-serif-4/files/source-serif-4-latin-opsz-normal.woff2')}; }
@font-face { font-family: Mono; font-weight: 400; src: ${font('@fontsource/ibm-plex-mono/files/ibm-plex-mono-latin-400-normal.woff2')}; }
@font-face { font-family: Mono; font-weight: 600; src: ${font('@fontsource/ibm-plex-mono/files/ibm-plex-mono-latin-600-normal.woff2')}; }
* { box-sizing: border-box; margin: 0; }
body { width: 1200px; height: 630px; overflow: hidden; background: #fbfaf7;
  background-image: linear-gradient(rgba(29,31,33,.05) 1px, transparent 1px), linear-gradient(90deg, rgba(29,31,33,.05) 1px, transparent 1px);
  background-size: 24px 24px; font-family: Inter; color: #1d1f21; padding: 64px 72px; display: flex; flex-direction: column; }
.brand { display: flex; align-items: center; gap: 16px; font-weight: 600; font-size: 34px; letter-spacing: -0.01em; }
.cap { margin-top: 40px; font-family: Mono; font-size: 20px; color: #5d6166; }
h1 { margin-top: 14px; font-weight: 700; font-size: 74px; line-height: 1.02; letter-spacing: -0.035em; max-width: 980px; }
.badges { margin-top: auto; display: flex; gap: 14px; }
.b { display: flex; align-items: center; gap: 10px; border: 1px solid #d4d0c6; background: #fff; padding: 10px 16px; font-family: Mono; font-weight: 600; font-size: 22px; }
.sq { width: 18px; height: 18px; border: 2px solid currentColor; }
.ok { color: #1f6f4a; } .ok .sq { background: currentColor; }
.st { color: #9a5b00; } .st .sq { background: repeating-linear-gradient(135deg, currentColor 0 2px, transparent 2px 5px); }
.un { color: #4a5a6e; }
.bad { color: #a3271f; } .bad .sq { background: repeating-linear-gradient(45deg, currentColor 0 2px, transparent 2px 4px), repeating-linear-gradient(135deg, currentColor 0 2px, transparent 2px 4px); }
.url { position: absolute; right: 72px; top: 72px; font-family: Mono; font-size: 22px; color: #5d6166; }
</style></head><body>
<div class="brand">${mark}<span>memprove</span></div>
<div class="url">memprove.dev</div>
<p class="cap">[ v${release.version} · open source · for coding agents ]</p>
<h1>Agent memory that is checked, not trusted.</h1>
<div class="badges">
  <span class="b ok"><span class="sq"></span>verified</span>
  <span class="b st"><span class="sq"></span>stale</span>
  <span class="b un"><span class="sq"></span>unconfirmed</span>
  <span class="b bad"><span class="sq"></span>tampered</span>
</div>
</body></html>`;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
await page.setContent(html, { waitUntil: 'load' });
await page.evaluate(() => document.fonts.ready);
await page.screenshot({ path: root + 'public/og.png' });
await browser.close();
console.log('wrote public/og.png');
