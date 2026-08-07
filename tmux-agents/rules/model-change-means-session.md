# Rule: "change the model" means session model

When the human asks you to **change the model**, they mean the model of the
**current active agent session** — not the default in `scripts/config.sh`.

- The default (`AGENT_MODEL`) only affects newly launched sessions via
  `make start`.
- The running session's model is controlled by whatever the agent CLI supports
  (e.g. `/model <name>` in cursor-agent, or the model picker in the TUI).

If there is no way to change the model mid-session in your CLI, tell the human
they need to restart with `make stop && AGENT_MODEL=<model> make start`.

Only update `scripts/config.sh` when the human explicitly asks to change the
**default** model for future sessions.
