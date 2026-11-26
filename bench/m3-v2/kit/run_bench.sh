#!/bin/bash
# The memprove memory benchmark M3 v2, end to end, on macOS (Apple silicon) or Linux.
#
#   run_bench.sh setup        memprove 0.3.0 into a throwaway prefix, the parcelpost v2 fixture with
#                             memprove's notes recorded at c2, task files for none/claude-md/memprove
#   run_bench.sh rehearse     scripted agents instead of a model ($0): oracle must pass 8 of 8 in every
#                             arm, stale 4 of 8, nomemory 6 of 8; anything else stops with exit 4
#   run_bench.sh probe        one cheap `claude -p` per model: does a user-level CLAUDE.md leak in?
#   run_bench.sh run <ROUNDS> each round runs every model x arm once over the eight tasks; finished
#                             (round, model, arm) runs are skipped, so the same command continues
#   run_bench.sh start <ROUNDS>
#                             `run <ROUNDS>` detached from this shell (its own session, kept awake with
#                             caffeinate on macOS); at most $BENCH_STARTS (2) starts in all
#   run_bench.sh wait [SECS]  wait up to SECS (default 540) for a started run; prints its status and,
#                             when it has ended, its exit code
#   run_bench.sh status       runs done and money spent so far
#   run_bench.sh collect      results.json, results.md and the raw runs into $BENCH_OUT/<time>/
#   run_bench.sh stop         stop the throwaway daemon
#
# Limits: Claude Code stops a trial at $BENCH_TRIAL_USD (0.50); `run` starts an eval run (8 trials)
# only while the money spent plus 8 x the trial limit stays within $BENCH_CAP_USD (30), so finished
# runs never pass the cap; a run cut off by a stop or a crash is not counted and is run again at
# the next start (at most $BENCH_STARTS, 2). `run` stops with exit 4 when an agent cannot be
# started (eval exit 3) or a model passes none of its trials in a round, and with exit 5 at the cap.
#
# Everything lives under $BENCH_DIR (default /private/tmp/m3v2 on macOS, /tmp/m3v2 elsewhere). The
# installation in ~/.memprove (or any other) is not read or changed: every command runs under `env -i`
# with MEMPROVE_CONFIG_DIR naming the throwaway one, so no variable of the calling session (memprove's,
# Claude Code's) reaches memprove or the agent. The agent is `claude -p` with --setting-sources
# project,local and --strict-mcp-config: no user-level settings, CLAUDE.md, hooks or MCP servers.
set -euo pipefail

KIT=$(cd "$(dirname "$0")" && pwd)
case "$(uname -s)" in Darwin) DEFAULT_DIR=/private/tmp/m3v2; TARGET=aarch64-apple-darwin ;;
                      *) DEFAULT_DIR=/tmp/m3v2; TARGET=x86_64-unknown-linux-gnu ;; esac
W=${BENCH_DIR:-$DEFAULT_DIR}
MODELS=${BENCH_MODELS:-claude-opus-5-5 claude-haiku-5-5}
ARMS=${BENCH_ARMS:-none claude-md memprove}
JOBS=${BENCH_JOBS:-2}
TRIAL_USD=${BENCH_TRIAL_USD:-0.50}
CAP_USD=${BENCH_CAP_USD:-30}
MAX_STARTS=${BENCH_STARTS:-2}
OUT=${BENCH_OUT:-$W/out}
VERSION=v0.3.0
MP=$W/mp
FX=$W/parcelpost

CLAUDE_BIN=$(command -v claude || true)
PY_BIN=$(command -v python3)
NODE_BIN=$(command -v node || echo /usr/bin/true)
CLEAN_PATH="$MP/bin:$(dirname "${CLAUDE_BIN:-/usr/bin/true}"):$(dirname "$NODE_BIN"):$(dirname "$PY_BIN"):/usr/bin:/bin:/usr/sbin:/sbin"
ME=${USER:-$(id -un)}

# Run a command with nothing of this session's environment but what the agent needs to log in.
clean() {
  local pass=()
  for v in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN; do
    if [ -n "${!v:-}" ]; then pass+=("$v=${!v}"); fi
  done
  env -i HOME="$HOME" USER="$ME" LOGNAME="$ME" PATH="$CLEAN_PATH" LANG=en_US.UTF-8 \
    TMPDIR="${TMPDIR:-/tmp}" SHELL=/bin/sh TERM=dumb PYTHONDONTWRITEBYTECODE=1 \
    MEMPROVE_CONFIG_DIR="$MP/config" ${pass[@]+"${pass[@]}"} "$@"
}

AGENT_ARGS=(--agent-arg --setting-sources --agent-arg project,local --agent-arg --strict-mcp-config
            --agent-arg --max-budget-usd --agent-arg "$TRIAL_USD")
CLAUDE_ISOLATION=(--setting-sources project,local --strict-mcp-config --no-session-persistence)

sha256() { if command -v shasum >/dev/null; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }
spent() { if [ -f "$W/runs.tsv" ]; then clean python3 "$KIT/collect.py" --spent "$W/runs.tsv"; else echo 0.00; fi; }

setup() {
  if [ -e "$W" ]; then echo "$W exists; remove it or set BENCH_DIR" >&2; exit 2; fi
  mkdir -p "$W/dl"
  local a="memprove-${VERSION#v}-$TARGET" url="https://github.com/memprove/memprove/releases/download/$VERSION"
  if [ -n "${BENCH_MEMPROVE_DIR:-}" ]; then
    cp -R "$BENCH_MEMPROVE_DIR" "$W/dl/$a"
  else
    (cd "$W/dl" && curl -fsSLO "$url/$a.tar.gz" && curl -fsSLO "$url/$a.tar.gz.sha256" \
       && sha256 -c "$a.tar.gz.sha256" && tar -xzf "$a.tar.gz")
  fi
  clean "$W/dl/$a/scripts/install.sh" --prefix "$MP" --from-binaries "$W/dl/$a/bin" --no-write-profile \
    > "$W/install.log" 2>&1 || { tail -20 "$W/install.log"; exit 1; }
  clean memprove --version
  clean python3 "$KIT/build_fixture.py" "$FX" --after-c2 sh "$KIT/record_memory.sh" > "$W/fixture.log" 2>&1 \
    || { tail -30 "$W/fixture.log"; exit 1; }
  grep -E '^(c[0-9]|no-claude-md) ' "$W/fixture.log"
  (cd "$FX" && clean python3 "$KIT/make_evals.py" . none claude-md memprove)
  (cd "$FX" && clean memprove resume --pack > "$W/pack-at-main.txt")
  echo "Pack at main: $W/pack-at-main.txt ($(wc -c < "$W/pack-at-main.txt") bytes)"
}

# One scripted pass over one arm; prints "<passed> <trials>".
scripted() {
  local arm=$1 mode=$2 mem log
  if [ "$arm" = memprove ]; then mem="--memory pack"; else mem="--no-memory"; fi
  log="$W/rehearse-$arm-$mode.log"
  set +e
  (cd "$FX" && clean memprove eval run "evals/$arm" --agent command --jobs "$JOBS" $mem \
     --out-root "$W/rehearse-runs" -- python3 "$KIT/agents/scripted.py" "$mode" {workdir} {prompt_file}) > "$log" 2>&1
  set -e
  clean python3 "$KIT/collect.py" --count "$(sed -n 's/^run directory: //p' "$log" | tail -1)"
}

rehearse() {
  local fail=0 arm got
  git -C "$FX" checkout -q main
  for arm in $ARMS; do
    got=$(scripted "$arm" oracle); echo "$arm oracle: $got (want 8 8)"; [ "$got" = "8 8" ] || fail=1
  done
  got=$(scripted claude-md stale); echo "claude-md stale: $got (want 4 8)"; [ "$got" = "4 8" ] || fail=1
  got=$(scripted none nomemory); echo "none nomemory: $got (want 6 8)"; [ "$got" = "6 8" ] || fail=1
  if [ "$fail" != 0 ]; then echo "rehearsal FAILED; logs: $W/rehearse-*.log" >&2; exit 4; fi
  echo "rehearsal PASS"
}

probe() {
  local d="$W/probe" model
  rm -rf "$d"; mkdir -p "$d"
  printf '# probe\n\nThe canary word for this directory is heliotrope.\n' > "$d/CLAUDE.md"
  (cd "$d" && git init -q)
  for model in $MODELS; do
    (cd "$d" && clean claude -p --output-format json --model "$model" --max-budget-usd "$TRIAL_USD" \
       "${CLAUDE_ISOLATION[@]}" -- \
      "Quote the first line of every CLAUDE.md or other instruction or memory file (user-level or project-level) that was loaded into your context, one per line, each with where it came from. If none was loaded, answer NONE. Do not use any tools.") \
      > "$W/probe-$model.json"
    echo "== $model"
    clean python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("result")); print("cost USD", d.get("total_cost_usd"))' "$W/probe-$model.json"
  done
}

run_rounds() {
  local rounds=${1:?run needs a number of rounds}
  local round model arm mem log dir status total
  [ -n "$CLAUDE_BIN" ] || { echo "claude is not on PATH" >&2; exit 2; }
  git -C "$FX" checkout -q main
  touch "$W/runs.tsv"
  for round in $(seq 1 "$rounds"); do
    for model in $MODELS; do
      for arm in $ARMS; do
        if awk -F'\t' -v r="$round" -v m="$model" -v a="$arm" '$1==r && $2==m && $3==a {f=1} END {exit !f}' "$W/runs.tsv"; then
          continue
        fi
        total=$(spent)
        if clean python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) + 8 * float(sys.argv[2]) > float(sys.argv[3]) else 1)' \
             "$total" "$TRIAL_USD" "$CAP_USD"; then
          echo "cap: \$$total spent; one more run could pass \$$CAP_USD, so none is started" >&2; exit 5
        fi
        if [ "$arm" = memprove ]; then mem="--memory pack"; else mem="--no-memory"; fi
        log="$W/run-$(date -u +%Y%m%dT%H%M%SZ)-r$round-$model-$arm.log"
        set +e
        (cd "$FX" && clean memprove eval run "evals/$arm" --agent claude-code --model "$model" --trials 1 \
           --jobs "$JOBS" $mem "${AGENT_ARGS[@]}") > "$log" 2>&1
        status=$?
        set -e
        grep -E 'memprove eval: |^run ' "$log" || tail -5 "$log"
        dir=$(sed -n 's/^run directory: //p' "$log" | tail -1)
        if [ "$status" = 3 ] || [ -z "$dir" ]; then
          echo "round $round $model $arm: the agent could not be run (exit $status); see $log" >&2; exit 4
        fi
        printf '%s\t%s\t%s\t%s\n' "$round" "$model" "$arm" "$dir" >> "$W/runs.tsv"
      done
      if ! clean python3 "$KIT/collect.py" --round-ok "$W/runs.tsv" "$round" "$model"; then
        echo "round $round: $model passed none of its trials; stopping (wrong model name or login?)" >&2; exit 4
      fi
    done
    echo "round $round done; spent \$$(spent) of \$$CAP_USD"
  done
}

start() {
  local rounds=${1:?start needs a number of rounds} n=0
  [ -d "$FX" ] || { echo "no fixture; run setup first" >&2; exit 2; }
  if [ -f "$W/run.pid" ] && kill -0 "$(cat "$W/run.pid")" 2>/dev/null; then
    echo "already running (pid $(cat "$W/run.pid"))"; return 0
  fi
  [ -f "$W/starts" ] && n=$(cat "$W/starts")
  if [ "$n" -ge "$MAX_STARTS" ]; then echo "refused: already started $n times (limit $MAX_STARTS)" >&2; exit 6; fi
  echo $((n + 1)) > "$W/starts"
  rm -f "$W/run.exit"
  local keep=""; command -v caffeinate >/dev/null && keep="caffeinate -i"
  nohup python3 -c 'import os, sys; os.getpgrp() == os.getpid() or os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
    $keep /bin/sh -c '/bin/bash "$0" run "$1"; echo $? > "$2"' "$KIT/run_bench.sh" "$rounds" "$W/run.exit" \
    >> "$W/run.log" 2>&1 < /dev/null &
  echo $! > "$W/run.pid"
  echo "started (pid $!, start $((n + 1)) of $MAX_STARTS); log $W/run.log"
}

wait_run() {
  local secs=${1:-540} waited=0
  while [ -f "$W/run.pid" ] && kill -0 "$(cat "$W/run.pid")" 2>/dev/null && [ "$waited" -lt "$secs" ]; do
    sleep 15; waited=$((waited + 15))
  done
  tail -5 "$W/run.log" 2>/dev/null || true
  status
  if [ -f "$W/run.exit" ]; then echo "ended with exit $(cat "$W/run.exit")"; else echo "still running"; fi
}

status() {
  if [ -f "$W/runs.tsv" ]; then
    echo "runs done: $(wc -l < "$W/runs.tsv") (one run = one model x arm x 8 tasks)"
    cut -f1,2,3 "$W/runs.tsv" | sed 's/^/  /'
  else
    echo "runs done: 0"
  fi
  echo "spent: \$$(spent) of \$$CAP_USD"
}

collect() {
  local dest
  dest="$OUT/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$dest"
  clean python3 "$KIT/collect.py" "$W/runs.tsv" "$dest"
  cp "$W/runs.tsv" "$dest/"
  cp "$W/pack-at-main.txt" "$dest/" 2>/dev/null || true
  cp "$W"/probe-*.json "$dest/" 2>/dev/null || true
  git -C "$FX" log --format='%H %ad %s' --date=iso-strict --all > "$dest/fixture-log.txt"
  if [ -d "$FX/.git/memprove-eval" ]; then tar -czf "$dest/runs.tar.gz" -C "$FX/.git" memprove-eval
  else tar -czf "$dest/runs.tar.gz" -T /dev/null; fi
  tar -czf "$dest/evals.tar.gz" -C "$FX" evals
  { clean claude --version; clean memprove --version; clean python3 --version; git --version
    uname -sm; command -v sw_vers >/dev/null && sw_vers -productVersion
    echo "models $MODELS; arms $ARMS; jobs $JOBS; trial cap \$$TRIAL_USD; run cap \$$CAP_USD"; } \
    > "$dest/versions.txt" 2>&1
  (cd "$dest" && sha256 results.json results.md runs.tar.gz evals.tar.gz)
  echo "collected into $dest"
}

stop() {
  if [ -f "$W/run.pid" ] && kill -0 "$(cat "$W/run.pid")" 2>/dev/null; then
    kill -TERM -- "-$(cat "$W/run.pid")" 2>/dev/null || kill -TERM "$(cat "$W/run.pid")"
    echo "run stopped (pid $(cat "$W/run.pid")); agents already started end at their own trial limit"
  fi
  pkill -f "$MP/bin/memproved" 2>/dev/null && echo "daemon stopped" || echo "no daemon running"
}

case "${1:-}" in
  setup) setup ;;
  rehearse) rehearse ;;
  probe) probe ;;
  run) shift; run_rounds "$@" ;;
  start) shift; start "$@" ;;
  wait) shift; wait_run "$@" ;;
  status) status ;;
  collect) collect ;;
  stop) stop ;;
  *) sed -n '2,31p' "$0"; exit 2 ;;
esac
