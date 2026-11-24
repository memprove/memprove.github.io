// memprove-tune: its release, its install commands and its recorded output
// (src/data/tune/, see the README there). Everything the pages under /tune/
// show in a terminal block or a figure is read from those files at build time.
import tuneJson from '../data/tune.json';
import scanJson from '../data/tune/scan.json';
import verdictsJson from '../data/tune/verdicts.json';

export const tune = tuneJson;

// The one-line installer: public/tune/install.sh, served at memprove.dev/tune/install.sh.
export const tuneInstallCommand = 'curl -fsSL https://memprove.dev/tune/install.sh | sh';
export const tuneSourceCommand = `cargo install --locked --git ${tuneJson.repo} memprove-tune`;
export const tunePluginCommand = '/plugin install memprove-tune --marketplace memprove/memprove-tune';

const files = import.meta.glob<string>('../data/tune/*.txt', { query: '?raw', import: 'default', eager: true });

export function tuneTranscript(name: string): string {
  const hit = Object.entries(files).find(([path]) => path.endsWith(`/${name}.txt`));
  if (!hit) throw new Error(`no recorded output src/data/tune/${name}.txt`);
  return hit[1].replace(/\n+$/, '');
}

export function tuneLine(name: string, test: RegExp): string {
  const found = tuneTranscript(name)
    .split('\n')
    .find((l) => test.test(l));
  if (!found) throw new Error(`src/data/tune/${name}.txt has no line matching ${test}`);
  return found;
}

export type Advice = 'keep' | 'removable' | 'inconclusive';
export type Unit = { id: string; title: string; first: number; last: number; tokens: number; advice: Advice };

/** The verdict `prune` recorded for a unit; the unit's text must be the one that was tested. */
function adviceFor(id: string, sha256: string): Advice {
  const v = verdictsJson.verdicts.find((x) => x.unit === id);
  if (!v) throw new Error(`src/data/tune/verdicts.json has no verdict for ${id}`);
  if (v.sha256 !== sha256) throw new Error(`the verdict for ${id} was measured on another text of the unit`);
  return v.advice as Advice;
}

/** The units of `memprove-tune scan --json`, in file order, with the verdict of the real prune run. */
export const units: Unit[] = scanJson.units.map((u) => ({
  id: u.id,
  title: u.title,
  first: u.first_line,
  last: u.last_line,
  tokens: u.tokens,
  advice: adviceFor(u.id, u.sha256),
}));
export const unitTokens = units.reduce((sum, u) => sum + u.tokens, 0);

/** The arms of the recorded `ab` report: name, passed, of, cost a trial. */
export function arms(): { name: string; passed: number; of: number; cost: string }[] {
  return tuneTranscript('ab')
    .split('\n')
    .map((l) => l.match(/^ {2}(\S.*?) {2,}(\d+)\/(\d+) +[\d.]+% +(\$[\d.]+)/))
    .filter((m): m is RegExpMatchArray => m !== null)
    .map((m) => ({ name: m[1], passed: Number(m[2]), of: Number(m[3]), cost: m[4] }));
}

// Run 3 of memprove-tune's docs/validation.md (2026-11-19 and 11-20): the whole
// configuration against none, on tasks mined from each repository's history.
export const run3 = {
  trials: 536,
  cost: '$260.96',
  rows: [
    { repo: 'modelcontextprotocol/python-sdk', tasks: 88, base: 62, bare: 66, bound: '4.8', verdict: 'no worse', cost: '$83.54' },
    { repo: 'PrefectHQ/fastmcp', tasks: 90, base: 62, bare: 59, bound: '10.9', verdict: 'not enough evidence', cost: '$84.75' },
    { repo: 'openai/openai-agents-python', tasks: 90, base: 57, bare: 59, bound: '8.8', verdict: 'no worse', cost: '$92.67' },
  ],
};
