# Benchmarks

The kits and results behind [memprove.dev/benchmark/](https://memprove.dev/benchmark/). The page reads every result from
here at build time (`src/lib/bench.ts`); change a file and the page changes with it, or the build fails.

## m3-v2: memprove against a plain CLAUDE.md (run 2026-11-26)

- `kit/` is the kit exactly as it ran: `README.md` describes the question, the tasks, the reading rules fixed before the
  run, and how to run it. Its files hash, as `find . -type f | LC_ALL=C sort | xargs sha256sum | sha256sum`, to
  `9859c16418c846c08eaf33d19179753bf8ddeb1b5f711acee943c7476264ea38`. Only the executable bits were set here.
- `results/` holds four of the files `./run_bench.sh collect` wrote on the machine that ran it (macOS on Apple silicon),
  unchanged:

  | file | what it is | sha256 |
  | --- | --- | --- |
  | `results.md` | pass counts, cost and turns per model, arm and task; the pre-registered comparisons | `56c29ad0900f22fa6fd0e49d0594c4d03b07ba3330a8bec104be02f6357f66ad` |
  | `versions.txt` | Claude Code, memprove, Python, git, the OS, the run's settings | `0acf82c4047290679ebe4b058700b58bb56f334a18a71bf8a685b1a4b3bcff56` |
  | `pack-at-main.txt` | the Context Pack memprove printed at main: what the memprove arm was given | `16886ae6405e4e6f697ca4e2bff32b347e518b6540a3e868eb65251f6c753c8d` |
  | `fixture-log.txt` | the fixture's commits, as `git log --all` printed them | `edd1363ce56b2b4f865bd3197d8fa3d35af08ee4453c2adedf8237e2f20a1904` |
  | `results.json` | every session: round, model, arm, task, outcome, cost, turns, tokens, duration, its diff (first 6,000 characters) and its final message; the readings | `85d1dc77f5c7086451c2376e99fc4e275b4fc1241e73b69c6637a3d5b796e9b5` |
  | `runs.tsv` | the 30 `memprove eval run` calls: round, model, arm and run directory, the input of `collect.py` | `b90f3cfcd2af08bf437c60dbf0f7e9ad68d4bc4b5ff32369b58ce79183e8d78a` |

  `src/lib/bench.ts` recounts every pass count, mean cost and mean turns of `results.md` from `results.json` and fails the
  build if they differ. The collect step also wrote `runs.tar.gz` (the raw run directories), `evals.tar.gz` (the task
  files, which `kit/make_evals.py` writes again) and the two probe answers; they are kept with the run and not published.

One session's cost is undercounted (round 3, claude-haiku-5-5, memprove arm, refund-rounding): the agent ended its work in
a background task, and Claude Code's final JSON counts only its last turn. Its outcome is not affected.
