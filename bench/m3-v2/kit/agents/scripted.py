#!/usr/bin/env python3
"""A scripted stand-in for a coding agent, to check the task files (M3 v2).

Usage (as a `memprove eval` command agent):
  memprove eval run evals/<arm> --agent command --no-memory -- \
      python3 agents/scripted.py <oracle|stale|nomemory> {workdir} {prompt_file}

oracle:   does each task right. Every task must pass (8 of 8).
stale:    believes the notes written at c2 (rate limit 100, free shipping from
          EUR 50, refunds round half-up) and knows the port and the staging
          host from them. The four memory-outdated tasks fail (4 of 8).
nomemory: reads only the repository: it cannot know the allocated port and
          takes the staging host from docs/DEPLOY.md. Both memory-needed tasks
          fail; the rest pass (6 of 8).
"""

import sys
from pathlib import Path


def edit(path, old, new):
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"{path}: {old!r} not found")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def append(path, text):
    with path.open("a", encoding="utf-8") as f:
        f.write(text)


def main(argv):
    mode, workdir, prompt_file = argv[1], Path(argv[2]), Path(argv[3])
    if mode not in ("oracle", "stale", "nomemory"):
        raise SystemExit(f"unknown mode {mode}")
    prompt = prompt_file.read_text(encoding="utf-8")
    stale = mode == "stale"
    if "port ops allocated" in prompt:
        if mode != "nomemory":
            edit(workdir / "parcelpost/config.py", "PORT = 8000", "PORT = 7431")
        else:
            append(workdir / "parcelpost/config.py", "# No allocated port is recorded in this repository.\n")
    elif "STAGING_URL" in prompt:
        host = "staging-1" if mode == "nomemory" else "staging-2"
        append(workdir / "parcelpost/config.py", f'STAGING_URL = "https://{host}.parcelpost.invalid"\n')
    elif "rate limits" in prompt:
        limit = 100 if stale else 60
        append(workdir / "docs/API.md", f"\n## Rate limits\n\nEach API key may make {limit} requests per minute.\n")
    elif "shipping is free" in prompt:
        euros = "50.00" if stale else "75.00"
        append(workdir / "docs/FAQ.md", f"\n## When is shipping free?\n\nOrders of €{euros} or more ship free.\n")
    elif "apply_discount" in prompt:
        append(workdir / "parcelpost/pricing.py",
               "\n\ndef apply_discount(cents, percent):\n"
               "    return round_half_up(cents * (100 - percent) / 100)\n")
    elif "partial_refund" in prompt:
        if stale:
            body = ("from .pricing import round_half_up\n\n\ndef partial_refund(order_cents, percent):\n"
                    "    return round_half_up(order_cents * percent / 100)\n")
        else:
            body = ("from .money import refund_cents\n\n\ndef partial_refund(order_cents, percent):\n"
                    "    return refund_cents(order_cents * percent / 100)\n")
        (workdir / "parcelpost/refunds.py").write_text('"""Partial refunds."""\n\n' + body, encoding="utf-8")
    elif "PARTNERS.md" in prompt:
        limit = 100 if stale else 60
        (workdir / "docs/PARTNERS.md").write_text(
            "# Getting started as a parcelpost API partner\n\n"
            "Call `GET /quote?weight=<grams>&zone=<zone>`; you get back `{\"cents\": <price>}`.\n\n"
            f"Each API key may make {limit} requests per minute.\n", encoding="utf-8")
    elif "unknown zone" in prompt:
        cli = workdir / "parcelpost/cli.py"
        edit(cli, "import argparse\n", "import argparse\nimport sys\n")
        edit(cli, "    cents = quote(args.weight, args.zone)\n",
             "    try:\n"
             "        cents = quote(args.weight, args.zone)\n"
             "    except KeyError:\n"
             "        print(f\"unknown zone: {args.zone}\", file=sys.stderr)\n"
             "        return 2\n")
    else:
        raise SystemExit("unknown task")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
