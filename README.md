# agentic-terminal

[![Vibe Coded](https://img.shields.io/badge/Vibe-Coded-ff69b4?style=for-the-badge)](https://github.com/ai-ecoverse/vibe-coded-badge-action)

## What is this?

**Your terminal. Their eyes. One shared workspace.**

Most AI coding tools run in their own sandbox — you copy errors, paste context, and hope they see what you see. **agentic-terminal flips that:** a coding agent sits in a background [tmux](https://github.com/tmux/tmux) session and **watches, reads, and drives the same terminal you use**.

| Strength | What it means for you |
|---|---|
| **Live context, zero paste** | Every command, stack trace, and REPL prompt — the agent sees it as it happens. |
| **Comment to command** | Type `# fix the failing test` at any prompt; the agent picks it up and acts. |
| **Your shell, not theirs** | Bash, Python, IPython, ssh — works in whatever environment you're already in. |
| **Agent-agnostic** | Plug in [Cursor CLI](https://docs.cursor.com/en/cli/overview), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), or any agent you already run. |
| **Minimal glue** | Two tmux sessions, a handful of bash scripts — no new terminal app, no vendor lock-in. |

You keep working exactly where you always have. The agent keeps up.

> **Status: 🚧 WIP (Work In Progress)** — This project is under active development. Interfaces, configuration, and behavior are subject to change.

## What it does

When triggered (via your system's default terminal keyboard shortcut), `agentic-terminal` spins up a bash terminal that bootstraps **two [tmux](https://github.com/tmux/tmux) sessions**:

1. **`agent`** — Runs a CLI coding agent (e.g. [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Cursor CLI](https://docs.cursor.com/en/cli/overview), or another agent selected via config). This session is **automatically detached** after launch so it runs in the background.
2. **`term`** — A normal interactive terminal session (opened using the system's default "new terminal" shortcut, e.g. `Ctrl+Shift+T`). This is where you actually work.

The `agent` session then **connects to** the `term` session so it can:

- **Read** everything in `term` — both your input (commands) and the output they produce.
- **Write** commands into `term` when it needs to act.
- **Track status & context** by continuously observing the terminal's input/output stream.
- **React to comments**: when you write a comment in `term` (a shell comment line, e.g. `# refactor the auth module`), the agent picks it up and uses it as a **prompt** to continue the session.

In short: your terminal becomes the shared workspace, and the agent lives alongside you in it.

## How it works (planned architecture)

```
┌─────────────────────────────────────────────────────────┐
│ bash terminal (system default shortcut)                  │
│                                                          │
│   tmux session: "agent"   ◀── detached automatically     │
│   ┌────────────────────┐                                 │
│   │  claude-code /      │   reads I/O                     │
│   │  cursor-cli / ...   │ ───────────────┐                │
│   │  (from config)      │                │                │
│   └────────────────────┘                │                │
│            │ writes commands             ▼                │
│            │                    ┌────────────────────┐    │
│            └───────────────────▶│ tmux session: "term"│   │
│                                 │  interactive shell  │    │
│                                 │  (you work here)    │    │
│                                 └────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

1. `start.sh` prunes week-old session logs and creates the `term` tmux session with a transcript log (`tmux pipe-pane`).
2. It creates the `agent` tmux session, starts the configured agent, and hands it a kickoff prompt pointing at [`tmux-agents/agent-prompt.md`](tmux-agents/agent-prompt.md) **and every rule in `tmux-agents/rules/`** so it loads its capabilities and knows to drive `term`. There is **no fixed countdown**: start **blocks until the agent has finished processing its initial prompt** and only then opens `term` in a **new terminal window** — so `term` never appears before the agent is ready. The terminal that ran start is then **attached to the `agent` session** (`AGENT_ATTACH=none` keeps it at its own shell and just prints how to attach to either session).
3. The agent reads the `term` pane (via `tmux capture-pane`) to consume input and output — `read.sh`.
4. The agent writes commands into `term` (via `tmux send-keys`) and captures their output — `send.sh`.
5. Comment lines in `term` are collected as prompts — `requests.sh` — and a host-side `pipe-pane` watcher auto-pings the agent when a line matches the trigger regex — `term-watch.sh`.

## The `scripts/` toolkit

The agent drives `term` through a small set of bash scripts in [`scripts/`](scripts). They mirror the tmux capture/send pattern and are safe to re-run.

| Script | Purpose | Usage |
|---|---|---|
| `setup.sh` | Verify prerequisites (`tmux`, agent, terminal), mark the toolkit executable, optionally install deps. | `scripts/setup.sh [--install-deps]` |
| `start.sh` | Create (or reuse) the `term` and `agent` tmux sessions, prompt the detached agent, block until the agent is ready, then open `term` in the default terminal. Both sessions stay detached and the launching terminal is untouched (it just prints how to attach to each). | `scripts/start.sh` |
| `send.sh` | Type a command into `term` with per-command `: AT: SEND BEGIN/DONE` markers (not `#`), block until it finishes, and print the captured output. | `echo 'ls -la' \| scripts/send.sh` |
| `prompt-work.sh` | Once per human `#` task: type the single `AT: BEGIN … session:[…]` / `AT: DONE` pair in `term`. | `scripts/prompt-work.sh begin` … `done` |
| `say.sh` | Short step status in `term` via `echo`/`print` (no `#`, no SEND markers). | `scripts/say.sh 'Running tests...'` |
| `agent-status.sh` | Print agent busy/free/wait/offline for the `term` tmux status bar (`#(…)`). | `scripts/agent-status.sh` / `AGENT_STATUS_PLAIN=1 …` |
| `log-snippet.sh` | Append copy-paste-ready text to the session log (`logs/agent.current.log`); not sent to `term`. | `scripts/log-snippet.sh --title 'step 1' <<'PY'` … `PY` |
| `read.sh` | Print a raw snapshot of the `term` pane (with scrollback) so the agent can catch up on state. | `scripts/read.sh [lines]` |
| `requests.sh` | Print all not-yet-processed comment-prompts typed in `term` (and mark them processed). Run on a "poke". | `scripts/requests.sh` |
| `stop.sh` | Kill both tmux sessions cleanly. | `scripts/stop.sh` |
| `watch.sh` | Diagnose (`status`), repair + verify (`reload`), or self-test (`selftest`) the `term` watcher when auto-ping stops. Safe to run from the `term` window. | `scripts/watch.sh [status\|reload\|selftest\|stop]` |
| `term-watch.sh` | Host-side `pipe-pane` watcher: logs the transcript and auto-pings the agent on a trigger match. Shell-agnostic. | _(run by `start.sh`)_ |
| `config.sh` | Configuration (agent command, session names, comment prefix, terminal emulator). Sourced by the others. | — |
| `_common.sh` | Shared helpers (repo root, tmux guards, comment-state path). Sourced; not run directly. | — |

## Agent capabilities (`tmux-agents/`)

Everything that defines what the tmux agent knows and can do lives in
[`tmux-agents/`](tmux-agents/README.md) — its role prompt, rules, skills, hooks,
and the auto-ping trigger:

```
tmux-agents/
├── agent-prompt.md      # the agent's role + how it drives term (kickoff)
├── ping-trigger.regex   # regex that decides what auto-pings the agent
├── rules/               # rules the agent loads + follows on start
├── skills/              # reusable task playbooks (<name>/SKILL.md)
└── hooks/               # scripts run on agent events
```

On `make start`, `start.sh` tells the agent to read `agent-prompt.md` **and every
rule in `rules/`**, so a rule you drop there is picked up on the next start — no
wiring needed. New tmux-agent capabilities belong here (not in `.cursor/`, which
is for Cursor-IDE-native skills); see
[`tmux-agents/rules/capabilities-location.md`](tmux-agents/rules/capabilities-location.md).

### Comment-as-prompt

Any line typed at the `term` prompt that starts with the comment prefix (default `#`) is a no-op in the shell but is treated as an instruction to the agent:

```
erik@host:~/proj$ # run the test suite and summarize the failures
```

By default this is **automatic**: `start.sh` attaches a host-side watcher to the `term` pane via `tmux pipe-pane` ([`scripts/term-watch.sh`](scripts/term-watch.sh)) so that whenever a line shown in `term` matches the trigger regex, it sends `ping` to the agent session for you (both sessions share one tmux server, so no linking is needed). Because it watches the pane's output rather than the shell, **nothing shell-specific is injected into `term`** — it works whether `term` runs bash, an interactive python shell, IPython, etc. Disable it with `AGENT_AUTOPING=0`.

The trigger is a configurable regex loaded from [`tmux-agents/ping-trigger.regex`](tmux-agents/ping-trigger.regex) (`PING_TRIGGER_FILE`) — the first non-`##`, non-blank line is used as a POSIX ERE and matched against the entered line. The default matches a `#` comment typed at **any** prompt — including themed/powerline prompts (it anchors to a prompt-ending symbol, not just `$`/`#`/`>`), while ignoring hashes in the middle of program output. The file also ships a stricter classic-prompt pattern and a commented IPython example (`^In \[[0-9]+\]:[[:space:]]*#`).

The canonical poke is the single word **`ping`** — receiving exactly `ping` makes the agent re-read `term`, scan the comment lines for new prompts, and refresh its status. On a poke it runs `requests.sh`, which returns every unprocessed `# ...` line in order and marks them handled so they aren't resurfaced. You can still `ping` (or send any message) manually.

## Setup

Two `make` commands — that's the whole install and launch flow.

```bash
make install-deps   # once: install tmux, check your agent CLI is on PATH
make run            # every time: verify + launch agent + term
```

Optional: set your agent in [`scripts/config.sh`](scripts/config.sh) (default is `cursor-agent`) or `export AGENT_CMD=claude` before `make run`.

**Cursor CLI permissions:** when using `cursor-agent`, project-level allow rules live in [`.cursor/cli.json`](.cursor/cli.json). They merge with `~/.cursor/cli-config.json` for sessions started in this repo, so the tmux agent can run `scripts/*`, `make test`, and edit repo files without re-approving after each `make stop` / `make start`. Adjust the patterns there if your workflow needs more tools.

**What opens where**

| Session | Where | You |
|---|---|---|
| **`term`** | New terminal window | Work here — run commands, type `# ...` to prompt the agent |
| **`agent`** | Terminal that ran start (default) | Watch/drive the agent CLI here; detach with `Ctrl-b d` |

**Detach** (leave a session running in the background): press **`Ctrl-b`**, then **`d`**.

| Session | Reattach with |
|---|---|
| **`term`** | `tmux attach -t term` |
| **`agent`** | `tmux attach -t agent` |

**Stop everything:** `make stop`

From anywhere on your machine you can also run **`atstart`** (install:
`ln -sf "$(pwd)/scripts/atstart.sh" ~/bin/atstart`) — same as `make run`, but
**`term` and `agent` both open in your current directory** (`$PWD`).

### Other `make` targets

Run `make` or `make help` for the full list. Handy ones:

```bash
make read LINES=500      # snapshot the term pane
make send CMD='pytest -q'
make requests            # unprocessed # comment prompts
make test                # run the test suite
```

## Configuration

Configuration lives in [`scripts/config.sh`](scripts/config.sh). Every value can also be overridden via an environment variable:

| Variable | Default | Effect |
|---|---|---|
| `AGENT_CMD` | `cursor-agent` | CLI agent launched in the detached `agent` session (e.g. `claude`, `cursor-agent`, custom command). |
| `AGENT_MODEL` | `composer` | Model the agent CLI uses. When set, `start.sh` appends `--model <AGENT_MODEL>` to the launch command; leave empty to use the CLI's default. |
| `AGENT_ARGS` | `--auto-review` | Extra args appended at launch so the agent doesn't stop for per-command approval. `--auto-review` auto-runs safe tool calls and prompts only for risky ones. Use `--force --trust` to run everything with no prompts, `--dangerously-skip-permissions` for Claude Code, or empty to require approvals. |
| `AGENT_SESSION` | `agent` | tmux session name for the agent. |
| `TERM_SESSION` | `term` | tmux session name for the interactive terminal. |
| `SESSION_CWD` | _(invocation `$PWD`)_ | Initial working directory for **both** `term` and `agent` when sessions are first created. Set automatically by `make start` / `run.sh` / `atstart`. |
| `TERM_CWD` | _(same as `SESSION_CWD`)_ | Legacy alias for `SESSION_CWD`. |
| `AGENTIC_TERMINAL_ROOT` | _(set in tmux on start)_ | Path to this repo; use `$AGENTIC_TERMINAL_ROOT/scripts/*` from a project cwd. |
| `COMMENT_PREFIX` | `#` | Prefix that turns a typed line into a prompt. |
| `SEND_MARKER` | `: AT:` | Prefix send.sh uses for begin/done markers in bash/zsh (must not use `#` or auto-ping fires). |
| `SEND_MARKER_REPL` | `# AT:` | REPL variant for Python/IPython; stripped before auto-ping matching. |
| `AGENT_AUTOPING` | `1` | Auto-poke the agent with `ping` when a comment is typed in `term` (`0` to disable). |
| `PING_TRIGGER_FILE` | `tmux-agents/ping-trigger.regex` | File whose first non-`##` line is the regex that triggers an auto-ping. |
| `PING_MIN_INTERVAL` | _(auto: `AGENT_SUBMIT_DELAY`+2)_ | Minimum seconds between auto-pings. Bursts collapse to one ping; must exceed `AGENT_SUBMIT_DELAY` so pings aren't merged into `pingping`. |
| `AGENT_PROMPT_WAIT` | `90` | The blocking wait: max seconds `start.sh` waits for the agent to finish the initial prompt before opening `term` (reported when done; the agent keeps working regardless). Detected by pane stability. `0` skips the wait and opens `term` immediately. |
| `AGENT_IDLE_STABLE` | `4` | Seconds the agent pane must stay unchanged to be considered done processing the initial prompt. |
| `TERM_ATTACH` | `emulator` | How `start.sh` shows `term` once the agent is ready: `emulator` (open a new window) or `none`. |
| `AGENT_ATTACH` | `current` | What happens to the launching terminal: `current` (default — take the terminal over with `tmux attach`/`switch-client` on the agent) or `none` (agent stays detached, the terminal is left alone and start.sh prints how to attach). |
| `TERMINAL_EMULATOR` | `x-terminal-emulator` | Terminal used to open the `term` window when `TERM_ATTACH=emulator`. |
| `AGENT_CAPS_DIR` | `tmux-agents` | Home of the agent's capabilities (prompt, rules, skills, hooks, trigger regex). |
| `AGENT_RULES_DIR` | `tmux-agents/rules` | Rules the agent is told to read + follow on start (drop a file here to add one). |
| `AGENT_PROJECT_CAPS_DIR` | _(auto from `$SESSION_CWD/tmux-agents`)_ | Optional project overlay when sessions run in another repo (e.g. qapi-client). |
| `AGENT_PROMPT_FILE` | `tmux-agents/agent-prompt.md` | Instructions the agent reads on launch (its role + how to drive `term`). |
| `AGENT_PROMPT_MODE` | `send-keys` | How to deliver the kickoff to the agent: `send-keys` or `none`. |
| `AGENT_READY_WAIT` | `4` | Seconds to let the agent CLI boot (draw its TUI) before the kickoff is typed into the still-detached agent. Raise it if your CLI is slow to draw its TUI. |
| `AGENT_SUBMIT_DELAY` | `1` | Seconds between typing the kickoff and pressing Enter (so the TUI submits it). |
| `AGENT_BOOTSTRAP` | _(see config)_ | One-line kickoff typed into the agent, pointing it at `AGENT_PROMPT_FILE` + `AGENT_RULES_DIR`. |
| `LOGS_DIR` | `logs` | Directory (repo-relative) for per-session `term` transcripts. |
| `LOG_RETENTION_DAYS` | `7` | On start, session logs older than this many days are deleted. |
| `AGENT_TIMEOUT` | `120` | Seconds `send.sh` waits for a command to finish. |

## Session logs

Every `start.sh` (and therefore `make start` / `./run.sh`) records a transcript
of the `term` session — every command from the agent and the user, plus their
output — via `tmux pipe-pane`. Logs are written to `logs/` (configurable via
`LOGS_DIR`) as:

```
logs/<AGENT_SESSION>-<TERM_SESSION>-<YYYYmmdd-HHMMSS>.log   # timestamped history
logs/<AGENT_SESSION>.current.log                            # symlink -> the live one
```

The `<AGENT_SESSION>.current.log` symlink always points at the transcript of the
running session, so you never have to guess a timestamp — e.g. `tail -f
logs/agent.current.log`. (You can also read the log path straight from the
watcher: `pgrep -af scripts/term-watch.sh`.)

On each start, transcripts older than `LOG_RETENTION_DAYS` (default 7) are
pruned. The `logs/` directory is kept in git via `logs/.gitkeep`, but its
contents are ignored (see [`.gitignore`](.gitignore)). The watcher strips ANSI
escape/control codes, so transcripts are human-readable.

## Troubleshooting: auto-ping stopped

Auto-ping relies on a `tmux pipe-pane` watcher attached to `term`. If that pipe
is lost (e.g. it was toggled off, or the watcher process died), `term` keeps
working but comments no longer poke the agent. Because `start.sh` only wires the
watcher when it *creates* `term`, re-running it will **repair** a live session
but won't duplicate a healthy one. To diagnose and fix — you can run these right
from the `term` window:

```bash
make watch-status     # is the watcher HEALTHY or BROKEN? (also checks the agent session)
make reload-watcher   # re-attach it AND verify the whole ping chain ([PASS]/[FAIL])
make ping-selftest    # prove a '# comment' is detected and pings the agent
make stop-watcher     # detach it (turns auto-ping off)
```

`reload-watcher` is idempotent — it **closes any existing pipe before opening a
new one** (never `pipe-pane -o`, which would toggle a healthy pipe *off* and was
the root cause of "auto-ping breaks after a reload"), reaps stray watchers,
starts a fresh transcript, and repoints `logs/<agent>.current.log`. It then
verifies each link (pipe attached, one watcher, **agent session alive**, and a
detection+delivery self-test) so you know auto-ping actually works — not just
that the pipe is attached.
A manual `ping` in the agent chat also still works even while the watcher is
down (the agent reads the pane directly), and the agent will offer to reload the
watcher when it detects the pipe is broken.

## Testing

Run the suite with:

```bash
make test        # or: bash tests/run.sh
```

It covers the meaningful capabilities: config defaults, the auto-ping trigger
regex (including the IPython pattern, ANSI-stripping, and the enable/disable
toggle), comment-prompt collection (`requests.sh`), and — using a real tmux
server — the end-to-end auto-ping and `send.sh`/`read.sh` round-trip. The
tmux-based integration tests are skipped automatically if `tmux` is not
installed. See [`tests/`](tests).

## Requirements

- `bash`
- `tmux` (`sudo apt install tmux`)
- A CLI agent installed and on your `PATH` (e.g. `claude`, `cursor-agent`)

## Roadmap

- [x] Scaffolding for the `scripts/` toolkit
- [x] `setup.sh` — prerequisite checks and toolkit bootstrap
- [x] `run.sh` — single entrypoint (setup + start)
- [x] `Makefile` — `make` wrapper around the toolkit
- [x] `start.sh` — create both tmux sessions and open `term`
- [x] Auto-detach the `agent` session
- [x] Agent → terminal read (`read.sh`, `capture-pane`)
- [x] Agent → terminal write with output capture (`send.sh`, `send-keys`)
- [x] Comment-as-prompt collection (`requests.sh`)
- [x] Connect the agent to `term` via a bootstrap prompt (`tmux-agents/agent-prompt.md`)
- [x] Consolidate agent capabilities (rules/skills/hooks/prompt) under `tmux-agents/`, loaded on `make start`
- [ ] Robust output capture (replace pane scraping with `pipe-pane`/markers to a file)
- [ ] Wire up the system terminal keyboard shortcut to launch `run.sh`
- [ ] Cross-platform terminal-emulator detection
- [x] Auto-ping the agent when a `term` line matches the trigger regex (`term-watch.sh`, shell-agnostic)
- [x] Per-session transcript logging with weekly retention (`logs/`)
- [x] Readable logs (ANSI/control codes stripped from transcripts)
- [x] Test suite (`make test`) covering pings, comment prompts, and send/read

## License

TBD.
