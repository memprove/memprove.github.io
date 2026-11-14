# memprove

> memprove is a memory and task-state layer for coding agents. Every fact an agent records is bound to a commit, a repository state and a passing test run, and a deterministic rule, not a model, decides whether it is still `verified`, `stale`, `unconfirmed` or `tampered`. A local daemon keeps the record in a hash-chained ledger; a new session reads a compact Context Pack of what holds, what is open and what to do next. It runs on macOS (Apple silicon) and Linux x86_64, works with Claude Code, Codex and Cursor, and sends nothing off the machine. Current release: {{version}}.

## Set memprove up in this repository

These are the steps for a coding agent whose user asked it to set memprove up. Run each command on its own and read its output before the next one. Every step is safe to run again. Tell the user what you did and which files changed when you are done.

1. Check for an installation: `memprove --version`. If it prints `memprove {{version}}` or later, skip to step 4. If `~/.memprove/bin/memprove` exists but is not on `PATH`, run `export PATH="$HOME/.memprove/bin:$PATH"` and skip to step 4.

2. Pick the release archive for this machine from `uname -sm`:
   - `Darwin arm64`: `aarch64-apple-darwin`
   - `Linux x86_64` (glibc 2.35 or later, such as Ubuntu 22.04 or Debian 12): `x86_64-unknown-linux-gnu`
   - anything else (Intel macOS, Linux arm64, Windows): there is no release binary. Stop and tell the user; building from source is described at https://memprove.dev/docs/guide/install-upgrade-and-backup.md and needs a Rust toolchain and libclang.

3. Download, verify and install, in a temporary directory outside the repository (never inside it):

   ```bash
   cd "$(mktemp -d)"
   target=aarch64-apple-darwin        # or x86_64-unknown-linux-gnu, from step 2
   base={{base}}
   curl -fLO "$base/memprove-{{version}}-$target.tar.gz"
   curl -fLO "$base/memprove-{{version}}-$target.tar.gz.sha256"
   shasum -a 256 -c "memprove-{{version}}-$target.tar.gz.sha256"     # Linux without shasum: sha256sum -c
   tar -xzf "memprove-{{version}}-$target.tar.gz"
   "memprove-{{version}}-$target/scripts/install.sh" --from-binaries "memprove-{{version}}-$target/bin" --no-write-profile
   export PATH="$HOME/.memprove/bin:$PATH"
   memprove --version
   ```

   Stop if the checksum does not match. `install.sh` installs into `~/.memprove`, starts the daemon `memproved` and writes the operator's token to `~/.memprove/operator-token`. Never read, print or copy that file or `~/.memprove/config/token`, and never put a token into a file of the repository. `--no-write-profile` leaves the shell profile alone; ask the user before you run `install.sh` again with `--write-profile`, which adds the `PATH` line to their profile so that later sessions find `memprove`.

4. Go to the repository's root (a Git worktree with at least one commit) and enable it:

   ```bash
   memprove init
   ```

   It registers the repository as a Project, adds memprove's client files to `.git/info/exclude`, writes the configuration of the clients it detects and ends with `memprove doctor`: for Claude Code the SessionStart hook in `.claude/settings.local.json` and the MCP server in `.mcp.json`; for Codex `[mcp_servers.memprove]` in `~/.codex/config.toml` and a short note in `AGENTS.md`; for Cursor `.cursor/mcp.json` and `.cursor/rules/memprove.mdc`. `memprove init --dry-run` describes the changes first; `--client claude-code` (or `codex`, `cursor`) picks clients. Before the first Session, doctor's `workspace` and `ledger` lines are `WARN`: that is expected. Any `FAIL` line says what to fix.

   Claude Code's allow rules (`mcp__memprove`, `Bash(memprove run:*)` and the same rule with the absolute path) are printed, not written. `memprove init --allow-tools` writes them; ask the user first.

5. Tell the user: which files `init` wrote; that `AGENTS.md` and `.cursor/rules/memprove.mdc` are repository content they may want to commit; and that the client picks up the hook and the MCP server at its next start (Claude Code asks once to approve a project MCP server from `.mcp.json`).

6. Use it on the work you were asked to do, not on a separate setup Task:

   ```bash
   memprove begin --new-task "<the task you are working on>"
   # ... edit, then commit: a fact is verified only while the repository is in the state its run saw ...
   memprove run --test-format pytest -- python3 -m pytest -q      # or: memprove run --test-format cargo -- cargo test
   memprove checkpoint create --fact "<what now holds, in one sentence>" --evidence r1 --next "<the next step>"
   memprove resume --pack
   memprove end --reason "<what was done>"
   ```

   `memprove run` prints the run's label (`r1`, `r2`, …) on the last line of standard error; cite it with `--evidence`. After the first run, check `git status --short`: an untracked file, such as the `__pycache__/` a Python test run leaves behind, makes every fact on the run `unconfirmed` (`untracked_files_not_captured`). Add such files to `.git/info/exclude` (or to `.gitignore`, after asking the user) and run the tests again before you record a fact. In a Claude Code session started after `init`, the hook already put the Context Pack at the top of the session; read it before `begin`.

## Rules while you work

- Keep `git status --short` free of untracked files (`??`) when you run the tests: a run in a state with an untracked file supports no fact.
- Run tests through `memprove run`, as a command of its own: not joined to another command with `&&`, `;` or a pipe. Only `memprove run` records Evidence.
- A fact needs a passed test run (exit code 0, at least one test case). Record a failure as an open item: `memprove checkpoint create --open "<what fails>" --evidence last --next "<fix>"`.
- Commit before the run you cite. An edit, a commit or a branch switch after the run makes the fact `stale`; `memprove resume --pack` then names the command to run again (`Rerun:`), and `memprove checkpoint create --reaffirm-all --next "<next>"` reaffirms the stale facts on the passing rerun.
- Word a fact by what holds, conclusion first; the Pack may keep only its first 120 characters.
- Never edit or delete memprove's data under `~/.memprove`; nothing in the record is deleted. Supersede or withdraw a statement instead (see "Correcting the record").
- A Session another agent left open: follow "Unattended takeover" before ending it.

## Docs

{{pages}}

## Optional

- [Full text of every docs page](https://memprove.dev/llms-full.txt): the pages above in one file.
- [Source repository](https://github.com/memprove/memprove): Rust workspace, Apache-2.0. These docs were generated from commit {{commit}}.
- [Release {{tag}}](https://github.com/memprove/memprove/releases/tag/{{tag}}): archives and their SHA-256 files.
