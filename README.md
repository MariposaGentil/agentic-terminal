# agentic-terminal

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

1. `start.sh` prunes week-old session logs, creates the `term` tmux session with a transcript log (`tmux pipe-pane`), opens `term` in a **new terminal window**, and attaches the terminal that ran it to the **`agent`** session.
2. It creates the `agent` tmux session, starts the configured agent, leaves it **detached**, and hands it a kickoff prompt pointing at [`.agents/agent-prompt.md`](.agents/agent-prompt.md) so it knows to drive `term`.
3. The agent reads the `term` pane (via `tmux capture-pane`) to consume input and output — `read.sh`.
4. The agent writes commands into `term` (via `tmux send-keys`) and captures their output — `send.sh`.
5. Comment lines in `term` are collected as prompts — `requests.sh` — and a host-side `pipe-pane` watcher auto-pings the agent when a line matches the trigger regex — `term-watch.sh`.

## The `scripts/` toolkit

The agent drives `term` through a small set of bash scripts in [`scripts/`](scripts). They mirror the tmux capture/send pattern and are safe to re-run.

| Script | Purpose | Usage |
|---|---|---|
| `setup.sh` | Verify prerequisites (`tmux`, agent, terminal), mark the toolkit executable, optionally install deps. | `scripts/setup.sh [--install-deps]` |
| `start.sh` | Create (or reuse) the `term` and `agent` tmux sessions; open `term` in the default terminal; start the agent detached. | `scripts/start.sh` |
| `send.sh` | Type a command (from stdin) into `term` using shell-agnostic `#AT#` comment markers, block until it finishes, and print the captured output. Works in bash, python, IPython, … | `echo 'ls -la' \| scripts/send.sh` |
| `read.sh` | Print a raw snapshot of the `term` pane (with scrollback) so the agent can catch up on state. | `scripts/read.sh [lines]` |
| `requests.sh` | Print all not-yet-processed comment-prompts typed in `term` (and mark them processed). Run on a "poke". | `scripts/requests.sh` |
| `stop.sh` | Kill both tmux sessions cleanly. | `scripts/stop.sh` |
| `term-watch.sh` | Host-side `pipe-pane` watcher: logs the transcript and auto-pings the agent on a trigger match. Shell-agnostic. | _(run by `start.sh`)_ |
| `config.sh` | Configuration (agent command, session names, comment prefix, terminal emulator). Sourced by the others. | — |
| `_common.sh` | Shared helpers (repo root, tmux guards, comment-state path). Sourced; not run directly. | — |

### Comment-as-prompt

Any line typed at the `term` prompt that starts with the comment prefix (default `#`) is a no-op in the shell but is treated as an instruction to the agent:

```
erik@host:~/proj$ # run the test suite and summarize the failures
```

By default this is **automatic**: `start.sh` attaches a host-side watcher to the `term` pane via `tmux pipe-pane` ([`scripts/term-watch.sh`](scripts/term-watch.sh)) so that whenever a line shown in `term` matches the trigger regex, it sends `ping` to the agent session for you (both sessions share one tmux server, so no linking is needed). Because it watches the pane's output rather than the shell, **nothing shell-specific is injected into `term`** — it works whether `term` runs bash, an interactive python shell, IPython, etc. Disable it with `AGENT_AUTOPING=0`.

The trigger is a configurable regex loaded from [`.agents/ping-trigger.regex`](.agents/ping-trigger.regex) (`PING_TRIGGER_FILE`) — the first non-`##`, non-blank line is used as a POSIX ERE and matched against the entered line. The default matches a `#` comment typed at **any** prompt — including themed/powerline prompts (it anchors to a prompt-ending symbol, not just `$`/`#`/`>`), while ignoring hashes in the middle of program output. The file also ships a stricter classic-prompt pattern and a commented IPython example (`^In \[[0-9]+\]:[[:space:]]*#`).

The canonical poke is the single word **`ping`** — receiving exactly `ping` makes the agent re-read `term`, scan the comment lines for new prompts, and refresh its status. On a poke it runs `requests.sh`, which returns every unprocessed `# ...` line in order and marks them handled so they aren't resurfaced. You can still `ping` (or send any message) manually.

## Quick start

```bash
# 1. Configure the agent to run (edit scripts/config.sh or export AGENT_CMD)
export AGENT_CMD=cursor-agent   # or: claude

# 2. Launch everything (verify environment, then start agent + terminal)
./run.sh                        # add --install-deps to auto-install tmux

# 3. From the agent, read/drive the term session
scripts/read.sh
echo 'pytest -q' | scripts/send.sh
scripts/requests.sh

# 4. Tear down when done
scripts/stop.sh
```

`run.sh` is the single entrypoint (it runs `setup.sh` then `start.sh`) and is
what you'd bind to your terminal keyboard shortcut. You can still call the
individual scripts below directly.

### Or use `make`

A [`Makefile`](Makefile) wraps everything. Run `make` (or `make help`) to list
targets:

```bash
make run                 # verify + launch (same as ./run.sh)
make setup               # or: make install-deps
make read LINES=500      # snapshot the term pane
make send CMD='pytest -q'
make requests
make stop
```

## Configuration

Configuration lives in [`scripts/config.sh`](scripts/config.sh). Every value can also be overridden via an environment variable:

| Variable | Default | Effect |
|---|---|---|
| `AGENT_CMD` | `cursor-agent` | CLI agent launched in the detached `agent` session (e.g. `claude`, `cursor-agent`, custom command). |
| `AGENT_MODEL` | `composer` | Model the agent CLI uses. When set, `start.sh` appends `--model <AGENT_MODEL>` to the launch command; leave empty to use the CLI's default. |
| `AGENT_SESSION` | `agent` | tmux session name for the agent. |
| `TERM_SESSION` | `term` | tmux session name for the interactive terminal. |
| `COMMENT_PREFIX` | `#` | Prefix that turns a typed line into a prompt. |
| `AGENT_AUTOPING` | `1` | Auto-poke the agent with `ping` when a comment is typed in `term` (`0` to disable). |
| `PING_TRIGGER_FILE` | `.agents/ping-trigger.regex` | File whose first non-`##` line is the regex that triggers an auto-ping. |
| `PING_MIN_INTERVAL` | _(auto: `AGENT_SUBMIT_DELAY`+2)_ | Minimum seconds between auto-pings. Bursts collapse to one ping; must exceed `AGENT_SUBMIT_DELAY` so pings aren't merged into `pingping`. |
| `TERM_ATTACH` | `emulator` | How `start.sh` shows `term`: `emulator` (open a new window) or `none`. |
| `AGENT_ATTACH` | `current` | How the launching terminal attaches to `agent`: `current` (attach in place) or `none`. |
| `TERMINAL_EMULATOR` | `x-terminal-emulator` | Terminal used to open the `term` window when `TERM_ATTACH=emulator`. |
| `AGENT_PROMPT_FILE` | `.agents/agent-prompt.md` | Instructions the agent reads on launch (its role + how to drive `term`). |
| `AGENT_PROMPT_MODE` | `send-keys` | How to deliver the kickoff to the agent: `send-keys` or `none`. |
| `AGENT_READY_WAIT` | `5` | Seconds to wait for the agent CLI to boot before sending the kickoff. |
| `AGENT_SUBMIT_DELAY` | `1` | Seconds between typing the kickoff and pressing Enter (so the TUI submits it). |
| `AGENT_BOOTSTRAP` | _(see config)_ | One-line kickoff typed into the agent, pointing it at `AGENT_PROMPT_FILE`. |
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
- [x] Connect the agent to `term` via a bootstrap prompt (`.agents/agent-prompt.md`)
- [ ] Robust output capture (replace pane scraping with `pipe-pane`/markers to a file)
- [ ] Wire up the system terminal keyboard shortcut to launch `run.sh`
- [ ] Cross-platform terminal-emulator detection
- [x] Auto-ping the agent when a `term` line matches the trigger regex (`term-watch.sh`, shell-agnostic)
- [x] Per-session transcript logging with weekly retention (`logs/`)
- [x] Readable logs (ANSI/control codes stripped from transcripts)
- [x] Test suite (`make test`) covering pings, comment prompts, and send/read

## License

TBD.
