// The recorded session in tinyini (demo/record.sh writes src/data/demo/*.txt).
// Everything the homepage shows about it is read from those files at build time.
const files = import.meta.glob<string>('../data/demo/*.txt', { query: '?raw', import: 'default', eager: true });

export function transcript(name: string): string {
  const hit = Object.entries(files).find(([path]) => path.endsWith(`/${name}.txt`));
  if (!hit) throw new Error(`no recorded output demo/${name}.txt; run demo/record.sh`);
  return hit[1].replace(/\n+$/, '');
}

/** The output lines, without the "$ command" line the recorder wrote first. */
export function output(name: string): string[] {
  return transcript(name).split('\n').slice(1);
}

export function line(name: string, test: RegExp): string {
  const found = transcript(name)
    .split('\n')
    .find((l) => test.test(l));
  if (!found) throw new Error(`demo/${name}.txt has no line matching ${test}`);
  return found;
}

export type Verdict = 'verified' | 'stale' | 'unconfirmed' | 'tampered';
export type Fact = { n: number; verdict: Verdict; text: string; commit: string };

/** The facts of a `memprove resume --text` transcript. */
export function facts(name: string): Fact[] {
  return output(name)
    .map((l) => l.match(/^#(\d+) (verified|fact stale|fact unconfirmed|fact tampered|unconfirmed|tampered): 「(.*?)」 \(evidence bound to commit ([0-9a-f]{12})/))
    .filter((m): m is RegExpMatchArray => m !== null)
    .map((m) => ({ n: Number(m[1]), verdict: m[2].replace('fact ', '') as Verdict, text: m[3], commit: m[4] }));
}

export function head(name: string): string {
  const m = transcript(name).match(/current HEAD ([0-9a-f]{40})/);
  if (!m) throw new Error(`demo/${name}.txt names no current HEAD`);
  return m[1];
}

/** "recorded PASS, 8 test cases, evidence_id …, label r1" → { status, cases, label } */
export function run(name: string) {
  const m = line(name, /^memprove: recorded /).match(/recorded (\w+), (\d+) test cases?, .*label (r\d+)/);
  if (!m) throw new Error(`demo/${name}.txt has no run summary`);
  return { status: m[1], cases: Number(m[2]), label: m[3] };
}

export function commits(): { sha: string; subject: string }[] {
  return transcript('00-about')
    .split('\n')
    .map((l) => l.match(/^commit ([0-9a-f]{40}) (.*)$/))
    .filter((m): m is RegExpMatchArray => m !== null)
    .map((m) => ({ sha: m[1], subject: m[2] }))
    .reverse();
}

export const about = () => transcript('00-about').split('\n').slice(0, 3);
