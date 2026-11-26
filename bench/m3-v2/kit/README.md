# M3 v2: does memprove beat a plain CLAUDE.md?

Kit for the second round of memprove's public memory benchmark (2026-11-24). Round 1
(2026-11-17, kit v1 beside this one) found that Claude Opus 5.5 checks the code before it
writes, so stale notes did not mislead it: memprove and a plain CLAUDE.md both passed 4 of 4,
and memprove cost a little more per trial ($0.12 against $0.10). v2 asks the question again
with tasks where checking is less obvious and with a cheaper model.

## What changed from v1

- **memprove 0.3.0** (was 0.2.1).
- **Two models**: `claude-opus-5-5` and `claude-haiku-5-5`. The hypothesis is that a cheaper
  model trusts its notes more, so memprove's "stale" marks matter more there.
- **Eight tasks** (was four), on a fixture with one more commit:

  | task | kind | what the notes say (written at c2) | what the code says at main |
  |---|---|---|---|
  | port | needs-memory | ops allocated port 7431 | 8000 (nothing in the repo names 7431) |
  | staging-url | needs-memory | staging is staging-2; docs/DEPLOY.md is outdated | docs/DEPLOY.md names staging-1 |
  | ratelimit-docs | memory-outdated | 100 requests per minute | 60 since c5 |
  | free-shipping-faq | memory-outdated | free from €50 | free from €75 since c6 |
  | refund-rounding | memory-outdated | customer amounts round half-up | refunds round down since c8 (`money.refund_cents`) |
  | partners-doc | memory-outdated | 100 requests per minute (used in passing) | 60 |
  | discount | control | half-up | half-up |
  | zone-validation | control | nothing relevant | nothing relevant |

- **Arms**: `none` (no CLAUDE.md, no memory), `claude-md` (CLAUDE.md as written at c2),
  `memprove` (no CLAUDE.md; memprove's Context Pack before the prompt). The stalebrain arm of
  v1 is left out (it tied in round 1 and needs its own `claude -p` audit).
- **Limits** in the script: Claude Code stops a trial at $0.50; no eval run starts once the
  money spent plus 8 x $0.50 would pass $30; at most 2 starts.
- **Cost and turns** are recorded per trial (Claude Code's own count, at API prices), as in v1.

The fixture's commit IDs differ from v1's (c1 has docs/DEPLOY.md, c2's notes have the staging
line). memprove marks all three facts recorded at c2 as stale at main, including the rounding
fact, which is still true for prices: its staleness is per commit, not per fact.

## Reading, fixed before any real run

Applied by `collect.py` as it stands; the results are published whatever they say.

- **Main question, per model**: memprove against claude-md on the four memory-outdated tasks.
  Each (round, task) is a pair; only pairs where exactly one arm passed count. One-sided exact
  sign test: "memprove better" if p < 0.05, "claude-md better" if p < 0.05 the other way,
  otherwise "no difference shown". With 5 rounds there are 20 pairs per model; memprove needs,
  for example, 5 wins and no loss, or 8 wins and 1 loss.
- **Memory value, per model**: claude-md and memprove each against none on the two
  memory-needed tasks (10 pairs per model), the same test.
- **Controls**: pass counts; noted when an arm passes 2 or more control trials fewer than
  claude-md.
- **Cost**: mean USD and mean turns per trial, per model and arm.

## Running it

Needs `claude` (logged in), `python3`, `git`, `curl`. Every command runs under `env -i` with a
throwaway memprove installation; `~/.memprove` and the user's Claude Code settings are not read.

    ./run_bench.sh setup          # downloads memprove 0.3.0, builds the fixture, writes the tasks
    ./run_bench.sh rehearse       # scripted agents, $0: must print "rehearsal PASS"
    ./run_bench.sh probe          # 2 cheap `claude -p`: no user-level CLAUDE.md may show up
    ./run_bench.sh start 5        # 5 rounds, detached; the Mac must stay awake, open and on power
    ./run_bench.sh wait           # up to 9 minutes; repeat until it prints "ended with exit"
    ./run_bench.sh collect        # results.md, results.json, raw runs into out/<time>/
    ./run_bench.sh stop           # stop a run and the throwaway daemon

Exit codes of a run: 0 done, 4 an agent could not be started or a model passed nothing in a
round (wrong model name or login), 5 the cap, 6 a third start refused.

Size: 5 rounds x 2 models x 3 arms x 8 tasks = 240 trials, plus 2 probe calls, so at most 242
`claude -p`. Expected about $18 (Opus about $0.12 a trial from round 1, Haiku unmeasured,
assumed at most $0.05); cap $30; worst case about $34 (the cap plus one run cut off and run
again). About 2 to 3 hours with 2 trials at a time.

## Rehearsal in the cloud (2026-11-24, scripted agents, $0)

`setup` with memprove 0.3.0 (a55358306619) on Linux, then `rehearse`: oracle 8 of 8 in every
arm, stale (believes the c2 notes) 4 of 8 failing exactly the four memory-outdated tasks,
nomemory 6 of 8 failing exactly the two memory-needed tasks; the memprove arm's run records the
Pack it was given. Skip, cap, start limit and wait were checked with recorded runs; no model was
called.
