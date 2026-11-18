#!/usr/bin/env bash
# Emit a visible status line in `term` without triggering auto-ping.
#
# Uses `echo` in shell and `print()` in Python/IPython REPLs — never
# COMMENT_PREFIX (`#`), which the human uses for prompts and which fires
# auto-ping when it appears at a prompt.
#
# Does not use send.sh (no SEND markers) — pair with prompt-work.sh for
# prompt-level BEGIN/DONE once per human task.
#
# Usage:
#   scripts/say.sh 'Working on the test suite...'
#   printf '%s' 'Step 2 done.' | scripts/say.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_tmux
require_term_session

if [ "$#" -ge 1 ]; then
    msg="$*"
else
    msg="$(cat)"
fi
[ -n "$msg" ] || exit 0

term_send_line "$(term_say_command "$msg")"
wait_term_idle_prompt "${AGENT_SAY_TIMEOUT:-15}" || true
