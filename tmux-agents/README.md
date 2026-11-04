# `tmux-agents/` — the tmux agent's capabilities

This folder is the single home for everything that defines what the
**agentic-terminal tmux agent** knows and can do: its role prompt, the rules it
must follow, reusable skills, event hooks, and the auto-ping trigger config.

It is loaded on `make start`: `scripts/start.sh` tells the freshly launched
agent to read `agent-prompt.md` **and every rule in `rules/`**, then follow them.

## Layout

```
tmux-agents/
├── agent-prompt.md      # the agent's role + how it drives `term` (kickoff)
├── ping-trigger.regex   # regex that decides what auto-pings the agent
├── term.bashrc          # term-only bash rc (aliases, make test); loaded on start
├── term.bashrc.example  # template for other projects
├── rules/               # behavioral rules the agent must follow (loaded on start)
│   ├── capabilities-location.md          # where new capabilities go (this policy)
│   ├── keep-guide-in-sync.md             # keep GUIDE.md/README.md in sync with usage
│   ├── ping-poke-behavior.md             # what to do on exactly `ping`
│   ├── lightweight-connectivity-checks.md # short ack for live probes
│   ├── know-where-term-is.md             # shell vs REPL vs pager before send
│   ├── no-system-exit.md                 # never exit the REPL from send.sh code
│   ├── repl-exec-for-multi-block-python.md  # exec() + log-snippet for REPL scripts
│   ├── session-workdir.md                # term+agent share SESSION_CWD; toolkit paths
│   ├── project-tmux-agents-overlay.md    # load project tmux-agents/ from SESSION_CWD
│   └── driving-rules.md                  # read-before-write, safety, one task at a time
├── skills/              # reusable task playbooks (<name>/SKILL.md) — generic only
└── hooks/               # scripts run on agent events
```

## Adding a capability

See [`rules/capabilities-location.md`](rules/capabilities-location.md). In short:
put it in the matching subfolder here (not in `.cursor/` or the repo root). New
rules take effect on the next `make start`; reference new skills/hooks from
`agent-prompt.md` so the agent discovers them.

> `.cursor/` in this repo is for Cursor-IDE-native skills auto-discovered for the
> human developer — a different audience. Capabilities for **this tmux agent**
> live here.
