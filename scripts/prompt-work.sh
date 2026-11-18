#!/usr/bin/env bash
# Bookend a human `#` prompt with a single BEGIN/DONE pair in `term`.
#
# send.sh uses per-command SEND markers only; call this script once when you
# start working on a prompt and once when you finish — never per send.sh call.
#
# Usage:
#   scripts/prompt-work.sh begin
#   scripts/prompt-work.sh done
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_tmux
require_term_session

cmd="${1:-}"
case "$cmd" in
    begin|done) ;;
    *)
        echo "Usage: prompt-work.sh begin|done" >&2
        exit 1
        ;;
esac

marker="$(pick_send_marker)"
agent_id="$(agent_session_id)"

prompt_work_active() {
    [ -f "$PROMPT_WORK_STATE" ] && [ -s "$PROMPT_WORK_STATE" ]
}

if [ "$cmd" = begin ]; then
    if prompt_work_active; then
        exit 0
    fi
    run_id="$$${RANDOM}"
    printf '%s' "$run_id" >"$PROMPT_WORK_STATE"
    term_send_line "${marker} BEGIN ${run_id} session:[${agent_id}]"
    exit 0
fi

if ! prompt_work_active; then
    exit 0
fi
run_id="$(cat "$PROMPT_WORK_STATE" 2>/dev/null || true)"
rm -f "$PROMPT_WORK_STATE"
[ -n "$run_id" ] || exit 0
term_send_line "${marker} DONE ${run_id}"
