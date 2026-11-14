#!/usr/bin/env bash
# Records the memprove output that memprove.dev shows, from a real session in
# the example repository tinyini (demo/tinyini). Every file it writes under
# src/data/demo/ is a command and what it printed, standard error included.
#
# Needs: memprove 0.1.0 installed with the default prefix (~/.memprove, the
# daemon running), git, and python3 with pytest. On a fresh installation the
# ledger sequence numbers are the ones the site shows; on one that already
# holds Projects they are higher.
#
#   demo/record.sh                 # builds ~/tinyini and records into src/data/demo/
#   DEMO_DIR=/tmp/t demo/record.sh # another place for the repository
#
# The commits use a fixed author and fixed dates, so their hashes are the same
# on every machine. The only change made to the output is that the home
# directory is written as ~ (so it does not show the recording machine's
# account name).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
site=$(cd "$here/.." && pwd)
src="$here/tinyini"
out="$site/src/data/demo"
repo=${DEMO_DIR:-$HOME/tinyini}
python=${PYTHON:-python3}

command -v memprove >/dev/null || { echo "memprove is not on PATH" >&2; exit 2; }
"$python" -m pytest --version >/dev/null 2>&1 || { echo "$python has no pytest" >&2; exit 2; }
if [ -e "$repo" ]; then
  echo "$repo exists; remove it or set DEMO_DIR" >&2
  exit 2
fi

export GIT_AUTHOR_NAME="tinyini" GIT_AUTHOR_EMAIL="tinyini@memprove.dev"
export GIT_COMMITTER_NAME="tinyini" GIT_COMMITTER_EMAIL="tinyini@memprove.dev"

rm -rf "$out"
mkdir -p "$out"

# rec <file> <command...>: runs the command in the repository and appends
# "$ <command>" and everything it printed to src/data/demo/<file>.txt.
rec() {
  local file="$out/$1.txt"
  shift
  local shown="" arg
  for arg in "$@"; do
    [ "$arg" = "$python" ] && arg=python3
    case "$arg" in
      *[[:space:]\;\(\)\[\]\'\"\&\|\<\>\$\*\?]*) arg="\"$arg\"" ;;
    esac
    shown="$shown${shown:+ }$arg"
  done
  printf '$ %s\n' "$shown" >>"$file"
  local status=0
  (cd "$repo" && "$@") >>"$file" 2>&1 || status=$?
  if [ "$status" -ne 0 ]; then
    printf '[exit %s]\n' "$status" >>"$file"
  fi
  return 0
}

# hook <file>: what Claude Code's SessionStart hook prints for a new session.
hook() {
  local file="$out/$1.txt"
  printf '$ memprove hook session-start   # run by Claude Code at the start of a session\n' >>"$file"
  printf '{"session_id":"tinyini-session-2","cwd":"%s","source":"startup","hook_event_name":"SessionStart"}' "$repo" \
    | (cd "$repo" && env -u CLAUDE_ENV_FILE memprove hook session-start --config-dir "$HOME/.memprove/config") >>"$file" 2>&1
}

commit() { # commit <iso date> <message>
  (cd "$repo" && git add -A && GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git commit -q -m "$2")
}

mkdir -p "$repo"
cp -R "$src/step1/." "$repo/"
(cd "$repo" && git init -q -b main)
commit "2026-11-14T09:00:00Z" "tinyini: parse sections and keys"

# The operator enables the repository once.
rec 01-init memprove init

# Session 1: the agent does the Task and records what holds.
rec 02-begin memprove begin --new-task "parser: handle empty input"
cp -R "$src/step2/." "$repo/"
commit "2026-11-14T10:00:00Z" "parser: handle empty input"
rec 03-run memprove run --test-format pytest -- "$python" -m pytest -q
rec 04-checkpoint memprove checkpoint create \
  --fact "parse() returns an empty document for empty or whitespace-only input" --evidence r1 \
  --fact "input of only comments is an empty document" --evidence r1 \
  --fact "keys before the first section header go into the default section" --evidence r1 \
  --fact "a duplicate key keeps the last value" --evidence r1 \
  --open "an unterminated section header such as [core is untested" \
  --next "write the unterminated-header test and run pytest"
rec 05-pack-verified memprove resume --pack
rec 05-text-verified memprove resume --text
rec 06-end memprove end --reason "empty input handled"

# The code moves on without memprove: someone commits another change.
cp -R "$src/step3/." "$repo/"
commit "2026-11-14T11:00:00Z" "parser: strip inline comments from values"

# Session 2: a new Claude Code session starts; the hook gives it the Pack.
hook 07-hook-stale
rec 07-text-stale memprove resume --text
rec 08-begin memprove begin
rec 09-run memprove run --test-format pytest -- "$python" -m pytest -q
rec 10-reaffirm memprove checkpoint create --reaffirm-all \
  --next "write the unterminated-header test and run pytest"
rec 11-pack-reverified memprove resume --pack
rec 11-text-reverified memprove resume --text
rec 12-ledger memprove ledger verify
rec 13-end memprove end --reason "facts reaffirmed after the inline-comment change"

# The home directory, written as ~.
for f in "$out"/*.txt; do
  sed -i.bak "s#$HOME#~#g" "$f" && rm -f "$f.bak"
done

{
  echo "memprove $(memprove --version | awk '{print $2, $3}')"
  echo "python $("$python" -c 'import sys; print(sys.version.split()[0])'), $("$python" -m pytest --version 2>&1 | head -1)"
  echo "recorded $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(uname -sm)"
  (cd "$repo" && git log --format='commit %H %s')
} >"$out/00-about.txt"

echo "recorded into $out:" >&2
ls "$out" >&2
