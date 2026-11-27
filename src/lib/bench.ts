// The memory benchmark M3 v2 (2026-11-26). Everything /benchmark/ shows is read at build time
// from bench/m3-v2/: the kit as it ran (kit/) and the files its collect step wrote (results/).
// bench/README.md says where each file comes from; nothing here is typed by hand, and the build
// fails if results.md and results.json, both written by the kit's collect step, disagree.
const files = import.meta.glob<string>(['../../bench/m3-v2/results/*.{md,txt,json}', '../../bench/m3-v2/kit/{README.md,build_fixture.py}'], {
  query: '?raw',
  import: 'default',
  eager: true,
});

function file(name: string): string {
  const hit = Object.entries(files).find(([path]) => path.endsWith(`/bench/m3-v2/${name}`));
  if (!hit) throw new Error(`no file bench/m3-v2/${name}`);
  return hit[1];
}

export const benchRepo = 'https://github.com/memprove/memprove.github.io';
export const kitUrl = `${benchRepo}/tree/main/bench/m3-v2/kit`;
export const resultsUrl = `${benchRepo}/tree/main/bench/m3-v2/results`;
export const resultsMdUrl = `${benchRepo}/blob/main/bench/m3-v2/results/results.md`;
export const packUrl = `${benchRepo}/blob/main/bench/m3-v2/results/pack-at-main.txt`;
export const sessionsUrl = `${benchRepo}/blob/main/bench/m3-v2/results/results.json`;

export type Cell = { passed: number; of: number };
export type Comparison = { a: string; b: string; kind: string; pairs: number; aOnly: number; bOnly: number; verdict: string; p: string };
export type ModelResult = {
  model: string;
  arms: string[];
  tasks: { task: string; kind: string; cells: Cell[] }[];
  kinds: { kind: string; cells: Cell[] }[];
  cost: string[];
  turns: string[];
  comparisons: Comparison[];
};

const cells = (row: string[]): Cell[] =>
  row.map((c) => {
    const m = c.match(/^(\d+)\/(\d+)$/);
    if (!m) throw new Error(`bench/m3-v2/results/results.md: "${c}" is not passed/trials`);
    return { passed: Number(m[1]), of: Number(m[2]) };
  });

/** One `## <model>` section of results.md: the pass table, then the comparisons. */
function parseModel(section: string): ModelResult {
  const [head, ...lines] = section.split('\n');
  const model = head.trim();
  const rows = lines
    .filter((l) => l.startsWith('| '))
    .map((l) => l.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map((c) => c.trim()));
  const header = rows.find((r) => r[0] === 'task');
  if (!header) throw new Error(`results.md, ${model}: no task table`);
  const arms = header.slice(2);
  const res: ModelResult = { model, arms, tasks: [], kinds: [], cost: [], turns: [], comparisons: [] };
  for (const r of rows) {
    if (r[0] === 'task' || r[0] === 'comparison') continue;
    const all = r[0].match(/^\*\*all (.+)\*\*$/);
    if (all) res.kinds.push({ kind: all[1], cells: cells(r.slice(2)) });
    else if (r[0] === 'mean cost per trial (USD)') res.cost = r.slice(2);
    else if (r[0] === 'mean turns per trial') res.turns = r.slice(2);
    else if (r.length === 6) {
      const [ab, kind, pairs, aOnly, bOnly, verdict] = r;
      const [a, b] = ab.split(' vs ');
      const v = verdict.match(/^(.*) \(p ([\d.]+) \/ [\d.]+\)$/);
      if (!v) throw new Error(`results.md, ${model}: cannot read the verdict "${verdict}"`);
      res.comparisons.push({ a, b, kind, pairs: Number(pairs), aOnly: Number(aOnly), bOnly: Number(bOnly), verdict: v[1], p: v[2] });
    } else res.tasks.push({ task: r[0], kind: r[1], cells: cells(r.slice(2)) });
  }
  if (res.tasks.length !== 8 || res.kinds.length !== 3 || res.comparisons.length !== 3 || res.cost.length !== arms.length)
    throw new Error(`results.md, ${model}: expected 8 tasks, 3 kinds, 3 comparisons and a cost per arm`);
  return res;
}

const resultsMd = file('results/results.md');
export const models: ModelResult[] = resultsMd
  .split('\n## ')
  .slice(1)
  .map(parseModel);

const total = resultsMd.match(/^Trials: (\d+); spent: ([\d.]+) USD/m);
if (!total) throw new Error('results.md: no "Trials: …; spent: … USD" line');
export const trials = Number(total[1]);
export const spent = `$${total[2]}`;

/** Every session as results.json records it (collect.py wrote results.md from the same records). */
type Session = {
  round: number;
  model: string;
  arm: string;
  task: string;
  outcome: string;
  cost_usd: number;
  turns: number | null;
  agent_ms: number | null;
};
export const sessions: Session[] = JSON.parse(file('results/results.json')).trials;

// results.md must say what results.json holds: every pass count, mean cost and mean turns, and the total.
if (sessions.length !== trials) throw new Error(`results.json has ${sessions.length} sessions, results.md says ${trials}`);
const sumOf = (xs: number[]) => xs.reduce((a, b) => a + b, 0);
for (const m of models) {
  m.arms.forEach((a, i) => {
    const mine = sessions.filter((x) => x.model === m.model && x.arm === a);
    for (const t of m.tasks) {
      const s = mine.filter((x) => x.task === t.task);
      const passed = s.filter((x) => x.outcome === 'passed').length;
      if (s.length !== t.cells[i].of || passed !== t.cells[i].passed)
        throw new Error(`${m.model} ${a} ${t.task}: results.md says ${t.cells[i].passed}/${t.cells[i].of}, results.json ${passed}/${s.length}`);
    }
    const cost = (sumOf(mine.map((x) => x.cost_usd)) / mine.length).toFixed(3);
    const turns = (sumOf(mine.map((x) => x.turns ?? 0)) / mine.length).toFixed(1);
    if (cost !== m.cost[i] || turns !== m.turns[i])
      throw new Error(`${m.model} ${a}: results.md says ${m.cost[i]} USD and ${m.turns[i]} turns, results.json ${cost} and ${turns}`);
  });
}
if (sumOf(sessions.map((x) => x.cost_usd)).toFixed(2) !== total[2]) throw new Error('results.json: the total cost differs from results.md');

/** The one session whose usage Claude Code undercounted: one turn reported for minutes of work. */
const short = sessions.filter((x) => x.turns === 1 && (x.agent_ms ?? 0) > 60_000);
if (short.length !== 1) throw new Error(`results.json: expected one undercounted session, found ${short.length}`);
export const undercounted = { ...short[0], seconds: Math.round((short[0].agent_ms ?? 0) / 1000) };

/** versions.txt: Claude Code, memprove, Python, git, OS, then the run's settings. */
const versions = file('results/versions.txt').trim().split('\n');
export const claudeCode = versions[0].replace(/ \(Claude Code\)$/, '');
const mp = versions[1].match(/^memprove (\S+) \((\w+)\)$/);
if (!mp) throw new Error('versions.txt: no "memprove <version> (<commit>)" line');
export const memproveVersion = mp[1];
export const memproveCommit = mp[2];
export const runSettings = versions[versions.length - 1];
export const platform = `${versions[4]} (${versions[5]})`;
const caps = runSettings.match(/trial cap (\$[\d.]+); run cap (\$[\d.]+)/);
if (!caps) throw new Error('versions.txt: no trial cap or run cap');
export const trialCap = caps[1];
export const runCap = caps[2];

/** The kit README's task table: task, kind, what the notes say (at c2), what the code says at main. */
export const tasks = file('kit/README.md')
  .split('\n')
  .map((l) => l.match(/^ {2}\| ([a-z-]+) \| ([a-z-]+) \| (.+?) \| (.+?) \|$/))
  .filter((m): m is RegExpMatchArray => m !== null && m[1] !== 'task')
  .map((m) => ({ task: m[1], kind: m[2], notes: m[3], code: m[4] }));
if (tasks.length !== 8) throw new Error(`kit/README.md: expected 8 tasks in its table, found ${tasks.length}`);

/** CLAUDE.md as the fixture writes it at commit c2. */
const claudeMd = file('kit/build_fixture.py').match(/^CLAUDE_MD = """([\s\S]*?)"""$/m);
if (!claudeMd) throw new Error('kit/build_fixture.py: no CLAUDE_MD');
export const claudeMdLines = claudeMd[1].replace(/\n+$/, '').split('\n');

/** The claims of the Context Pack memprove printed at main, the one the memprove arm was given. */
const pack = file('results/pack-at-main.txt').split('\n');
export const packClaims = pack
  .map((l) => l.match(/^#(\d+) (fact stale|decision|next action): 「(.+?)」/))
  .filter((m): m is RegExpMatchArray => m !== null)
  .map((m) => ({ n: Number(m[1]), kind: m[2], text: m[3] }));
export const packRerun = pack.find((l) => l.startsWith('Rerun: '))?.replace(/[「」]/g, '`') ?? '';
if (packClaims.filter((c) => c.kind === 'fact stale').length !== 3) throw new Error('pack-at-main.txt: expected 3 stale facts');

/** The fixture's commits, oldest first, with their short IDs. */
export const commits = file('results/fixture-log.txt')
  .trim()
  .split('\n')
  .map((l) => l.match(/^([0-9a-f]{40}) (\S+) (.+)$/))
  .filter((m): m is RegExpMatchArray => m !== null)
  .map((m) => ({ id: m[1].slice(0, 7), date: m[2].slice(0, 10), subject: m[3] }))
  .reverse();
