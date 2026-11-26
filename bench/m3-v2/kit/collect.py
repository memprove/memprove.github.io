#!/usr/bin/env python3
"""Summarise the M3 v2 benchmark's runs.

Usage:
  collect.py <runs.tsv> <out dir>      results.json and results.md
  collect.py --spent <runs.tsv>        money spent so far, in USD
  collect.py --count <run dir>         "<passed> <trials>" of one eval run
  collect.py --round-ok <runs.tsv> <round> <model>
                                       exit 0 if the model passed any trial in that round

runs.tsv has one line per `memprove eval run`: round, model, arm, run directory (tab-separated).

The reading below was fixed before any real run (2026-11-24) and is applied as it stands:
  - main question, per model: memprove against claude-md on the four memory-outdated tasks.
    Each (round, task) is a pair; only pairs where one arm passed and the other failed count.
    One-sided exact sign test on those pairs: "memprove better" if p < 0.05, "claude-md better"
    if p < 0.05 the other way, otherwise "no difference shown".
  - memory value, per model: claude-md and memprove each against none on the two
    memory-needed tasks, the same test.
  - controls: pass counts per arm; noted when an arm passes 2 or more control trials fewer
    than claude-md.
  - cost: mean USD and mean turns per trial, per model and arm.
"""

import json
import sys
from collections import defaultdict
from math import comb
from pathlib import Path

TASK_ORDER = ["port", "staging-url", "ratelimit-docs", "free-shipping-faq", "refund-rounding",
              "partners-doc", "discount", "zone-validation"]
KIND = {"port": "needs-memory", "staging-url": "needs-memory",
        "ratelimit-docs": "memory-outdated", "free-shipping-faq": "memory-outdated",
        "refund-rounding": "memory-outdated", "partners-doc": "memory-outdated",
        "discount": "control", "zone-validation": "control"}
ARM_ORDER = ["none", "claude-md", "memprove"]


def read_runs(runs_tsv):
    runs = []
    for line in Path(runs_tsv).read_text(encoding="utf-8").splitlines():
        if line.strip():
            rnd, model, arm, run_dir = line.split("\t")
            runs.append((int(rnd), model, arm, Path(run_dir)))
    return runs


def run_json(run_dir):
    return json.loads((Path(run_dir) / "run.json").read_text(encoding="utf-8"))


def cost_of(result):
    usage = (result.get("agent") or {}).get("usage") or {}
    return (usage.get("cost_microusd") or 0) / 1e6


def final_message(trial_dir):
    try:
        out = json.loads((trial_dir / "agent.out").read_text(encoding="utf-8"))
        return str(out.get("result", ""))[-1500:]
    except (OSError, ValueError):
        return ""


def sign_test(wins, losses):
    """One-sided exact sign test: P(X >= wins) for X ~ Binomial(wins + losses, 1/2)."""
    n = wins + losses
    if n == 0:
        return 1.0
    return sum(comb(n, k) for k in range(wins, n + 1)) / 2 ** n


def compare(outcomes, model, a, b, kind):
    """Pairs (round, task) of tasks of `kind` where arm a and arm b both ran."""
    wins = losses = pairs = 0
    for (m, arm, rnd, task), passed in outcomes.items():
        if m != model or arm != a or KIND.get(task) != kind:
            continue
        other = outcomes.get((m, b, rnd, task))
        if other is None:
            continue
        pairs += 1
        if passed and not other:
            wins += 1
        elif other and not passed:
            losses += 1
    p_better, p_worse = sign_test(wins, losses), sign_test(losses, wins)
    if wins + losses and p_better < 0.05:
        verdict = f"{a} better"
    elif wins + losses and p_worse < 0.05:
        verdict = f"{b} better"
    else:
        verdict = "no difference shown"
    return {"a": a, "b": b, "kind": kind, "pairs": pairs, "a_only": wins, "b_only": losses,
            "p_a_better": round(p_better, 4), "p_b_better": round(p_worse, 4), "verdict": verdict}


def main(argv):
    if len(argv) == 3 and argv[1] == "--spent":
        total = 0.0
        if Path(argv[2]).exists():
            for _, _, _, run_dir in read_runs(argv[2]):
                try:
                    total += sum(cost_of(r) for r in run_json(run_dir)["results"])
                except (OSError, ValueError, KeyError):
                    pass
        print(f"{total:.2f}")
        return 0
    if len(argv) == 3 and argv[1] == "--count":
        results = run_json(argv[2])["results"]
        print(sum(r["outcome"] == "passed" for r in results), len(results))
        return 0
    if len(argv) == 5 and argv[1] == "--round-ok":
        rnd, model = int(argv[3]), argv[4]
        for r, m, _, run_dir in read_runs(argv[2]):
            if r == rnd and m == model and any(x["outcome"] == "passed" for x in run_json(run_dir)["results"]):
                return 0
        return 1
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    out = Path(argv[2])
    out.mkdir(parents=True, exist_ok=True)
    trials, runs, outcomes = [], [], {}
    for rnd, model, arm, run_dir in read_runs(argv[1]):
        run = run_json(run_dir)
        runs.append({"round": rnd, "model": model, "arm": arm, "run_id": run["run_id"],
                     "agent_model": run["agent"].get("model"), "agent_version": run["agent"].get("version"),
                     "extra_args": run["agent"].get("extra_args"), "memory_given": run.get("memory_given"),
                     "summary": run["summary"], "started_at": run["started_at"], "finished_at": run["finished_at"]})
        for r in run["results"]:
            usage = (r.get("agent") or {}).get("usage") or {}
            trial_dir = Path(run_dir) / r["logs"]
            try:
                diff = (trial_dir / "agent.diff").read_text(encoding="utf-8", errors="replace")[:6000]
            except OSError:
                diff = ""
            passed = r["outcome"] == "passed"
            outcomes[(model, arm, rnd, r["task"])] = passed
            trials.append({
                "round": rnd, "model": model, "arm": arm, "run_id": run["run_id"], "task": r["task"],
                "kind": KIND.get(r["task"]), "outcome": r["outcome"], "reason": r.get("reason"),
                "cost_usd": cost_of(r), "turns": usage.get("turns"),
                "input_tokens": usage.get("input_tokens"), "output_tokens": usage.get("output_tokens"),
                "cache_read_tokens": usage.get("cache_read_tokens"),
                "cache_write_tokens": usage.get("cache_write_tokens"),
                "agent_ms": (r.get("agent") or {}).get("duration_ms"), "agent_end": (r.get("agent") or {}).get("end"),
                "diff_files": r["diff"]["files"], "diff_insertions": r["diff"]["insertions"],
                "diff_deletions": r["diff"]["deletions"], "diff": diff, "final_message": final_message(trial_dir),
            })

    models = []
    for t in trials:
        if t["model"] not in models:
            models.append(t["model"])
    table = defaultdict(lambda: {"trials": 0, "passed": 0, "cost_usd": 0.0, "turns": 0})
    for t in trials:
        for key in ((t["model"], t["arm"], t["task"]), (t["model"], t["arm"], t["kind"]), (t["model"], t["arm"], "*")):
            cell = table[key]
            cell["trials"] += 1
            cell["passed"] += t["outcome"] == "passed"
            cell["cost_usd"] += t["cost_usd"]
            cell["turns"] += t["turns"] or 0

    readings, lines = [], ["# M3 v2 results", ""]
    for model in models:
        arms = [a for a in ARM_ORDER if any(t["model"] == model and t["arm"] == a for t in trials)]
        tasks = [k for k in TASK_ORDER if any(t["model"] == model and t["task"] == k for t in trials)]
        lines += [f"## {model}", "", "| task | kind | " + " | ".join(arms) + " |", "|---|---|" + "---|" * len(arms)]
        for k in tasks:
            cells = [f"{table[(model, a, k)]['passed']}/{table[(model, a, k)]['trials']}" for a in arms]
            lines.append(f"| {k} | {KIND[k]} | " + " | ".join(cells) + " |")
        for kind in ("needs-memory", "memory-outdated", "control"):
            cells = [f"{table[(model, a, kind)]['passed']}/{table[(model, a, kind)]['trials']}" for a in arms]
            lines.append(f"| **all {kind}** | | " + " | ".join(cells) + " |")
        n = {a: table[(model, a, '*')]["trials"] or 1 for a in arms}
        lines.append("| mean cost per trial (USD) | | " + " | ".join(
            f"{table[(model, a, '*')]['cost_usd'] / n[a]:.3f}" for a in arms) + " |")
        lines.append("| mean turns per trial | | " + " | ".join(
            f"{table[(model, a, '*')]['turns'] / n[a]:.1f}" for a in arms) + " |")
        lines.append("")
        reading = {"model": model, "comparisons": [
            compare(outcomes, model, "memprove", "claude-md", "memory-outdated"),
            compare(outcomes, model, "claude-md", "none", "needs-memory"),
            compare(outcomes, model, "memprove", "none", "needs-memory"),
        ], "control_notes": []}
        base = table[(model, "claude-md", "control")]["passed"]
        for a in arms:
            if a != "claude-md" and base - table[(model, a, "control")]["passed"] >= 2:
                reading["control_notes"].append(f"{a} passed {base - table[(model, a, 'control')]['passed']} "
                                                f"control trials fewer than claude-md")
        readings.append(reading)
        lines.append("| comparison | tasks | pairs | only first passed | only second passed | verdict |")
        lines.append("|---|---|---|---|---|---|")
        for c in reading["comparisons"]:
            lines.append(f"| {c['a']} vs {c['b']} | {c['kind']} | {c['pairs']} | {c['a_only']} | {c['b_only']} | "
                         f"{c['verdict']} (p {c['p_a_better']} / {c['p_b_better']}) |")
        for note in reading["control_notes"]:
            lines.append(f"\nControl note: {note}.")
        lines.append("")
    total = sum(t["cost_usd"] for t in trials)
    lines.append(f"Trials: {len(trials)}; spent: {total:.2f} USD (Claude Code's own count, at API prices).")
    (out / "results.json").write_text(json.dumps({"runs": runs, "readings": readings, "trials": trials},
                                                 indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (out / "results.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
