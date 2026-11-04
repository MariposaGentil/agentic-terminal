# Rule: session working directory

**Scope:** where `term` and `agent` run, and how you invoke the toolkit.

## Policy

Both **`term` and `agent` share the same initial working directory**: the
directory where `make start`, `make run`, `./run.sh`, or `atstart` was invoked
(`$PWD` at launch). That value is exported as `SESSION_CWD` in both tmux
sessions.

The agentic-terminal repo itself is **`AGENTIC_TERMINAL_ROOT`** (also set in both
sessions). Capabilities (`tmux-agents/`, `scripts/`, `logs/`) live there — not
in the project cwd.

## Agent: run the toolkit by absolute path

Your shell cwd is `$SESSION_CWD` (often a project repo). **Do not** assume
`scripts/` exists in cwd. Always invoke:

```bash
$AGENTIC_TERMINAL_ROOT/scripts/read.sh
$AGENTIC_TERMINAL_ROOT/scripts/requests.sh
echo 'CMD' | $AGENTIC_TERMINAL_ROOT/scripts/send.sh
$AGENTIC_TERMINAL_ROOT/scripts/say.sh 'MSG'
```

Read prompt/rules from `$AGENTIC_TERMINAL_ROOT/tmux-agents/` (plus any project
overlay under `$SESSION_CWD/tmux-agents/` — see
`project-tmux-agents-overlay.md`).

## Human: start from the project you want

```bash
cd /path/to/qapi-client
/path/to/agentic-terminal/scripts/atstart.sh   # recommended
# or:
SESSION_CWD=$PWD make -C /path/to/agentic-terminal start
```

Both sessions open in `/path/to/qapi-client`. Override explicitly with
`SESSION_CWD=/other/path make start` when needed.

**Note:** plain `make -C … start` runs recipes inside the toolkit directory, so
pass `SESSION_CWD=$PWD` (as above) or use `atstart` from the project folder.

## Reusing sessions

If `term` or `agent` already exists, `start.sh` reuses it **without changing
cwd**. Run `make stop` first when you need a different working directory.
