# Recorded output of memprove-tune

Everything the pages under `/tune/` show in a terminal block or a figure was
printed by the tool. Nothing here is written by hand.

- `scan.txt`, `scan.json`, `init.txt`, `plan.txt`: `memprove-tune scan`,
  `scan --json`, `init --verify --test "python3 -m unittest discover -s tests"`
  and `prune --dry-run --cost-per-trial 0.11 --max-cost 30`, in that order, in
  a fresh clone of `parcelpost`, the small made-up repository of run 1 in
  memprove-tune's `docs/validation.md`. They start no agent and call no model.
  Record them again with a new release when its output changes.
- `claude-md.txt`: that repository's `CLAUDE.md`, the file `scan` read.
- `ab.txt`: the report of run 1 (experiment `2707b9652d84`, 2026-11-17 and
  11-18, Claude Code 2.1.310 with `claude-opus-5-5`), as the tool printed it
  after the last round.
- `prune.txt`, `verdicts.json`: the report and the verdict file of run 4
  (`prune`, experiments `17769feefe9e` and `9e12cfd88bbc`, 2026-11-24,
  Claude Code 2.1.310 with `claude-opus-5-5`), copied unchanged from the
  run's log and its `.tune/verdicts.json`. The build stops if a unit's
  text in `scan.json` is not the text the verdict was measured on.
