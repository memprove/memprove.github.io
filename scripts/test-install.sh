#!/bin/bash
# Tests public/install.sh offline: a fake curl serves a fake release from a
# temporary directory, fake uname, getconf, ldd and sysctl play the platform,
# and a fake scripts/install.sh in the archive records what it was given.
# The installer runs under /bin/sh (dash on Ubuntu) with a PATH that holds
# only the tools it is allowed to need.
#
#   bash scripts/test-install.sh            # or: npm run test:install
#   INSTALLER_SH=bash bash scripts/test-install.sh   # under another shell
#
# Runs shellcheck on the installer first when shellcheck is on PATH. Needs
# Linux (GNU coreutils, util-linux script), as on the deploy workflow's runner.
set -euo pipefail
[ "$(uname -s)" = Linux ] || { echo "test-install.sh: runs on Linux only" >&2; exit 2; }

root="$(cd "$(dirname "$0")/.." && pwd -P)"
installer="$root/public/install.sh"
sh_bin="$(command -v "${INSTALLER_SH:-sh}")"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -s sh "$installer"
  echo "shellcheck -s sh public/install.sh: OK"
else
  echo "shellcheck not on PATH: skipped"
fi

# ---- fakes
fakes="$T/fakes"
mkdir -p "$fakes" "$T/log" "$T/rel" "$T/home" "$T/tmp"
cat >"$fakes/curl" <<'EOF'
#!/bin/bash
out="" fmt="" url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    -w) fmt=$2; shift 2 ;;
    --proto | --retry) shift 2 ;;
    -*) shift ;;
    *) url=$1; shift ;;
  esac
done
printf '%s\n' "$url" >>"$FAKE_LOG/curl.log"
case "$url" in
  https://github.com/memprove/memprove/releases/latest)
    [ -n "${FAKE_LATEST:-}" ] || exit 22
    [ "$fmt" = '%{redirect_url}' ] || exit 99
    printf 'https://github.com/memprove/memprove/releases/tag/%s' "$FAKE_LATEST" ;;
  https://github.com/memprove/memprove/releases/download/*)
    src="$FAKE_RELEASES/${url#https://github.com/memprove/memprove/releases/download/}"
    [ -f "$src" ] || exit 22
    cp "$src" "$out" ;;
  *) exit 6 ;;
esac
EOF
cat >"$fakes/uname" <<'EOF'
#!/bin/bash
case "${1:-}" in -m) echo "$FAKE_UNAME_M" ;; *) echo "$FAKE_UNAME_S" ;; esac
EOF
cat >"$fakes/getconf" <<'EOF'
#!/bin/bash
[ "${1:-}" = GNU_LIBC_VERSION ] && [ -n "${FAKE_GLIBC:-}" ] || exit 1
echo "glibc $FAKE_GLIBC"
EOF
cat >"$fakes/ldd" <<'EOF'
#!/bin/bash
if [ -n "${FAKE_MUSL:-}" ]; then echo "musl libc (x86_64)" >&2; exit 1; fi
echo "ldd (GNU libc) ${FAKE_GLIBC:-}"
EOF
cat >"$fakes/sysctl" <<'EOF'
#!/bin/bash
[ "${2:-}" = sysctl.proc_translated ] || exit 1
echo "${FAKE_TRANSLATED:-0}"
EOF
chmod +x "$fakes"/*

# The PATH the installer gets: the fakes plus these tools, and one hasher.
minbin() { # <dir> <hasher or "none">
  mkdir -p "$1"
  for tool in bash tar gzip mktemp rm tr cat grep cp; do ln -sf "$(command -v "$tool")" "$1/$tool"; done
  [ "$2" = none ] || ln -sf "$(command -v "$2")" "$1/$2"
  if [ "$2" = shasum ]; then ln -sf "$(command -v perl)" "$1/perl"; fi
  for f in "$fakes"/*; do ln -sf "$f" "$1/"; done
}
for h in sha256sum shasum openssl none; do minbin "$T/bin-$h" "$h"; done

# ---- a fake release 0.1.0 for both targets
for target in aarch64-apple-darwin x86_64-unknown-linux-gnu; do
  name="memprove-0.1.0-$target"
  d="$T/build/$name"
  mkdir -p "$d/scripts" "$d/bin" "$T/rel/v0.1.0"
  cat >"$d/scripts/install.sh" <<'EOF'
#!/bin/bash
{
  printf 'arg=%s\n' "$@"
  printf 'cwd=%s\n' "$(pwd -P)"
  printf 'self=%s\n' "$0"
  if [ -t 0 ]; then echo stdin=tty; else echo stdin=notty; fi
} >"$FAKE_LOG/install.log"
exit "${FAKE_INSTALL_STATUS:-0}"
EOF
  chmod +x "$d/scripts/install.sh"
  printf 'fake\n' >"$d/bin/memprove"
  printf 'fake\n' >"$d/bin/memproved"
  tar -czf "$T/rel/v0.1.0/$name.tar.gz" -C "$T/build" "$name"
  (cd "$T/rel/v0.1.0" && sha256sum "$name.tar.gz" >"$name.tar.gz.sha256")
done

# ---- the runner
passed=0
failed=0
out="$T/log/out"
base_env=(HOME="$T/home" TMPDIR="$T/tmp" FAKE_LOG="$T/log" FAKE_RELEASES="$T/rel"
  FAKE_UNAME_S=Linux FAKE_UNAME_M=x86_64 FAKE_GLIBC=2.35 FAKE_LATEST=v0.1.0)

# case <name> <expected status> [VAR=value ...] -- [installer arguments ...]
# Runs the installer from $T/cwd; HASHER (default sha256sum) picks the PATH.
case_() {
  name=$1 want=$2
  shift 2
  vars=()
  while [ "$1" != -- ]; do vars+=("$1"); shift; done
  shift
  rm -f "$T"/log/*.log "$out"
  mkdir -p "$T/cwd"
  set +e
  (cd "$T/cwd" && env -i PATH="$T/bin-${HASHER:-sha256sum}" "${base_env[@]}" "${vars[@]}" "$sh_bin" "$installer" "$@") >"$out" 2>&1
  got=$?
  set -e
  current_ok=1
  [ "$got" = "$want" ] || note "exit status $got, expected $want"
  if [ -n "$(ls -A "$T/tmp")" ]; then note "the temporary directory was left behind: $(ls -A "$T/tmp")"; rm -rf "${T:?}"/tmp/*; fi
}
note() {
  current_ok=0
  echo "    $*"
}
# Checks after a case_; each marks the case failed when it does not hold.
has_out() { grep -Eq -- "$1" "$out" || note "output lacks /$1/"; }
installed_with() { grep -Fqx -- "$1" "$T/log/install.log" 2>/dev/null || note "install.sh did not record the line '$1'"; }
not_installed() { [ ! -e "$T/log/install.log" ] || note "install.sh ran, but should not have"; }
no_download() { [ ! -e "$T/log/curl.log" ] || note "curl ran, but should not have"; }
done_() {
  if [ "$current_ok" = 1 ]; then
    passed=$((passed + 1))
    echo "PASS $name"
  else
    failed=$((failed + 1))
    echo "FAIL $name"
    sed 's/^/    | /' "$out"
  fi
}

case_ "linux x86_64, MEMPROVE_VERSION=0.1.0, --no-write-profile" 0 MEMPROVE_VERSION=0.1.0 -- --no-write-profile
has_out 'installing memprove 0\.1\.0 for x86_64-unknown-linux-gnu'
has_out 'SHA-256 matches'
installed_with "arg=--from-binaries"
installed_with "arg=--no-write-profile"
installed_with "cwd=$T/cwd"
installed_with "stdin=notty"
grep -q '^arg=/.*/memprove-0\.1\.0-x86_64-unknown-linux-gnu/bin$' "$T/log/install.log" || note "--from-binaries is not the archive's bin"
grep -q 'releases/latest' "$T/log/curl.log" && note "asked for the latest release although MEMPROVE_VERSION was set"
done_

case_ "latest release from the GitHub redirect" 0 -- --write-profile
has_out 'installing memprove 0\.1\.0'
grep -q 'releases/latest$' "$T/log/curl.log" || note "did not ask for the latest release"
installed_with "arg=--write-profile"
done_

case_ "MEMPROVE_VERSION=v0.1.0 (leading v)" 0 MEMPROVE_VERSION=v0.1.0 -- --no-write-profile
has_out 'installing memprove 0\.1\.0'
done_

case_ "MEMPROVE_VERSION=latest" 0 MEMPROVE_VERSION=latest -- --no-write-profile
has_out 'installing memprove 0\.1\.0'
done_

case_ "--prefix <DIR> and --prefix=<DIR> pass through; relative to the caller's directory" 0 MEMPROVE_VERSION=0.1.0 -- --prefix rel/one --no-write-profile
installed_with "arg=rel/one"
installed_with "cwd=$T/cwd"
done_
case_ "--prefix=<DIR>" 0 MEMPROVE_VERSION=0.1.0 -- --prefix=/opt/mp
installed_with "arg=--prefix=/opt/mp"
done_

case_ "macOS arm64" 0 FAKE_UNAME_S=Darwin FAKE_UNAME_M=arm64 FAKE_GLIBC= MEMPROVE_VERSION=0.1.0 -- --no-write-profile
has_out 'for aarch64-apple-darwin'
installed_with "arg=--no-write-profile"
done_

case_ "macOS x86_64 under Rosetta 2 gets the arm64 archive" 0 FAKE_UNAME_S=Darwin FAKE_UNAME_M=x86_64 FAKE_TRANSLATED=1 MEMPROVE_VERSION=0.1.0 -- --no-write-profile
has_out 'for aarch64-apple-darwin'
done_

HASHER=shasum case_ "shasum when sha256sum is missing (macOS)" 0 MEMPROVE_VERSION=0.1.0 -- --no-write-profile
has_out 'SHA-256 matches'
done_
HASHER=openssl case_ "openssl when sha256sum and shasum are missing" 0 MEMPROVE_VERSION=0.1.0 -- --no-write-profile
has_out 'SHA-256 matches'
done_
HASHER=none case_ "no hasher: stops before installing" 1 MEMPROVE_VERSION=0.1.0 -- --no-write-profile
has_out 'none of sha256sum, shasum or openssl'
not_installed
done_

# A damaged archive: same name, other bytes.
good="$T/rel/v0.1.0/memprove-0.1.0-x86_64-unknown-linux-gnu.tar.gz"
cp "$good" "$T/good.tar.gz"
printf 'x' >>"$good"
case_ "SHA-256 mismatch: stops, installs nothing" 1 MEMPROVE_VERSION=0.1.0 -- --no-write-profile
has_out 'download is damaged or was changed; nothing was installed'
not_installed
done_
cp "$T/good.tar.gz" "$good"

sums="$good.sha256"
cp "$sums" "$T/good.sha256"
printf 'not a checksum\n' >"$sums"
case_ ".sha256 without a SHA-256" 1 MEMPROVE_VERSION=0.1.0 -- --no-write-profile
has_out 'does not hold a SHA-256'
not_installed
done_
sed 's/  .*/  other.tar.gz/' "$T/good.sha256" >"$sums"
case_ ".sha256 naming another file" 1 MEMPROVE_VERSION=0.1.0 -- --no-write-profile
has_out "names 'other.tar.gz'"
not_installed
done_
cut -d' ' -f1 "$T/good.sha256" >"$sums"
case_ ".sha256 with the hash alone" 0 MEMPROVE_VERSION=0.1.0 -- --no-write-profile
has_out 'SHA-256 matches'
done_
cp "$T/good.sha256" "$sums"

case_ "a release that does not exist" 1 MEMPROVE_VERSION=9.9.9 -- --no-write-profile
has_out 'is there a release v9\.9\.9\?'
not_installed
done_

case_ "GitHub does not answer for the latest release" 1 FAKE_LATEST= -- --no-write-profile
has_out 'set MEMPROVE_VERSION'
not_installed
done_

case_ "MEMPROVE_VERSION that is not a version" 2 'MEMPROVE_VERSION=0.1.0;rm' -- --no-write-profile
has_out 'must be a release version'
no_download
done_
case_ "MEMPROVE_VERSION=1.2" 2 MEMPROVE_VERSION=1.2 -- --no-write-profile
has_out 'must be a release version'
done_

for p in "Darwin x86_64 Intel" "Linux aarch64 arm64" "Linux armv7l armv7l" "MINGW64_NT-10.0 x86_64 Windows" "FreeBSD amd64 FreeBSD"; do
  # shellcheck disable=SC2086 # split "<os> <arch> <label>" on purpose
  set -- $p
  case_ "unsupported: $3 ($1 $2)" 1 FAKE_UNAME_S="$1" FAKE_UNAME_M="$2" -- --no-write-profile
  has_out 'no release archive for'
  has_out 'install-upgrade-and-backup'
  no_download
  done_
done
case_ "unsupported: Linux x86_64 with musl" 1 FAKE_GLIBC= FAKE_MUSL=1 -- --no-write-profile
has_out 'musl'
no_download
done_
case_ "unsupported: Linux x86_64 with glibc 2.31" 1 FAKE_GLIBC=2.31 -- --no-write-profile
has_out 'glibc 2\.31: the archive needs glibc 2\.35'
no_download
done_
case_ "glibc 2.39 is fine" 0 FAKE_GLIBC=2.39 MEMPROVE_VERSION=0.1.0 -- --no-write-profile
done_
case_ "glibc 3.0 is fine" 0 FAKE_GLIBC=3.0 MEMPROVE_VERSION=0.1.0 -- --no-write-profile
done_

case_ "unknown argument" 2 -- --from-binaries /x
has_out 'unknown argument: --from-binaries'
no_download
done_
case_ "--prefix without a value" 2 -- --prefix
has_out '--prefix requires a value'
done_
case_ "--write-profile with --no-write-profile" 2 -- --write-profile --no-write-profile
has_out 'exclude each other'
done_
case_ "--help" 0 -- --help
has_out '^Usage: curl -fsSL https://memprove.dev/install.sh \| sh -s -- \[OPTIONS\]'
no_download
done_

case_ "install.sh fails: its status comes back" 1 FAKE_INSTALL_STATUS=1 MEMPROVE_VERSION=0.1.0 -- --no-write-profile
has_out "exited with status 1"
done_

# Piped, as `curl ... | sh -s -- ...` runs it.
name="piped into sh -s --"
rm -f "$T"/log/*.log
set +e
(cd "$T/cwd" && env -i PATH="$T/bin-sha256sum" "${base_env[@]}" MEMPROVE_VERSION=0.1.0 "$sh_bin" -s -- --no-write-profile <"$installer" >"$out" 2>&1)
got=$?
cat "$installer" | (cd "$T/cwd" && env -i PATH="$T/bin-sha256sum" "${base_env[@]}" MEMPROVE_VERSION=0.1.0 "$sh_bin" -s -- --no-write-profile >>"$out" 2>&1)
got2=$?
set -e
current_ok=1
[ "$got$got2" = 00 ] || note "exit status $got and $got2, expected 0"
installed_with "arg=--no-write-profile"
done_

# A download cut short runs nothing: every cut before the last line.
name="a truncated download runs nothing"
current_ok=1
size=$(wc -c <"$installer")
last=$(tail -n 1 "$installer" | wc -c)
for cut in $(seq 1 97 $((size - last - 1))); do
  rm -f "$T"/log/*.log
  head -c "$cut" "$installer" | (cd "$T/cwd" && env -i PATH="$T/bin-sha256sum" "${base_env[@]}" MEMPROVE_VERSION=0.1.0 "$sh_bin" -s -- --no-write-profile >"$out" 2>&1) || true
  if [ -e "$T/log/curl.log" ] || [ -e "$T/log/install.log" ]; then note "cut at byte $cut ran a step"; fi
done
done_

# In a terminal, with neither profile option, install.sh gets /dev/tty, so it can ask.
if command -v script >/dev/null 2>&1 && script -qec true /dev/null >/dev/null 2>&1; then
  for opt in "" --no-write-profile; do
    name="in a terminal${opt:+ with $opt}"
    rm -f "$T"/log/*.log
    cmd="cd '$T/cwd' && env -i PATH='$T/bin-sha256sum' ${base_env[*]} MEMPROVE_VERSION=0.1.0 '$sh_bin' -s -- $opt <'$installer'"
    script -qec "$cmd" /dev/null >"$out" 2>&1 </dev/null || true
    current_ok=1
    if [ -z "$opt" ]; then installed_with "stdin=tty"; else installed_with "stdin=notty"; fi
    done_
  done
else
  echo "script(1) cannot open a terminal here: the terminal cases were skipped"
fi

echo "test-install: $passed passed, $failed failed (shell: $sh_bin)"
[ "$failed" = 0 ]
