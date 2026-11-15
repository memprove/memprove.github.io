{{readme-intro}}

简体中文：[中文快速上手](/zh/)

## 1. Install

On macOS on Apple silicon, or Linux x86_64 with glibc 2.35 or later (such as Ubuntu 22.04 and Debian 12):

```bash
curl -fsSL https://memprove.dev/install.sh | sh
export PATH="$HOME/.memprove/bin:$PATH"     # --write-profile puts it in the profile
memprove --version
```

[The installer](/install.sh) picks the release archive for the machine (`aarch64-apple-darwin` or `x86_64-unknown-linux-gnu`) from the latest [GitHub release](https://github.com/memprove/memprove/releases), stops unless the archive's SHA-256 matches its `.sha256` file, and runs the archive's own `scripts/install.sh --from-binaries bin`: memprove goes into `~/.memprove` and the daemon starts. Run it again to upgrade; the data is backed up first. Options go after `sh -s --`:

```bash
# also write the PATH line into the shell profile
curl -fsSL https://memprove.dev/install.sh | sh -s -- --write-profile
# change no profile and ask nothing
curl -fsSL https://memprove.dev/install.sh | sh -s -- --no-write-profile
# another directory; it then also needs the MEMPROVE_* lines it prints
curl -fsSL https://memprove.dev/install.sh | sh -s -- --prefix ~/tools/memprove
# a given release instead of the latest
curl -fsSL https://memprove.dev/install.sh | MEMPROVE_VERSION={{version}} sh
```

With neither profile option, a run in a terminal asks once before it changes the profile. Linux on arm64 is not supported yet, and the installer stops on any platform without a release archive; build from source there, as [Install, upgrade and backup](/docs/guide/install-upgrade-and-backup/) says.

### By hand

The same steps without the installer, release {{version}}:

```bash
target=aarch64-apple-darwin        # or x86_64-unknown-linux-gnu
base={{base}}
curl -LO "$base/memprove-{{version}}-$target.tar.gz"
curl -LO "$base/memprove-{{version}}-$target.tar.gz.sha256"
shasum -a 256 -c "memprove-{{version}}-$target.tar.gz.sha256"
tar -xzf "memprove-{{version}}-$target.tar.gz"
cd "memprove-{{version}}-$target"
scripts/install.sh --from-binaries bin        # installs into ~/.memprove and starts the daemon
export PATH="$HOME/.memprove/bin:$PATH"       # --write-profile puts this line in your shell profile
```

The macOS binaries are not notarized: if a browser downloaded the archive, clear the quarantine flag first (`xattr -dr com.apple.quarantine memprove-{{version}}-aarch64-apple-darwin`). Archives that `curl` downloads, as the installer does, carry no such flag.

## 2. Enable a repository

From inside the repository's Git worktree (it needs at least one commit):

```bash
memprove init
```

`init` registers the Project, keeps memprove's own files out of your Evidence through `.git/info/exclude`, writes the configuration of the clients it finds (Claude Code: the SessionStart hook in `.claude/settings.local.json` and `.mcp.json`; Codex: `~/.codex/config.toml` and a note in `AGENTS.md`; Cursor: `.cursor/mcp.json` and a rule), and ends with `memprove doctor`. Running it again changes nothing. `--client` names the clients; `--allow-tools` also writes Claude Code's allow rules for the MCP server and `memprove run`. Before the first Session, `doctor` prints two `WARN` lines (`workspace`, `ledger`); both pass after it. [Enabling memprove in a project](/docs/guide/enabling-memprove-in-a-project/) has the details.

## 3. One session, five commands

{{readme:One session, five commands}}

A run supports facts only while `git status --short` lists no untracked files. A Python test run leaves `__pycache__/` behind: add it to `.gitignore` or `.git/info/exclude` before the run you cite, or the fact reads `unconfirmed`.

## What the next session reads

This is the Pack of a real session in [tinyini](https://github.com/memprove/memprove.github.io/tree/main/demo/tinyini), a small Python repository, right after its first checkpoint ([every command of that session](/how-it-works/#every-command-as-recorded)):

````text
{{demo:05-pack-verified}}
````

## Taking over

{{readme:Taking over}}

## Next

- [The agent's guide](/docs/guide/): every command, the Pack, the hook, the MCP server and the exit codes.
- [How it works](/how-it-works/): the daemon, the ledger, Evidence and verdicts, with a recorded session.
- [llms.txt](/llms.txt): the same setup, written for a coding agent to follow.
