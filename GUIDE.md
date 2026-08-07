# agentic-terminal — User Guide

> **Status: 🚧 WIP** — see [`README.md`](README.md) for the project overview.

This guide walks you through using the repo end to end: launching the agent
alongside a live terminal, driving work by typing comments, and shutting down.
The [second section](#what-each-step-does-technically) explains what each step
does under the hood.

---

## TL;DR — one command

Once your agent is on your PATH, the whole flow (verify + launch) is a single
entrypoint you can bind to your terminal keyboard shortcut:

```bash
./run.sh                  # verify environment, then launch agent + terminal
./run.sh --install-deps   # also try to apt-install missing dependencies
./run.sh --no-setup       # skip checks, just launch
```

Prefer `make`? A [`Makefile`](Makefile) wraps the same commands — run `make`
(or `make help`) to list targets (`make run`, `make setup`, `make send CMD=...`,
`make read LINES=...`, `make requests`, `make stop`, `make test`).

The step-by-step below is the same flow, broken out.

---

## Step-by-step

### 1. Install the prerequisites

You need `tmux`, a CLI coding agent, and (optionally) a terminal emulator.

```bash
sudo apt install tmux            # if not already installed
# and make sure your agent CLI is on your PATH, e.g. `cursor-agent` or `claude`
```

### 2. Choose which agent to run

The agent that runs in the background is configured in
[`scripts/config.sh`](scripts/config.sh). Either edit that file or export the
variable for the current shell:

```bash
export AGENT_CMD=cursor-agent    # or: claude, or any custom command
export AGENT_MODEL=composer       # model the agent uses (empty = CLI default)
```

`AGENT_MODEL` defaults to `composer`. When set, `start.sh` appends
`--model <AGENT_MODEL>` to the launch command; clear it (`AGENT_MODEL=`) to use
the agent CLI's own default model.

### 3. Run setup

Verify prerequisites and make the toolkit executable:

```bash
scripts/setup.sh                 # check only
scripts/setup.sh --install-deps  # also try to apt-install missing deps
```

It reports the status of `tmux`, your configured agent, and the terminal
emulator, and tells you what to fix if anything is missing.

### 4. Start the session

From the repo root:

```bash
scripts/start.sh
```

By default this opens the **`term` session in a new terminal window** (where
**you** work), and **attaches the terminal that ran `start` to the `agent`
session** so you can watch/drive the agent right there (detach with `Ctrl-b d`).
The agent runs there but is otherwise headless — you interact with it by typing
comments in the `term` window. Prefer different placement? Set
`TERM_ATTACH=none` (open term yourself) or `AGENT_ATTACH=none`. It then
**connects the agent to `term`** by sending it a kickoff
message that points it at [`.agents/agent-prompt.md`](.agents/agent-prompt.md) —
the file that defines the agent's role and the `scripts/` tools it uses. Edit
that file to change how the agent behaves; set `AGENT_PROMPT_MODE=none` if you'd
rather prompt the agent yourself.

It also records a transcript of the session to
`logs/<agent>-<term>-<timestamp>.log` (every command and its output) and keeps a
stable `logs/<agent>.current.log` symlink pointing at the live one (so
`tail -f logs/agent.current.log` always follows the current session). Transcripts
older than a week are deleted. See "Session logs" in [`README.md`](README.md).

### 5. Work normally in the `term` window

Type and run commands as you always would. The agent can see everything in this
window — both what you type and the output it produces.

### 6. Ask the agent for something — type a comment

To hand the agent a task, type a shell comment (a line starting with `#`) at the
prompt and press Enter:

```
erik@host:~/proj$ # run the test suite and summarize the failures
```

The comment does nothing in the shell (it's a no-op), but it becomes a **prompt**
for the agent.

### 7. The agent picks up your request (auto-ping)

By default you don't have to do anything: the moment you enter a comment line,
`term` automatically sends `ping` to the agent, which re-reads `term`
(`read.sh`), scans the comment lines for new `#` prompts (`requests.sh`),
refreshes its status, and acts on anything pending.

If you set `AGENT_AUTOPING=0`, poke it manually instead by sending the single
word **`ping`** to the agent (any other message is treated as a task itself).

### 8. Stop when you're done

```bash
scripts/stop.sh
```

This shuts down both the `agent` and `term` sessions cleanly.

---

## What each step does (technically)

This section maps each user step above to the underlying mechanics implemented
in [`scripts/`](scripts).

### Entrypoint — `run.sh`

The TL;DR command is a thin orchestrator: it parses flags (`--install-deps`,
`--no-setup`), runs `scripts/setup.sh` (unless skipped), and then `exec`s
`scripts/start.sh`. It exists so a single command — steps 3 and 4 combined — can
be bound to a keyboard shortcut.

### Step 1 — Prerequisites

`tmux` is the backbone: both the agent and your terminal run as **tmux
sessions**, which lets a background process (`send.sh`/`read.sh`) attach to your
live shell and read/write it. The CLI agent is the process launched inside the
detached `agent` session.

### Step 2 — Agent selection

[`scripts/config.sh`](scripts/config.sh) defines defaults using the
`: "${VAR:=default}"` pattern, so any value can be overridden by an environment
variable. `AGENT_CMD` is the command executed inside the `agent` tmux session,
and `AGENT_MODEL` (default `composer`) is appended to it as
`--model <AGENT_MODEL>` by `start.sh` when set.
`_common.sh` sources this file so every script shares the same configuration.

### Step 3 — `scripts/setup.sh`

Sources `_common.sh` (so it sees your config), then verifies each prerequisite
with `command -v`: `tmux`, the first word of `AGENT_CMD`, and
`TERMINAL_EMULATOR`. It runs `chmod +x` on the toolkit and prints an
ok/warn/FAIL summary. With `--install-deps` it will `sudo apt-get install`
missing packages (currently `tmux`). It exits non-zero if a hard requirement
failed.

### Step 4 — `scripts/start.sh`

- **Prunes old logs:** deletes `logs/*.log` files older than
  `LOG_RETENTION_DAYS` (default 7) with `find ... -mtime +N -delete`.
- Creates the interactive session detached:
  `tmux new-session -d -s "$TERM_SESSION" -c "$REPO_ROOT"`.
- **Attaches a pane watcher:** `tmux pipe-pane -o -t "$TERM_SESSION" "... exec
  scripts/term-watch.sh <logfile>"`. The watcher receives everything shown in
  `term` (agent + user commands and their output), writes an ANSI-stripped
  transcript to `logs/<AGENT_SESSION>-<TERM_SESSION>-<timestamp>.log` (plus a
  `logs/<AGENT_SESSION>.current.log` symlink to the live one), and handles auto-ping
  (see step 7). Nothing shell-specific is injected into `term`.
- Resets the comment-tracking state file so old comments aren't replayed.
- Creates the agent session **detached**, running your agent:
  `tmux new-session -d -s "$AGENT_SESSION" -c "$REPO_ROOT" "$AGENT_CMD"`. When
  `AGENT_MODEL` is set (default `composer`), it is appended as
  `--model <AGENT_MODEL>`.
- **Connects the agent to `term`:** it **backgrounds** the kickoff (so it can
  attach to term immediately), waits `AGENT_READY_WAIT` seconds for the CLI to
  boot, types `AGENT_BOOTSTRAP` into the agent session with `tmux send-keys -l`
  (literal), waits `AGENT_SUBMIT_DELAY` seconds, then sends `Enter` as a
  **separate** keystroke to submit it — sending text and Enter
  together often leaves the prompt typed but not submitted. That message tells
  the agent to read `AGENT_PROMPT_FILE`
  ([`.agents/agent-prompt.md`](.agents/agent-prompt.md)) and start driving `term`
  via the toolkit. This is agent-CLI-agnostic — the kickoff is just typed into
  the interactive agent, which then reads the file itself. Set
  `AGENT_PROMPT_MODE=none` to skip it.
- **Shows the sessions:** `term` opens in a new window when `TERM_ATTACH=emulator`
  (default) via `$TERMINAL_EMULATOR -e tmux attach -t "$TERM_SESSION"` (only when
  the session was just created). The calling terminal then attaches to `agent`
  when `AGENT_ATTACH=current` (default): `exec tmux attach -t "$AGENT_SESSION"`
  — or `tmux switch-client` if already inside tmux. `none` on either just prints
  the attach command. The `exec` is why the kickoff is backgrounded above
  (backgrounded jobs survive the `exec`).
- Re-running is safe: existing sessions are reused rather than duplicated (and
  the kickoff is only sent when the agent session is newly created).

### Step 5 — Working in `term`

Because your shell lives inside a tmux session, its full scrollback is
available to the agent. [`scripts/read.sh`](scripts/read.sh) snapshots it with
`tmux capture-pane -pt "$TERM_SESSION" -S -<lines>`, giving the agent your
inputs, the commands that ran, and their output as context.

### Step 6 — Comment-as-prompt

A line beginning with `COMMENT_PREFIX` (default `#`) is a shell no-op, so it runs
safely but leaves a marker in the pane.
[`scripts/requests.sh`](scripts/requests.sh) scrapes the pane, strips the shell
prompt prefix, and extracts those comment lines as instructions.

### Step 7 — Poking / processing

The poke keyword is `ping`: receiving exactly `ping` tells the agent to run
`read.sh` + `requests.sh` and refresh its status rather than treat the word as a
task (defined in [`.agents/agent-prompt.md`](.agents/agent-prompt.md)).

**Auto-ping.** When `AGENT_AUTOPING=1` (default), the pane watcher
[`scripts/term-watch.sh`](scripts/term-watch.sh) matches each (ANSI-stripped)
line shown in `term` against the **trigger regex**; on a match it runs
`tmux send-keys -t "$AGENT_SESSION" -l ping` followed by a separate `Enter`.
Because detection reads the pane output — not the shell's history/hooks — it is
**shell-agnostic** (bash, python, ipython, ...) and injects nothing into `term`.
Both sessions share one tmux server, so the watcher drives the agent directly;
no session linking required.

Before matching, the watcher strips the agent's own `send.sh` markers (`#AT#` up
to the next `#`) from the line rather than discarding the whole line. This keeps
the agent from pinging itself while still detecting a **human comment that an
interactive REPL merged onto the same line as a marker** (IPython redraws its
prompt, so a marker and your next `# comment` can share one streamed line — you
should never have to type a comment twice).

Matches are de-duplicated (identical consecutive lines) **and rate-limited** by
`PING_MIN_INTERVAL` seconds (default `AGENT_SUBMIT_DELAY` + 2). The rate limit
must exceed `AGENT_SUBMIT_DELAY` because the `Enter` is sent a moment after the
`ping` text; without it, a burst of matches (e.g. an interactive REPL like
IPython redrawing its prompt, or the agent's own `send.sh` markers interleaving
with your typing) would type `ping` twice before the first `Enter` landed and the
agent would receive a single merged `pingping`. Collapsing a burst to one ping is
lossless: a single `ping` already makes the agent re-read **all** pending
comments via `requests.sh`.

The trigger regex is loaded from `PING_TRIGGER_FILE`
([`.agents/ping-trigger.regex`](.agents/ping-trigger.regex)) — its first
non-`##`, non-blank line, matched with `grep -E` (POSIX ERE). Since matching is
on the pane's visible output, patterns are prompt-anchored to avoid false pings.
The default is `(^|[^[:alnum:][:space:]][[:space:]]+)#([[:space:]]|$)` — a `#`
at line start or right after a prompt-ending **symbol** + space. A prompt ends in
a non-alphanumeric char (`$`, `>`, `%`, `]`, or a **powerline/themed glyph**), so
this is prompt-agnostic yet ignores mid-output hashes that follow a word (e.g.
`items # ...`). The file also ships a stricter `$`/`#`/`>`-only pattern and a
commented IPython example (`^In \[[0-9]+\]:[[:space:]]*#`). If the file is
missing/empty the watcher falls back to the same symbol-anchored `COMMENT_PREFIX`
match.

On a poke, `requests.sh` returns every **unprocessed** comment (in order) and
records how many it has handled in a state file
(`$TMPDIR/agentic_terminal_<term>_last_comment`), so the same comment is never
resurfaced. The agent turns each comment into work and runs it via
[`scripts/send.sh`](scripts/send.sh), which is **shell-agnostic** — it never
runs shell builtins in `term`, it only *types* lines with `tmux send-keys`:

- types a `#AT#` comment carrying the agent identifier + a unique begin marker,
- types your command verbatim,
- types a `#AT#` comment with a done marker (a comment is a no-op in bash,
  python, IPython, …, so nothing breaks in non-bash REPLs),
- polls `capture-pane -J` until the done marker appears, then prints everything
  between the two markers (the command echo and its output).

Using comment markers (instead of `printf`/`{ …; }`/`$?`) is what lets the agent
tell *its* output apart from yours and know when a command finished, while
working in any REPL. Because markers are plain comments, there is no numeric exit
code. The `#AT#` sentinel is also what `term-watch.sh` and `requests.sh` use to
skip the agent's own lines so it never pings itself.

### Step 8 — `scripts/stop.sh`

Sends `Ctrl-C` then `Ctrl-D` to each session so the agent CLI can exit cleanly,
kills both tmux sessions with `tmux kill-session`, and removes the
comment-tracking state file.

---

## Reference

| Script | Role |
|---|---|
| `run.sh` | Entrypoint: verify environment, then launch (setup + start). |
| `scripts/setup.sh` | Verify prerequisites and make the toolkit executable. |
| `scripts/start.sh` | Create both sessions, open `term`, start the agent detached. |
| `scripts/send.sh` | Run a command in `term` and capture its output. |
| `scripts/read.sh` | Snapshot the `term` pane (context). |
| `scripts/requests.sh` | Collect unprocessed `#` comment-prompts. |
| `scripts/term-watch.sh` | Pane watcher: logs the transcript and auto-pings the agent on a match. |
| `scripts/stop.sh` | Tear everything down. |
| `scripts/config.sh` | Configuration (agent, sessions, prefix, terminal). |
| `scripts/_common.sh` | Shared helpers. |

See [`README.md`](README.md) for the full configuration table and roadmap.
