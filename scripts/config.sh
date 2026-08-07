#!/usr/bin/env bash
# agentic-terminal configuration.
#
# WIP: values here are the defaults used by the scripts/ toolkit. Override any
# of them by exporting the matching environment variable before calling a
# script, or by editing this file.

# --- Agent -------------------------------------------------------------------
# Command launched inside the detached `agent` tmux session. This is the CLI
# coding agent that will drive the `term` session. Examples:
#   claude            # Claude Code
#   cursor-agent      # Cursor CLI
#   any custom command on your PATH
: "${AGENT_CMD:=cursor-agent}"

# Model the agent CLI should use. When non-empty, start.sh appends it to the
# launch command as `--model <AGENT_MODEL>`. Leave empty to use the CLI's own
# default model. Example values: composer, sonnet, opus.
: "${AGENT_MODEL:=composer}"

# Extra arguments appended to AGENT_CMD at launch so the agent doesn't stop for
# per-command approval while driving `term` (including the start-up
# read.sh/requests.sh calls). Default is cursor-agent's Auto-review:
#   --auto-review  a server classifier auto-runs safe tool calls and prompts
#                  only for the risky ones (a safe middle ground).
# Other options: `--force`/`--yolo` (run everything, no prompts) + `--trust`
# (skip the workspace-trust prompt); for Claude Code use
# `--dangerously-skip-permissions`; set empty to require approvals for everything.
: "${AGENT_ARGS:=--auto-review}"

# --- tmux sessions -----------------------------------------------------------
# Name of the detached session running the agent.
: "${AGENT_SESSION:=agent}"
# Name of the interactive terminal session the human works in.
: "${TERM_SESSION:=term}"
# Initial working directory for `term` when start.sh creates the session.
# Defaults to the repo root when unset.
: "${TERM_CWD:=}"

# --- Agent capabilities ------------------------------------------------------
# Home of the tmux agent's capabilities (rules, skills, hooks, prompt, trigger).
# Everything the agent "knows" lives here and is loaded on start. See
# tmux-agents/rules/capabilities-location.md for the policy on what goes where.
: "${AGENT_CAPS_DIR:=tmux-agents}"
# Directory (repo-relative) of behavioral rules the agent must follow. On start,
# the agent is told to read agent-prompt.md AND every file in here, then obey
# them, so dropping a new rule file here takes effect on the next `make start`.
: "${AGENT_RULES_DIR:=${AGENT_CAPS_DIR}/rules}"

# --- Agent bootstrap ---------------------------------------------------------
# When the agent session starts, it needs to be told its role: that it drives
# the `term` session via the scripts/ toolkit. These control that hand-off.
#
# File (repo-relative) containing the agent's full role/instructions.
: "${AGENT_PROMPT_FILE:=${AGENT_CAPS_DIR}/agent-prompt.md}"
# How to deliver the kickoff message to the agent:
#   send-keys - type $AGENT_BOOTSTRAP into the agent session after it boots
#   none      - deliver nothing (you prompt the agent yourself)
: "${AGENT_PROMPT_MODE:=send-keys}"
# Seconds to let the agent CLI boot (draw its TUI) before the kickoff prompt is
# typed into it. The agent is still DETACHED at this point. Raise it if your
# agent CLI is slow to draw its TUI and swallows the typed prompt.
: "${AGENT_READY_WAIT:=4}"
# Seconds to wait after typing the kickoff text before pressing Enter. Many
# agent TUIs need the submit keystroke sent separately once the pasted text has
# settled, otherwise the prompt is typed but never submitted.
: "${AGENT_SUBMIT_DELAY:=1}"
# One-line kickoff typed into the agent; points it at the prompt file AND the
# rules directory so all capabilities load on start.
: "${AGENT_BOOTSTRAP:=Read ${AGENT_PROMPT_FILE} and every file in ${AGENT_RULES_DIR}/, then follow them. You are the agent driving the '${TERM_SESSION}' tmux session via the scripts/ toolkit. Start by running scripts/read.sh and scripts/requests.sh.}"

# --- Comment-as-prompt -------------------------------------------------------
# Lines typed in `term` starting with this prefix are treated as prompts for the
# agent (a shell comment is a no-op, so it is safe to type at the prompt).
: "${COMMENT_PREFIX:=#}"
# Prefix send.sh uses for begin/done markers typed into `term`. Must NOT start
# with COMMENT_PREFIX or auto-ping will fire on the agent's own lines. Leading
# `:` is a no-op in bash/zsh.
: "${SEND_MARKER:=: AT:}"
# Variant for Python/IPython REPLs where only `#` comments are no-ops. Uses the
# same ` AT:` tag so term-watch.sh can strip both forms before auto-ping matching.
: "${SEND_MARKER_REPL:=# AT:}"
# Auto-poke: automatically send `ping` to the agent when a line shown in `term`
# matches the trigger regex. Detection is done by a host-side tmux pipe-pane
# watcher (scripts/term-watch.sh), so it is shell-agnostic (bash, python,
# ipython, ...) and injects nothing into term. 1 = on, 0 = off.
: "${AGENT_AUTOPING:=1}"
# File (repo-relative) holding the regex that decides what triggers an auto-ping.
# The first non-'##', non-blank line is used as a POSIX ERE and matched against
# each (ANSI-stripped) line shown in `term`. Edit it to support other prompts
# (e.g. IPython's `In [n]: # ...`).
: "${PING_TRIGGER_FILE:=${AGENT_CAPS_DIR}/ping-trigger.regex}"
# Minimum seconds between two auto-pings. Bursts of matches (e.g. IPython prompt
# redraws) are collapsed to one ping. MUST be greater than AGENT_SUBMIT_DELAY so
# each ping is submitted before the next is typed (otherwise the agent receives
# a merged "pingping"). Empty = auto (AGENT_SUBMIT_DELAY + 2). One ping makes the
# agent re-read all pending comments, so collapsing bursts loses nothing.
: "${PING_MIN_INTERVAL:=}"

# --- Ping feedback -----------------------------------------------------------
# When auto-ping fires, flash a tmux status message in `term` so you know the
# poke was sent (especially when the agent is still busy on a prior task).
: "${PING_ACK:=1}"
# How long (ms) the status message stays visible in `term`.
: "${PING_ACK_MS:=3000}"

# --- Session logging ---------------------------------------------------------
# Directory (repo-relative) where per-session `term` transcripts are written.
# Each start creates a file named <TERM_SESSION>-<YYYYmmdd-HHMMSS>.log capturing
# every command (from the agent and the user) and its output.
: "${LOGS_DIR:=logs}"
# On start, session logs older than this many days are deleted.
: "${LOG_RETENTION_DAYS:=7}"

# --- Attaching to the sessions ----------------------------------------------
# There is no fixed countdown: start.sh kicks off the agent first and then BLOCKS
# until the agent has finished processing its initial prompt, and only THEN opens
# `term` in a NEW terminal window -- so `term` never appears before the agent is
# ready. Both sessions stay DETACHED and the terminal that ran start keeps its
# own shell; start.sh prints how to attach to either session.
#
# The blocking wait detects completion by watching the agent pane's VISIBLE
# screen and noticing when it stops changing (the TUI is static once the agent is
# idle) -- agent-CLI-agnostic, no brittle status-text matching. This is the max
# seconds to wait before giving up and opening `term` anyway (the agent keeps
# working regardless). Set 0 to skip the wait and open `term` immediately.
: "${AGENT_PROMPT_WAIT:=90}"
# Seconds the agent pane must stay UNCHANGED to be considered done processing.
# Higher = more certain (tolerates brief pauses mid-turn) but reports a little
# later; lower = snappier but may declare "done" during a long silent step.
: "${AGENT_IDLE_STABLE:=4}"
#
# How to show the `term` session:
#   emulator - open TERMINAL_EMULATOR in a new window attached to term (default).
#   none     - don't open a window; just print the manual attach command.
: "${TERM_ATTACH:=emulator}"
# How the launching terminal attaches to the `agent` session:
#   none     - don't attach (default). The agent runs detached and the terminal
#              that ran start is left alone at its own prompt; start.sh prints
#              the command to attach whenever you want to watch it.
#   current  - attach in the same terminal that ran start, taking it over. Uses
#              tmux switch-client if already inside tmux.
: "${AGENT_ATTACH:=none}"
# Used when TERM_ATTACH=emulator. On most Linux desktops `x-terminal-emulator`
# points at the user's default terminal. Invoked as:
#   $TERMINAL_EMULATOR -e tmux attach -t <TERM_SESSION>
: "${TERMINAL_EMULATOR:=x-terminal-emulator}"

export AGENT_CMD AGENT_MODEL AGENT_ARGS AGENT_SESSION TERM_SESSION TERM_CWD COMMENT_PREFIX SEND_MARKER SEND_MARKER_REPL AGENT_AUTOPING PING_TRIGGER_FILE PING_MIN_INTERVAL PING_ACK PING_ACK_MS
export TERM_ATTACH AGENT_ATTACH TERMINAL_EMULATOR AGENT_PROMPT_WAIT AGENT_IDLE_STABLE
export LOGS_DIR LOG_RETENTION_DAYS
export AGENT_CAPS_DIR AGENT_RULES_DIR
export AGENT_PROMPT_FILE AGENT_PROMPT_MODE AGENT_READY_WAIT AGENT_SUBMIT_DELAY AGENT_BOOTSTRAP
