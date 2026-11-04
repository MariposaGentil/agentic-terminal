# Rule: project `tmux-agents/` overlay

**Scope:** when the session working directory (`SESSION_CWD`) is a **different
repo** from agentic-terminal (e.g. qapi-client) that ships its own
`tmux-agents/`.

**Rule:** On start, if `AGENT_PROJECT_CAPS_DIR` is set (auto-detected from
`$SESSION_CWD/tmux-agents` when that directory exists), also read **every file**
in `$AGENT_PROJECT_CAPS_DIR/rules/` and follow those rules alongside the
agentic-terminal rules.

When a task clearly belongs to the project in `term` (paths, `make qapi-client`,
etc.), read matching skills under `$AGENT_PROJECT_CAPS_DIR/skills/*/SKILL.md`.

**Project-specific domain rules belong in the project repo** — e.g.
qapi-client's `tmux-agents/rules/validate-use-raw-endpoints.md` — not in
agentic-terminal's `tmux-agents/`.

## Start with a project cwd

Both `term` and `agent` use the directory where you invoked start:

```bash
cd /path/to/qapi-client
/path/to/agentic-terminal/scripts/atstart.sh
# or:
make -C /path/to/agentic-terminal run
# or explicitly:
SESSION_CWD=/path/to/qapi-client make -C /path/to/agentic-terminal start
```

Or export `AGENT_PROJECT_CAPS_DIR=/path/to/qapi-client/tmux-agents` explicitly.

Generic driver rules (`session-workdir.md`, `driving-rules.md`,
`no-system-exit.md`, …) stay in agentic-terminal; qapi ProfileRules / GVA /
Validate behavior stays in qapi-client's `tmux-agents/`.
