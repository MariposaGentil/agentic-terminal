# Rule: where tmux-agent capabilities live

**Scope:** the agentic-terminal repo, for the **tmux CLI agent** (the agent that
runs in the detached `agent` tmux session and drives `term`).

**Rule:** Every capability *for the tmux agent* — rules, skills, hooks, prompts,
and the auto-ping trigger config — MUST be created under **`tmux-agents/`**, in
the matching subfolder. Do **not** put tmux-agent capabilities in `.cursor/`, in
`AGENTS.md`, in the repo root, or scattered elsewhere.

## Where each thing goes

| Capability | Location |
|---|---|
| Agent role / kickoff instructions | `tmux-agents/agent-prompt.md` |
| Behavioral rules the agent must follow | `tmux-agents/rules/<name>.md` |
| Reusable skills (task playbooks) | `tmux-agents/skills/<name>/SKILL.md` |
| Event hooks (scripts run on agent events) | `tmux-agents/hooks/<name>` |
| Auto-ping trigger regex | `tmux-agents/ping-trigger.regex` |

Prefer kebab-case file/folder names. Keep each rule short and focused (one
concern per file), the same way this file is.

## Loaded on `make start`

`scripts/start.sh` hands the freshly launched agent a kickoff message
(`AGENT_BOOTSTRAP`) that tells it to read `tmux-agents/agent-prompt.md` **and
every file in `tmux-agents/rules/`**, then follow them (see `AGENT_PROMPT_FILE`
and `AGENT_RULES_DIR` in `scripts/config.sh`). So **any rule you drop in
`tmux-agents/rules/` is picked up on the next `make start`** — no wiring needed.
When you add a skill or hook, reference it from `agent-prompt.md` (or a rule) so
the agent knows it exists.

## Not to be confused with `.cursor/`

`.cursor/` in this repo holds skills that the **Cursor IDE / `cursor-agent`
auto-discovers** for the human developer (e.g. `.cursor/skills/review`). That is
a different audience and a different discovery mechanism. Capabilities meant for
**this project's tmux agent**, loaded explicitly on `make start`, belong in
`tmux-agents/` — not `.cursor/`.

## When adding or changing a capability

1. Put the file in the correct `tmux-agents/` subfolder (table above).
2. If it changes how a user or the agent interacts with the repo, also update
   `GUIDE.md` and `README.md` (see `keep-guide-in-sync.md`).
3. New rules need no code change to take effect — they load on the next
   `make start`. New skills/hooks should be referenced from `agent-prompt.md`.
