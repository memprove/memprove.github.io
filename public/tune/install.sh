#!/bin/sh
# memprove-tune's one-line installer, served at https://memprove.dev/tune/install.sh.
#
#   curl -fsSL https://memprove.dev/tune/install.sh | sh
#   curl -fsSL https://memprove.dev/tune/install.sh | sh -s -- --write-profile
#   curl -fsSL https://memprove.dev/tune/install.sh | MEMPROVE_TUNE_VERSION=0.1.0 sh
#
# It picks the release archive for this machine (macOS on Apple silicon, or
# Linux x86_64 with glibc 2.35 or later), downloads the archive and its
# .sha256 file from the GitHub release of memprove/memprove-tune, stops
# unless the SHA-256 matches, unpacks it in a temporary directory, checks
# that the binary runs here and says the version that was asked for, and
# puts it at ~/.memprove-tune/bin/memprove-tune (or under --prefix). A
# binary that is already there is replaced. The temporary directory is
# removed at the end.
#
# That one file is all it installs: there is no daemon and no
# configuration, and the shell profile is written only with
# --write-profile. To remove memprove-tune, delete the directory.
#
# Everything runs inside main, called on the last line, so a download that
# is cut short runs nothing. POSIX sh.
set -eu

REPO_URL="https://github.com/memprove/memprove-tune"
PROFILE_BEGIN="# >>> memprove-tune (install.sh) >>>"
PROFILE_END="# <<< memprove-tune <<<"

say() { printf 'memprove-tune-install: %s\n' "$*"; }
err() { printf 'memprove-tune-install: error: %s\n' "$*" >&2; }
die() {
  err "$@"
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: curl -fsSL https://memprove.dev/tune/install.sh | sh -s -- [OPTIONS]
       sh install.sh [OPTIONS]

Installs the memprove-tune release for this machine as
~/.memprove-tune/bin/memprove-tune (or under the --prefix directory), in
place of the one that may be there. The archive's SHA-256 is checked before
anything is installed. Nothing else is written.

Options:
  --prefix <DIR>       installation directory, an absolute path
                       (default: $HOME/.memprove-tune)
  --write-profile      write the PATH line into the shell profile
                       ($SHELL: ~/.zshrc, ~/.bash_profile on macOS,
                       ~/.bashrc on Linux, or fish's config.fish)
  --no-write-profile   change no profile; this is the default
  -h, --help           print this help

Environment:
  MEMPROVE_TUNE_VERSION   the release to install, such as 0.1.0
                          (default: the latest release)

Release archives exist for macOS on Apple silicon (aarch64-apple-darwin)
and Linux x86_64 with glibc 2.35 or later (x86_64-unknown-linux-gnu). On
any other platform, build from source with Rust 1.89 or later:
  cargo install --locked --git https://github.com/memprove/memprove-tune memprove-tune

Exit status: 0 installed, 1 a step failed, 2 usage error.
USAGE
}

# Downloads $1 to the file $2. --proto '=https' keeps every redirect on HTTPS.
fetch() {
  curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o "$2" "$1"
}

unsupported() {
  err "there is no release archive for $1."
  err "Build memprove-tune from source instead (Rust 1.89 or later):"
  err "  cargo install --locked --git $REPO_URL memprove-tune"
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
    *[!0-9.]* | .* | *.)
      say "warning: could not read the glibc version ($libc); the archive needs glibc 2.35 or later"
      return 0
      ;;
  esac
  if [ "$major" -lt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -lt 35 ]; }; then
    unsupported "Linux x86_64 with glibc $glibc: the archive needs glibc 2.35 or later (Ubuntu 22.04, Debian 12)"
  fi
}

# Sets os and target to the system and the release target triple of this
# machine, or exits.
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
        *) unsupported "Linux on $arch" ;;
      esac
      ;;
    MINGW* | MSYS* | CYGWIN* | Windows_NT) unsupported "Windows (memprove-tune runs on macOS and Linux; WSL 2 counts as Linux)" ;;
    *) unsupported "$os on $arch" ;;
  esac
}

bad_version() {
  err "MEMPROVE_TUNE_VERSION must be a release version such as 0.1.0, not '$1'"
  exit 2
}

# Sets version from MEMPROVE_TUNE_VERSION when it is given. Asks nobody.
given_version() {
  version=${MEMPROVE_TUNE_VERSION:-latest}
  [ "$version" != latest ] || return 0
  version=${version#v}
  case "$version" in
    *[!0-9A-Za-z.+-]*) bad_version "$version" ;;
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) bad_version "$version" ;;
  esac
}

# Sets version to the latest release on GitHub when none was given.
resolve_version() {
  [ "$version" = latest ] || return 0
  # github.com/<repo>/releases/latest answers with a redirect to
  # /releases/tag/<tag>; reading the redirect needs no API token and has no
  # rate limit.
  location=$(curl --proto '=https' --tlsv1.2 -fsS --retry 3 -o /dev/null -w '%{redirect_url}' "$REPO_URL/releases/latest") ||
    die "could not ask GitHub for the latest release ($REPO_URL/releases/latest); set MEMPROVE_TUNE_VERSION, such as MEMPROVE_TUNE_VERSION=0.1.0"
  case "$location" in
    */releases/tag/?*) version=${location##*/releases/tag/} ;;
    *) die "could not find the latest release at $REPO_URL/releases/latest; set MEMPROVE_TUNE_VERSION, such as MEMPROVE_TUNE_VERSION=0.1.0" ;;
  esac
  version=${version#v}
  case "$version" in
    *[!0-9A-Za-z.+-]*) die "GitHub names '$version' as the latest release, which is no version; set MEMPROVE_TUNE_VERSION" ;;
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) die "GitHub names '$version' as the latest release, which is no version; set MEMPROVE_TUNE_VERSION" ;;
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
    die "found none of sha256sum, shasum or openssl to check the download with; nothing was installed"
  fi
  printf '%s\n' "${sum%% *}" | tr 'A-F' 'a-f'
}

# The profile file of the login shell ($SHELL): zsh, bash (macOS reads
# ~/.bash_profile for a login shell, Linux ~/.bashrc), or fish; empty for
# another shell.
profile_file() {
  case "$(basename "${SHELL:-}")" in
    zsh) printf '%s\n' "$HOME/.zshrc" ;;
    bash)
      if [ "$os" = Darwin ]; then printf '%s\n' "$HOME/.bash_profile"; else printf '%s\n' "$HOME/.bashrc"; fi
      ;;
    fish) printf '%s\n' "$HOME/.config/fish/config.fish" ;;
    *) printf '\n' ;;
  esac
}

# The line that puts $bin on PATH, in the form the shell named $1 reads.
path_line() {
  # $PATH stays as it is written: the shell that reads the profile expands it.
  if [ "$1" = fish ]; then
    # shellcheck disable=SC2016
    printf 'set -gx PATH %s $PATH\n' "$bin"
  else
    # shellcheck disable=SC2016
    printf 'export PATH="%s:$PATH"\n' "$bin"
  fi
}

# Writes the PATH line into the file $1 between two marker lines, in place
# of an earlier block between them; every other line of the file stays.
write_profile_block() {
  mkdir -p "$(dirname "$1")"
  new="$1.memprove-tune.new"
  if [ -f "$1" ]; then
    awk -v begin="$PROFILE_BEGIN" -v end="$PROFILE_END" '
      $0 == begin { skipping = 1; next }
      $0 == end { skipping = 0; next }
      !skipping { print }
    ' "$1" >"$new"
  else
    : >"$new"
  fi
  if [ -s "$new" ] && [ -n "$(tail -c 1 "$new")" ]; then printf '\n' >>"$new"; fi
  {
    printf '%s\n' "$PROFILE_BEGIN"
    path_line "$(basename "${SHELL:-}")"
    printf '%s\n' "$PROFILE_END"
  } >>"$new"
  mv "$new" "$1"
  say "wrote the PATH line to $1 (between two marker lines; a new shell reads it)"
}

# Says how memprove-tune gets on PATH, or writes the profile when asked.
path_advice() {
  shell_name=$(basename "${SHELL:-}")
  file=$(profile_file)
  if [ "$profile" = --write-profile ]; then
    if [ -n "$file" ]; then
      write_profile_block "$file"
      return 0
    fi
    say "the login shell ${shell_name:-(unknown)} is not zsh, bash or fish, so no profile was written; put this line in its profile yourself:"
    say "  $(path_line sh)"
    return 0
  fi
  case ":${PATH:-}:" in
    *":$bin:"*) return 0 ;;
  esac
  say "$bin is not on PATH. Add this line to ${file:-the profile of your shell}, or run the installer again with --write-profile:"
  say "  $(path_line "$shell_name")"
}

tmp=""
cleanup() {
  if [ -n "$tmp" ]; then rm -rf "$tmp"; fi
}

main() {
  profile=""
  prefix=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -h | --help)
        usage
        exit 0
        ;;
      --prefix)
        if [ $# -lt 2 ] || [ -z "$2" ]; then
          err "--prefix requires a value"
          exit 2
        fi
        prefix=$2
        shift
        ;;
      --prefix=?*) prefix=${1#--prefix=} ;;
      --write-profile | --no-write-profile)
        if [ -n "$profile" ] && [ "$profile" != "$1" ]; then
          err "--write-profile and --no-write-profile exclude each other"
          exit 2
        fi
        profile=$1
        ;;
      *)
        err "unknown argument: $1"
        usage >&2
        exit 2
        ;;
    esac
    shift
  done
  if [ -z "$prefix" ]; then
    [ -n "${HOME:-}" ] || die "HOME is not set; name the installation directory with --prefix"
    prefix="$HOME/.memprove-tune"
  fi
  case "$prefix" in
    /*) ;;
    *)
      err "--prefix must be an absolute path, not '$prefix'"
      exit 2
      ;;
  esac
  bin="${prefix%/}/bin"
  given_version

  for cmd in curl tar uname mktemp; do
    command -v "$cmd" >/dev/null 2>&1 || die "this installer needs $cmd, which is not on PATH"
  done

  detect_target
  resolve_version
  name="memprove-tune-$version-$target"
  archive="$name.tar.gz"
  base="$REPO_URL/releases/download/v$version"
  say "installing memprove-tune $version for $target"

  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/memprove-tune-install.XXXXXX") || die "could not create a temporary directory"

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

  tar -xzf "$tmp/$archive" -C "$tmp" || die "could not unpack $archive; nothing was installed"
  fresh="$tmp/$name/bin/memprove-tune"
  [ -f "$fresh" ] || die "$archive has no $name/bin/memprove-tune; nothing was installed"
  chmod 755 "$fresh"
  said=$("$fresh" --version 2>/dev/null) ||
    die "the memprove-tune in $archive does not run on this machine; nothing was installed"
  [ "$said" = "memprove-tune $version" ] ||
    die "the memprove-tune in $archive says '$said', not 'memprove-tune $version'; nothing was installed"

  before=""
  if [ -x "$bin/memprove-tune" ]; then before=$("$bin/memprove-tune" --version 2>/dev/null || echo "a memprove-tune that does not run"); fi
  mkdir -p "$bin" || die "could not create $bin; nothing was installed"
  # Copied next to its place first, then moved over it: a run that is cut
  # short leaves the old binary or the new one, never half of one.
  cp "$fresh" "$bin/.memprove-tune.new" || die "could not write into $bin; nothing was installed"
  chmod 755 "$bin/.memprove-tune.new"
  mv -f "$bin/.memprove-tune.new" "$bin/memprove-tune" || die "could not put memprove-tune into $bin"

  if [ -n "$before" ]; then
    say "installed memprove-tune $version at $bin/memprove-tune (replaced $before)"
  else
    say "installed memprove-tune $version at $bin/memprove-tune"
  fi
  path_advice
  say "next, in a repository: memprove-tune scan"
}

main "$@"
