#!/bin/sh
# Record in memprove, at commit c2 of the parcelpost fixture, the same six
# notes that CLAUDE.md holds at c2 (M3 v2). build_fixture.py runs it with --after-c2,
# in the fixture, with `memprove` on PATH and MEMPROVE_CONFIG_DIR naming the
# installation to use (a throwaway one: see run_bench.sh).
#
# The test command becomes the run memprove binds the facts to; the three
# testable notes become facts citing that run; the port and staging notes,
# which no test can check, become Decisions.
set -eu
export PYTHONDONTWRITEBYTECODE=1

printf 'evals/\n' >> .git/info/exclude
memprove init --client claude-code >/dev/null
memprove begin --new-task "parcelpost: rate limiting and free shipping" \
  --agent-name notes-agent --agent-role orchestrator

cases=$(python3 -m unittest discover -s tests 2>&1 | sed -n 's/^Ran \([0-9][0-9]*\) tests* in .*/\1/p')
memprove run --test --test-cases "$cases" -- python3 -m unittest discover -s tests

memprove checkpoint create \
  --fact "Money is integer cents everywhere. Customer-facing amounts are rounded half-up to whole cents with pricing.round_half_up, never with round()." --evidence r1 \
  --fact "API clients are rate limited to 100 requests per minute per API key." --evidence r1 \
  --fact "Orders of €50.00 or more ship free." --evidence r1 \
  --next "No work is planned; take the next request."
memprove decide "Ops allocated port 7431 to parcelpost in the shared host's port registry; the code still defaults to 8000 until we switch." \
  --rationale "the entry in the shared host's port registry"
memprove decide "Ops moved staging to https://staging-2.parcelpost.invalid on 2026-09-02; staging-1 is retired. docs/DEPLOY.md still names staging-1 until someone updates it." \
  --rationale "ops announcement of 2026-09-02"
memprove end --reason "rate limiting and free shipping are in"
