# Rule: Keep GUIDE.md in sync with usage

**Scope:** the agentic-terminal repo.

**Rule:** Whenever the way a user interacts with this repo changes, update
[`GUIDE.md`](../../GUIDE.md) in the same change so the guide never drifts from
reality.

## When this rule applies

Treat any of the following as a "usage change" that requires a GUIDE.md update:

- A script in `scripts/` is added, removed, renamed, or has its CLI/behavior
  changed (`start.sh`, `send.sh`, `read.sh`, `requests.sh`, `stop.sh`,
  `watch.sh`, `term-watch.sh`, ...).
- The auto-ping behavior (`term-watch.sh` / `AGENT_AUTOPING` / `PING_MIN_INTERVAL`)
  or its trigger regex (`tmux-agents/ping-trigger.regex` / `PING_TRIGGER_FILE`)
  changes, or the watcher control/recovery flow (`watch.sh`
  `status`/`reload`/`selftest`/`stop`, `make watch-status` / `reload-watcher` /
  `ping-selftest` / `stop-watcher`, the shared trigger-regex loader
  `_ping_regex.sh`, `attach_watcher` in `_common.sh` (idempotent close-then-open,
  never `pipe-pane -o`), the `reload` verification / `selftest_ping_path`, or
  `start.sh`'s self-heal on reuse) changes.
- Session logging or retention (`LOGS_DIR`, `LOG_RETENTION_DAYS`, `logs/`,
  `.gitignore`) changes.
- A configuration value in `scripts/config.sh` changes (name, default, or
  meaning) — e.g. `AGENT_CMD`, `AGENT_SESSION`, `TERM_SESSION`,
  `COMMENT_PREFIX`, `SEND_MARKER`, `AGENT_AUTOPING`, `PING_TRIGGER_FILE`, `TERM_ATTACH`,
  `AGENT_ATTACH`, `TERMINAL_EMULATOR`, `AGENT_CAPS_DIR`, `AGENT_RULES_DIR`,
  `AGENT_PROMPT_FILE`, `AGENT_PROMPT_MODE`, `AGENT_READY_WAIT`,
  `AGENT_SUBMIT_DELAY`, `AGENT_BOOTSTRAP`, `LOGS_DIR`, `LOG_RETENTION_DAYS`,
  `AGENT_TIMEOUT`.
- The agent capabilities layout (`tmux-agents/` — `agent-prompt.md`, `rules/`,
  `skills/`, `hooks/`, `ping-trigger.regex`) or how they are loaded on start
  changes, including the agent's role/instructions in
  `tmux-agents/agent-prompt.md`, or how `start.sh` connects the agent to `term`.
- The comment-as-prompt / poke workflow changes.
- Prerequisites change (new/removed dependency or required tool).
- Any user-facing step order or command changes.
- A capability changes that the test suite (`tests/`, `make test`) should cover —
  update or add tests alongside the change.

## What to update

For each usage change, in the same commit/PR:

1. Update the matching **Step-by-step** step in `GUIDE.md`.
2. Update the corresponding entry in **"What each step does (technically)"** so
   the mechanics stay accurate.
3. Update the **Reference** table in `GUIDE.md` if a script's role changed.
4. Keep `README.md` consistent (config table, script table, roadmap) — the guide
   and README must not contradict each other.

## How to verify

- Re-read the changed step and confirm the commands shown actually work.
- Confirm every script referenced in `GUIDE.md` exists in `scripts/` and every
  config variable referenced exists in `scripts/config.sh`.
- If a step no longer applies, remove it rather than leaving stale instructions.

Do not consider a usage change complete until `GUIDE.md` reflects it.
