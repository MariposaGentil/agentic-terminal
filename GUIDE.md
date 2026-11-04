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
export AGENT_MODEL=opus       # model the agent uses (empty = CLI default)
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

From the directory you want `term` and `agent` to run in (often your project
repo; the toolkit itself can live elsewhere):

```bash
/path/to/agentic-terminal/scripts/start.sh   # or: make -C …/agentic-terminal start
# from a project repo:
cd /path/to/your-project && /path/to/agentic-terminal/scripts/atstart.sh
```

Both tmux sessions are created **detached** first, then start.sh kicks off the
agent and reports each step in the terminal you launched from:

```
[agentic-terminal] Step 1/3: initializing agent CLI 'cursor-agent' (waiting 4s for it to boot)...
[agentic-terminal] Step 2/3: loading initial prompt from 'tmux-agents/' (agent-prompt.md + N rule(s))...
[agentic-terminal] Step 3/3: waiting for the agent to be ready before opening 'term'...
[agentic-terminal] Waiting for 'agent' to finish the initial prompt (up to 90s; the agent keeps working if it takes longer)...
[agentic-terminal] Initial prompt processed - 'agent' has been idle for 4s (took ~23s).
```

There is **no fixed countdown**: start **blocks until the agent has finished
processing its initial prompt** (detected by watching the agent pane go idle),
and **only then opens `term` in a new terminal window** (where **you** work) — so
`term` never appears before the agent is ready.

By default (`AGENT_ATTACH=current`) the terminal you launched from is then
**attached to the `agent` session**, so you watch it boot live (the agent-ready
wait is skipped in this mode and `term` opens right away). Detach with
`Ctrl-b d`.

With `AGENT_ATTACH=none` both sessions stay **detached** and the terminal you
launched from is **left alone at its own prompt** — start.sh just tells you how
to reach **each** session:

```
[agentic-terminal] Agent is ready -- opening 'x-terminal-emulator' for 'term'...
[agentic-terminal] Both sessions run DETACHED in tmux. To attach them:
        term  ->  tmux attach -t term
        agent ->  tmux attach -t agent
    Detach again with:  Ctrl-b  then  d
```

Prefer to keep the launching terminal at its own shell? Set
`AGENT_ATTACH=none`. Other knobs: `AGENT_PROMPT_WAIT=0` (skip the wait and
open `term` immediately), `AGENT_READY_WAIT` (how long to let the CLI boot before
the kickoff), `TERM_ATTACH=none` (open term yourself).

The `term` window shows a persistent **status bar** with the agent's state
(`FREE` / `BUSY` / `WAIT` when a ping is queued / `OFF` if the agent session is
gone). It refreshes about once a second (`AGENT_STATUS_INTERVAL`). Disable with
`AGENT_STATUS_BAR=0`.

The kickoff message
**connects the agent to `term`**: it points the agent at
[`tmux-agents/agent-prompt.md`](tmux-agents/agent-prompt.md)
**and every rule in [`tmux-agents/rules/`](tmux-agents/README.md)** — the files
that define the agent's role, its rules, and the `scripts/` tools it uses. Edit
those to change how the agent behaves (a new rule dropped in `tmux-agents/rules/`
loads on the next start); set `AGENT_PROMPT_MODE=none` if you'd rather prompt the
agent yourself.

It also records a transcript of the session to
`logs/<agent>-<term>-<timestamp>.log` (every command and its output) and keeps a
stable `logs/<agent>.current.log` symlink pointing at the live one (so
`tail -f logs/agent.current.log` always follows the current session). Transcripts
older than a week are deleted. See "Session logs" in [`README.md`](README.md).

If you use **`cursor-agent`**, pre-approved tool patterns for this repo are in
[`.cursor/cli.json`](.cursor/cli.json). Cursor merges that file (from the git
root down) with `~/.cursor/cli-config.json` when the agent starts here, so
`scripts/read.sh`, `scripts/send.sh`, `make test`, and common repo edits survive
a fresh agent process after `make stop` / `make start` without clicking through
the allow list again.

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
  `tmux new-session -d -s "$TERM_SESSION" -c "$SESSION_CWD"` (`SESSION_CWD` =
  `$PWD` where start was invoked, unless overridden).
- **Attaches a pane watcher:** closes any existing pipe, then `tmux pipe-pane -t
  "$TERM_SESSION" "... exec scripts/term-watch.sh <logfile>"` (no `-o`, which
  would toggle an existing pipe *off*). The watcher receives everything shown in
  `term` (agent + user commands and their output), writes an ANSI-stripped
  transcript to `logs/<AGENT_SESSION>-<TERM_SESSION>-<timestamp>.log` (plus a
  `logs/<AGENT_SESSION>.current.log` symlink to the live one), and handles auto-ping
  (see step 7). Nothing shell-specific is injected into `term`.
- Resets the comment-tracking state file so old comments aren't replayed.
- Creates the agent session **detached**, running your agent:
  `tmux new-session -d -s "$AGENT_SESSION" -c "$SESSION_CWD" "$AGENT_CMD"`. When
  `AGENT_MODEL` is set it is appended as   `--model <AGENT_MODEL>`, and `AGENT_ARGS`
  (default `--auto-review`) is appended so the agent doesn't stop to ask you to
  approve each command (including the start-up `read.sh`/`requests.sh` calls).
  `--auto-review` auto-runs safe tool calls and prompts only for risky ones; use
  `AGENT_ARGS=--force --trust` to run everything with no prompts, or `AGENT_ARGS=`
  to require approvals. These take effect the next time the agent session is
  created (relaunch with `make start` after `make stop`).
- **Connects the agent to `term`** (reporting each step): **step 1/3** waits
  `AGENT_READY_WAIT` seconds (default 4) so the still-**detached** agent CLI can
  draw its TUI; **step 2/3** types `AGENT_BOOTSTRAP` into the agent session with
  `tmux send-keys -l` (literal), waits `AGENT_SUBMIT_DELAY` seconds, then sends
  `Enter` as a **separate** keystroke to submit it — sending text and Enter
  together often leaves the prompt typed but not submitted. That message tells
  the agent to read `AGENT_PROMPT_FILE`
  ([`tmux-agents/agent-prompt.md`](tmux-agents/agent-prompt.md) + `tmux-agents/rules/`) and start driving `term`
  via the toolkit. This is agent-CLI-agnostic — the kickoff is just typed into
  the interactive agent, which then reads the file itself. Set
  `AGENT_PROMPT_MODE=none` to skip it.
- **Blocks until the agent is ready (this is the only wait — there is no fixed
  countdown):** **step 3/3** calls `wait_for_agent_prompt_done` (in `_common.sh`),
  which watches the agent pane's **visible screen** and, once it stops changing
  for `AGENT_IDLE_STABLE` seconds (default 4), prints
  `Initial prompt processed - ... (took ~Ns)`. This stability check is
  agent-CLI-agnostic (no brittle status-text matching) and never blocks past
  `AGENT_PROMPT_WAIT` seconds (default 90; `0` skips the wait and opens `term`
  immediately). It is skipped when `AGENT_ATTACH=current` (the default — you
  watch it live) or when no kickoff was sent (reused agent /
  `AGENT_PROMPT_MODE=none`).
- **Opens `term` only once the agent is ready:** after the wait above, `term`
  opens in a new window when `TERM_ATTACH=emulator`
  (default) via `$TERMINAL_EMULATOR -e tmux attach -t "$TERM_SESSION"` (only when
  the session was just created); `TERM_ATTACH=none` just leaves it detached.
- **Attaches the launching terminal to the agent:** `print_session_attach_hints`
  (in `_common.sh`) prints `tmux attach -t "$TERM_SESSION"` **and**
  `tmux attach -t "$AGENT_SESSION"` (or `tmux switch-client` when you are already
  inside tmux) plus the `Ctrl-b d` reminder. With `AGENT_ATTACH=current`
  (default) start.sh then takes the terminal over with
  `exec tmux attach`/`switch-client` on the agent (without a TTY it just prints
  the command). `AGENT_ATTACH=none` returns to your shell instead.
- Re-running is safe: existing sessions are reused rather than duplicated (and
  the kickoff — and its ready-wait — only runs when the agent session is newly
  created).

### Step 5 — Working in `term`

Because your shell lives inside a tmux session, its full scrollback is
available to the agent. [`scripts/read.sh`](scripts/read.sh) snapshots it with
`tmux capture-pane -pt "$TERM_SESSION" -S -<lines>`, giving the agent your
inputs, the commands that ran, and their output as context.

**Term-only bash rc:** this repo ships
[`tmux-agents/term.bashrc`](tmux-agents/term.bashrc) (toolkit aliases and
`make test` for the agentic-terminal suite). On `make start`, `term` launches as
`bash --rcfile … -i` — aliases and functions exist only in that session. Other
projects: copy [`term.bashrc.example`](tmux-agents/term.bashrc.example) or add
`tmux-agents/term.bashrc` under the project repo (sourced as an overlay). Set
`TERM_BASHRC=none` to disable.

### Step 6 — Comment-as-prompt

A line beginning with `COMMENT_PREFIX` (default `#`) is a shell no-op, so it runs
safely but leaves a marker in the pane.
[`scripts/requests.sh`](scripts/requests.sh) scrapes the pane, strips the shell
prompt prefix, and extracts those comment lines as instructions.

### Step 7 — Poking / processing

The poke keyword is `ping`: receiving exactly `ping` tells the agent to run
`read.sh` + `requests.sh` and refresh its status rather than treat the word as a
task (defined in [`tmux-agents/agent-prompt.md`](tmux-agents/agent-prompt.md) and `tmux-agents/rules/`).

**Auto-ping.** When `AGENT_AUTOPING=1` (default), the pane watcher
[`scripts/term-watch.sh`](scripts/term-watch.sh) matches each (ANSI-stripped)
line shown in `term` against the **trigger regex**; on a match it runs
`tmux send-keys -t "$AGENT_SESSION" -l ping` followed by a separate `Enter`.
Because detection reads the pane output — not the shell's history/hooks — it is
**shell-agnostic** (bash, python, ipython, ...) and injects nothing into `term`.
Both sessions share one tmux server, so the watcher drives the agent directly;
no session linking required.

Before matching, the watcher strips the agent's own `send.sh` markers (`SEND_MARKER`,
default `: AT:`, up to the next `#`) from the line rather than discarding the
whole line. This keeps the agent from pinging itself while still detecting a
**human comment that an interactive REPL merged onto the same line as a marker**
(IPython redraws its prompt, so a marker and your next `# comment` can share one
streamed line — you should never have to type a comment twice). Markers
deliberately avoid `#` so they never match the auto-ping trigger regex.

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
([`tmux-agents/ping-trigger.regex`](tmux-agents/ping-trigger.regex)) — its first
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
[`scripts/send.sh`](scripts/send.sh), which types lines with `tmux send-keys`:

- types a `: AT:` marker line (bash/zsh no-op; not a `#` comment) carrying the
  agent identifier + a unique begin marker,
- types your command verbatim,
- types a `: AT:` done marker,
- polls `capture-pane -J` until the done marker appears, then prints everything
  between the two markers (the command echo and its output).

Using `: AT:` markers (instead of `#` comments or shell builtins like `printf`/
`{ …; }`/`$?`) lets the agent tell *its* output apart from yours, know when a
command finished, and avoid tripping auto-ping. There is no numeric exit code.
The `SEND_MARKER` prefix is also what `term-watch.sh` and `requests.sh` use to
skip the agent's own lines.

### Step 8 — `scripts/stop.sh`

Sends `Ctrl-C` then `Ctrl-D` to each session so the agent CLI can exit cleanly,
kills both tmux sessions with `tmux kill-session`, and removes the
comment-tracking state file.

### Recovering auto-ping (`scripts/watch.sh`)

Auto-ping depends on the `tmux pipe-pane` watcher staying attached to `term`. If
it drops (the pipe gets toggled off, or the watcher process dies), `term` keeps
working but comments stop poking the agent. Since `start.sh` only wires the
watcher when it *creates* `term`, use `watch.sh` to inspect and repair a live
session — you can run it straight from the `term` window:

```bash
make watch-status     # HEALTHY or BROKEN? (pipe state, agent-session liveness, watcher PIDs, log age)
make reload-watcher   # re-attach the watcher AND verify the whole ping chain
make ping-selftest    # prove a '# comment' is detected and pings the agent (non-disruptive)
make stop-watcher     # detach it (auto-ping off)
```

`make reload-watcher` is the one-shot "fix + prove it" button. It:

1. **Idempotently re-attaches** the pipe — it first *closes* any existing pipe,
   then opens a fresh one with `-o` (output only), so reloading a **healthy**
   watcher can never toggle it off (an earlier bug called `pipe-pane -o` while a
   pipe was still open, which silently killed auto-ping). It also reaps stray
   watchers so exactly one runs,
   starts a fresh transcript, and repoints `logs/<agent>.current.log`.
2. **Verifies the full chain** and prints `[PASS]`/`[FAIL]` for each link: pipe
   attached, one watcher running, the **agent session alive** (a missing agent
   session is a silent ping sink — the watcher looks healthy but `send-keys` goes
   nowhere), and a **self-test** that runs a canonical `# comment` through a
   throwaway watcher aimed at a scratch session to confirm detection + delivery.

If everything passes it prints `auto-ping VERIFIED working` plus a reminder that
a prompt must be a **clean comment line** (`# do the thing`, with a space after
`#`) — a `#` glued onto a command (`ls# ...`) or inline in output (`code()  #
note`) is treated as program output and deliberately ignored (important in a
Python REPL where agent `print`/`exec` output is common). Re-running `make start`
also self-heals a broken watcher,
and a manual `ping` in the agent chat works even while the watcher is down.

---

## Reference

| Script | Role |
|---|---|
| `run.sh` | Entrypoint: verify environment, then launch (setup + start). |
| `scripts/setup.sh` | Verify prerequisites and make the toolkit executable. |
| `scripts/start.sh` | Create both sessions, prompt the detached agent, count down, then open `term` and print how to reach the agent (self-heals a broken watcher on reuse). |
| `scripts/send.sh` | Run a command in `term` and capture its output. |
| `scripts/say.sh` | Show a status line in `term` (never `#`; does not trigger auto-ping). |
| `scripts/log-snippet.sh` | Append copy-paste-ready text to `logs/agent.current.log` (not sent to `term`). |
| `scripts/read.sh` | Snapshot the `term` pane (context). |
| `scripts/requests.sh` | Collect unprocessed `#` comment-prompts. |
| `scripts/watch.sh` | Diagnose/repair+verify/self-test the pane watcher (`status`/`reload`/`selftest`/`stop`) when auto-ping breaks. |
| `scripts/term-watch.sh` | Pane watcher: logs the transcript and auto-pings the agent on a match. |
| `scripts/stop.sh` | Tear everything down. |
| `scripts/config.sh` | Configuration (agent, sessions, prefix, terminal). |
| `scripts/_common.sh` | Shared helpers (incl. `attach_watcher`). |

### Agent capabilities: `tmux-agents/`

The tmux agent's capabilities live in [`tmux-agents/`](tmux-agents/README.md):
`agent-prompt.md` (role), `rules/` (rules loaded + followed on start), `skills/`,
`hooks/`, and `ping-trigger.regex`. On `make start` the agent is told to read the
prompt **and every rule in `rules/`**, so adding a rule there needs no code
change. Put any new tmux-agent capability here (not in `.cursor/`, which is for
Cursor-IDE-native skills) — see
[`tmux-agents/rules/capabilities-location.md`](tmux-agents/rules/capabilities-location.md).

**Project repos** (e.g. qapi-client) can ship their own `tmux-agents/` for
domain rules. Start from that repo's directory (`atstart` or `make -C … run`) so
they load automatically (see `rules/project-tmux-agents-overlay.md`).

See [`README.md`](README.md) for the full configuration table and roadmap.
