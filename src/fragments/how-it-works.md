memprove never asks a model whether a memory still holds. A fact cites test runs; each run sealed the repository state it ran in; on every read the daemon probes the repository again and a fixed rule gives the fact its verdict. Here is that happening in a real repository, then how it is built.

## One fact, three verdicts

[tinyini](https://github.com/memprove/memprove.github.io/tree/main/demo/tinyini) is a small INI parser in Python, kept in this site's repository so that every output here is real. `demo/record.sh` builds it commit by commit and runs the commands below with memprove {{version}} and pytest. Nothing in the output is edited, except that the home directory is written as `~`.

### Verified: recorded on a passing run

Session 1 commits the change for the Task `parser: handle empty input`, runs the tests through `memprove run` (they pass as `r1`) and records four facts citing that run. The repository is still in the state `r1` ran in, so every fact reads `verified`:

````text
{{demo:05-text-verified}}
````

### Stale: the code moved on

Session 1 ends. Someone then commits `558cb252ae87` ("parser: strip inline comments from values") without running anything through memprove. The facts were not edited, but the state they were bound to is gone: every one reads `stale`, with the reasons, the files that changed, and the command that would confirm them again:

````text
{{demo:07-text-stale}}
````

### Verified again: a passing rerun

Session 2 reads that, runs `python3 -m pytest -q` through `memprove run` (it passes as `r1` of this Session) and reaffirms the stale facts on it with `checkpoint create --reaffirm-all`. The old statements are kept as superseded; the new ones are bound to `558cb252ae87`:

````text
{{demo:11-text-reverified}}
````

## What the next session reads

When Session 2 started, Claude Code's SessionStart hook put this in front of the agent before its first message: one opening statement, then the Context Pack in a fence. The same ledger, repository state and budget always give the same bytes, and the last line is the SHA-256 of the lines above it.

````text
{{demo:07-hook-stale}}
````

## Every command, as recorded

<details>
<summary>Both Sessions, command by command (standard output and standard error)</summary>

````text
{{demo:01-init}}

{{demo:02-begin}}

{{demo:03-run}}

{{demo:04-checkpoint}}

{{demo:05-pack-verified}}

{{demo:06-end}}

$ git commit -m "parser: strip inline comments from values"

{{demo:07-hook-stale}}

{{demo:08-begin}}

{{demo:09-run}}

{{demo:10-reaffirm}}

{{demo:11-pack-reverified}}

{{demo:12-ledger}}

{{demo:13-end}}
````

</details>

## How it is built
