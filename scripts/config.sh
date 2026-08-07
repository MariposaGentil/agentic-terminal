#!/usr/bin/env bash
# agentic-terminal configuration.
#
# WIP: values here are the defaults used by the .agents/* scripts. Override any
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

# --- tmux sessions -----------------------------------------------------------
# Name of the detached session running the agent.
: "${AGENT_SESSION:=agent}"
# Name of the interactive terminal session the human works in.
: "${TERM_SESSION:=term}"

# --- Agent bootstrap ---------------------------------------------------------
# When the agent session starts, it needs to be told its role: that it drives
# the `term` session via the scripts/ toolkit. These control that hand-off.
#
# File (repo-relative) containing the agent's full role/instructions.
: "${AGENT_PROMPT_FILE:=.agents/agent-prompt.md}"
# How to deliver the kickoff message to the agent:
#   send-keys - type $AGENT_BOOTSTRAP into the agent session after it boots
#   none      - deliver nothing (you prompt the agent yourself)
: "${AGENT_PROMPT_MODE:=send-keys}"
# Seconds to wait for the agent CLI to be ready before sending the kickoff.
: "${AGENT_READY_WAIT:=5}"
# Seconds to wait after typing the kickoff text before pressing Enter. Many
# agent TUIs need the submit keystroke sent separately once the pasted text has
# settled, otherwise the prompt is typed but never submitted.
: "${AGENT_SUBMIT_DELAY:=1}"
# One-line kickoff typed into the agent; it points the agent at the prompt file.
: "${AGENT_BOOTSTRAP:=Read ${AGENT_PROMPT_FILE} and follow it. You are the agent driving the '${TERM_SESSION}' tmux session via the scripts/ toolkit. Start by running scripts/read.sh and scripts/requests.sh.}"

# --- Comment-as-prompt -------------------------------------------------------
# Lines typed in `term` starting with this prefix are treated as prompts for the
# agent (a shell comment is a no-op, so it is safe to type at the prompt).
: "${COMMENT_PREFIX:=#}"
# Auto-poke: automatically send `ping` to the agent when a line shown in `term`
# matches the trigger regex. Detection is done by a host-side tmux pipe-pane
# watcher (scripts/term-watch.sh), so it is shell-agnostic (bash, python,
# ipython, ...) and injects nothing into term. 1 = on, 0 = off.
: "${AGENT_AUTOPING:=1}"
# File (repo-relative) holding the regex that decides what triggers an auto-ping.
# The first non-'##', non-blank line is used as a POSIX ERE and matched against
# each (ANSI-stripped) line shown in `term`. Edit it to support other prompts
# (e.g. IPython's `In [n]: # ...`).
: "${PING_TRIGGER_FILE:=.agents/ping-trigger.regex}"
# Minimum seconds between two auto-pings. Bursts of matches (e.g. IPython prompt
# redraws) are collapsed to one ping. MUST be greater than AGENT_SUBMIT_DELAY so
# each ping is submitted before the next is typed (otherwise the agent receives
# a merged "pingping"). Empty = auto (AGENT_SUBMIT_DELAY + 2). One ping makes the
# agent re-read all pending comments, so collapsing bursts loses nothing.
: "${PING_MIN_INTERVAL:=}"

# --- Session logging ---------------------------------------------------------
# Directory (repo-relative) where per-session `term` transcripts are written.
# Each start creates a file named <TERM_SESSION>-<YYYYmmdd-HHMMSS>.log capturing
# every command (from the agent and the user) and its output.
: "${LOGS_DIR:=logs}"
# On start, session logs older than this many days are deleted.
: "${LOG_RETENTION_DAYS:=7}"

# --- Attaching to the sessions ----------------------------------------------
# Once both sessions are up, start.sh shows `term` in a NEW terminal window and
# attaches the CURRENT terminal (the one that ran start) to the `agent`.
#
# How to show the `term` session:
#   emulator - open TERMINAL_EMULATOR in a new window attached to term (default).
#   none     - don't open a window; just print the manual attach command.
: "${TERM_ATTACH:=emulator}"
# How the launching terminal attaches to the `agent` session:
#   current  - attach in the same terminal that ran start (default), so you
#              watch/drive the agent there. Uses tmux switch-client if already
#              inside tmux.
#   none     - don't attach; just print the manual attach command.
: "${AGENT_ATTACH:=current}"
# Used when TERM_ATTACH=emulator. On most Linux desktops `x-terminal-emulator`
# points at the user's default terminal. Invoked as:
#   $TERMINAL_EMULATOR -e tmux attach -t <TERM_SESSION>
: "${TERMINAL_EMULATOR:=x-terminal-emulator}"

export AGENT_CMD AGENT_MODEL AGENT_SESSION TERM_SESSION COMMENT_PREFIX AGENT_AUTOPING PING_TRIGGER_FILE PING_MIN_INTERVAL
export TERM_ATTACH AGENT_ATTACH TERMINAL_EMULATOR
export LOGS_DIR LOG_RETENTION_DAYS
export AGENT_PROMPT_FILE AGENT_PROMPT_MODE AGENT_READY_WAIT AGENT_SUBMIT_DELAY AGENT_BOOTSTRAP
