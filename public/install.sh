#!/bin/sh
# memprove's one-line installer, served at https://memprove.dev/install.sh.
#
#   curl -fsSL https://memprove.dev/install.sh | sh
#   curl -fsSL https://memprove.dev/install.sh | sh -s -- --no-write-profile
#   curl -fsSL https://memprove.dev/install.sh | MEMPROVE_VERSION=0.1.0 sh
#
# It picks the release archive for this machine (macOS on Apple silicon, or
# Linux x86_64 with glibc 2.35 or later), downloads the archive and its
# .sha256 file from the GitHub release of memprove/memprove, stops unless the
# SHA-256 matches, unpacks it in a temporary directory and runs the archive's
# own `scripts/install.sh --from-binaries bin`. That script installs into
# ~/.memprove (or --prefix), starts the daemon, and on an existing
# installation upgrades it. The temporary directory is removed at the end.
#
# Everything runs inside main, called on the last line, so a download that
# is cut short runs nothing. POSIX sh; the release's install.sh needs bash.
set -eu

REPO_URL="https://github.com/memprove/memprove"
SOURCE_DOCS="https://memprove.dev/docs/guide/install-upgrade-and-backup/"

say() { printf 'memprove-install: %s\n' "$*"; }
err() { printf 'memprove-install: error: %s\n' "$*" >&2; }
die() {
  err "$@"
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: curl -fsSL https://memprove.dev/install.sh | sh -s -- [OPTIONS]
       sh install.sh [OPTIONS]

Installs the memprove release for this machine into ~/.memprove (or the
--prefix directory) and starts its daemon, or upgrades the installation
already there. The archive's SHA-256 is checked before anything is installed.

Options, passed on to the release's scripts/install.sh:
  --prefix <DIR>       installation directory (default: $HOME/.memprove)
  --write-profile      write the PATH line into the shell profile
  --no-write-profile   change no profile and ask nothing
                       (with neither, a run from a terminal asks once)
  -h, --help           print this help

Environment:
  MEMPROVE_VERSION     the release to install, such as 0.1.0
                       (default: the latest release)

Release archives exist for macOS on Apple silicon (aarch64-apple-darwin)
and Linux x86_64 with glibc 2.35 or later (x86_64-unknown-linux-gnu). On
any other platform, build from source:
  https://memprove.dev/docs/guide/install-upgrade-and-backup/

Exit status: 0 installed, 1 a step failed, 2 usage error.
USAGE
}

# Downloads $1 to the file $2. --proto '=https' keeps every redirect on HTTPS.
fetch() {
  curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o "$2" "$1"
}

unsupported() {
  err "there is no release archive for $1."
  err "Build memprove from source instead (Rust 1.96 and libclang): $SOURCE_DOCS"
  err "In short: git clone $REPO_URL && cd memprove && scripts/install.sh"
  exit 1
}

# The release archive is linked against glibc 2.35. Fails on musl (Alpine)
# and on an older glibc; goes on with a warning when it cannot tell.
check_glibc() {
  libc=$(getconf GNU_LIBC_VERSION 2>/dev/null || true)
  case "$libc" in
    "glibc "*) ;;
    *)
      if (ldd --version 2>&1 || true) | grep -qi musl; then
        unsupported "Linux x86_64 with musl libc (such as Alpine): the archive needs glibc 2.35 or later"
      fi
      say "warning: could not read the glibc version; the archive needs glibc 2.35 or later"
      return 0
      ;;
  esac
  glibc=${libc#glibc }
  major=${glibc%%.*}
  minor=${glibc#*.}
  minor=${minor%%[!0-9]*}
  case "$major.$minor" in
    *[!0-9.]* | .* | *.) say "warning: could not read the glibc version ($libc); the archive needs glibc 2.35 or later"; return 0 ;;
  esac
  if [ "$major" -lt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -lt 35 ]; }; then
    unsupported "Linux x86_64 with glibc $glibc: the archive needs glibc 2.35 or later (Ubuntu 22.04, Debian 12)"
  fi
}

# Sets target to the release target triple of this machine, or exits.
detect_target() {
  os=$(uname -s 2>/dev/null || echo unknown)
  arch=$(uname -m 2>/dev/null || echo unknown)
  case "$os" in
    Darwin)
      # A shell running under Rosetta 2 reports x86_64 on Apple silicon.
      if [ "$arch" = x86_64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then
        arch=arm64
      fi
      case "$arch" in
        arm64 | aarch64) target=aarch64-apple-darwin ;;
        *) unsupported "macOS on $arch (Intel Macs)" ;;
      esac
      ;;
    Linux)
      case "$arch" in
        x86_64 | amd64)
          check_glibc
          target=x86_64-unknown-linux-gnu
          ;;
        aarch64 | arm64) unsupported "Linux on $arch (arm64 is not supported yet)" ;;
        *) unsupported "Linux on $arch" ;;
      esac
      ;;
    MINGW* | MSYS* | CYGWIN* | Windows_NT) unsupported "Windows (memprove runs on macOS and Linux; WSL 2 counts as Linux)" ;;
    *) unsupported "$os on $arch" ;;
  esac
}

# Sets version from MEMPROVE_VERSION, or from the latest release on GitHub.
resolve_version() {
  version=${MEMPROVE_VERSION:-latest}
  if [ "$version" = latest ]; then
    # github.com/<repo>/releases/latest answers with a redirect to
    # /releases/tag/<tag>; reading the redirect needs no API token and no rate limit.
    location=$(curl --proto '=https' --tlsv1.2 -fsS --retry 3 -o /dev/null -w '%{redirect_url}' "$REPO_URL/releases/latest") ||
      die "could not ask GitHub for the latest release ($REPO_URL/releases/latest); set MEMPROVE_VERSION, such as MEMPROVE_VERSION=0.1.0"
    case "$location" in
      */releases/tag/?*) version=${location##*/releases/tag/} ;;
      *) die "could not find the latest release at $REPO_URL/releases/latest; set MEMPROVE_VERSION, such as MEMPROVE_VERSION=0.1.0" ;;
    esac
  fi
  version=${version#v}
  case "$version" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) err "MEMPROVE_VERSION must be a release version such as 0.1.0, not '$version'"; exit 2 ;;
  esac
  case "$version" in
    *[!0-9A-Za-z.+-]*) err "MEMPROVE_VERSION must be a release version such as 0.1.0, not '$version'"; exit 2 ;;
  esac
}

# Prints the SHA-256 of the file $1 in lowercase hex.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sum=$(sha256sum "$1")
  elif command -v shasum >/dev/null 2>&1; then
    sum=$(shasum -a 256 "$1")
  elif command -v openssl >/dev/null 2>&1; then
    sum=$(openssl dgst -sha256 -r "$1")
  else
    die "found none of sha256sum, shasum or openssl to check the download with"
  fi
  printf '%s\n' "${sum%% *}" | tr 'A-F' 'a-f'
}

tmp=""
cleanup() {
  if [ -n "$tmp" ]; then rm -rf "$tmp"; fi
}

main() {
  profile=""
  expect_prefix=0
  for arg in "$@"; do
    if [ "$expect_prefix" = 1 ]; then
      expect_prefix=0
      continue
    fi
    case "$arg" in
      -h | --help)
        usage
        exit 0
        ;;
      --prefix) expect_prefix=1 ;;
      --prefix=?*) ;;
      --write-profile | --no-write-profile)
        if [ -n "$profile" ] && [ "$profile" != "$arg" ]; then
          err "--write-profile and --no-write-profile exclude each other"
          exit 2
        fi
        profile=$arg
        ;;
      *)
        err "unknown argument: $arg"
        usage >&2
        exit 2
        ;;
    esac
  done
  if [ "$expect_prefix" = 1 ]; then
    err "--prefix requires a value"
    exit 2
  fi

  for cmd in curl tar uname mktemp bash; do
    command -v "$cmd" >/dev/null 2>&1 || die "this installer needs $cmd, which is not on PATH"
  done

  detect_target
  resolve_version
  name="memprove-$version-$target"
  archive="$name.tar.gz"
  base="$REPO_URL/releases/download/v$version"
  say "installing memprove $version for $target"

  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/memprove-install.XXXXXX") || die "could not create a temporary directory"

  say "downloading $base/$archive"
  fetch "$base/$archive.sha256" "$tmp/$archive.sha256" ||
    die "could not download $base/$archive.sha256: is there a release v$version? The releases: $REPO_URL/releases"
  fetch "$base/$archive" "$tmp/$archive" ||
    die "could not download $base/$archive"

  read -r expected listed <"$tmp/$archive.sha256" || true
  expected=$(printf '%s\n' "${expected:-}" | tr 'A-F' 'a-f')
  case "$expected" in
    *[!0-9a-f]* | "") die "$archive.sha256 does not hold a SHA-256; nothing was installed" ;;
  esac
  [ "${#expected}" -eq 64 ] || die "$archive.sha256 does not hold a SHA-256; nothing was installed"
  listed=${listed:-}
  [ -z "$listed" ] || [ "${listed#\*}" = "$archive" ] || die "$archive.sha256 names '$listed', not $archive; nothing was installed"
  actual=$(sha256_of "$tmp/$archive")
  if [ "$actual" != "$expected" ]; then
    err "the SHA-256 of $archive is $actual,"
    err "but $archive.sha256 says $expected."
    die "the download is damaged or was changed; nothing was installed"
  fi
  say "SHA-256 matches $archive.sha256: $actual"

  tar -xzf "$tmp/$archive" -C "$tmp" || die "could not unpack $archive"
  for f in scripts/install.sh bin/memprove bin/memproved; do
    [ -f "$tmp/$name/$f" ] || die "$archive has no $name/$f; nothing was installed"
  done

  # The release's install.sh asks before it writes the shell profile when
  # neither option is given and it runs in a terminal. Under `curl | sh` the
  # script's stdin is the download, so the question goes to /dev/tty.
  status=0
  if [ -z "$profile" ] && [ -t 1 ] && (: </dev/tty) 2>/dev/null; then
    bash "$tmp/$name/scripts/install.sh" --from-binaries "$tmp/$name/bin" "$@" </dev/tty || status=$?
  else
    bash "$tmp/$name/scripts/install.sh" --from-binaries "$tmp/$name/bin" "$@" </dev/null || status=$?
  fi
  if [ "$status" -ne 0 ]; then
    err "the release's scripts/install.sh exited with status $status (see its messages above)"
    exit "$status"
  fi
  say "done: memprove $version ($target); the lines above say what comes next"
}

main "$@"
