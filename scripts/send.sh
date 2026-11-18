#!/usr/bin/env bash
# Send a command (read from stdin) to the interactive `term` session and print
# its output. Blocks until the command finishes.
#
# SHELL-AGNOSTIC for the command itself: this does NOT wrap the command in any
# shell builtins. It only TYPES lines into term with `tmux send-keys`.
#
# Per-command sync uses SEND BEGIN / SEND DONE (no session id). For one BEGIN/DONE
# pair per human prompt, use prompt-work.sh — see tmux-agents/rules/prompt-work-markers.md.
#
# Because it stays shell-agnostic for the command body, it does NOT report a
# numeric exit code.
#
# State persists: commands run in the same live shell/REPL, so variables, cwd,
# and imports set by one call are visible to the next.
#
# Usage:
#   echo 'ls -la' | send.sh
#   send.sh <<'SH'
#   cd src && ls
#   SH
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_tmux
require_term_session

cmd="$(cat)"

# Keep run_id short so the marker line is unlikely to line-wrap in the pane.
run_id="$$${RANDOM}"

marker="$(pick_send_marker)"
begin="${marker} SEND BEGIN ${run_id}"
done_marker="${marker} SEND DONE ${run_id}"

# 1) Per-command begin marker (a `:` no-op line in bash/zsh).
term_send_line "$begin"
# 2) The command itself, typed verbatim.
term_send_line "$cmd"
# 3) Done marker: only echoed once the command returns and the prompt is back.
term_send_line "$done_marker"

# Poll the pane until the done marker appears, then print everything between the
# begin and done markers (the command echo and its output).
timeout="${AGENT_TIMEOUT:-120}"
deadline=$(( $(date +%s) + timeout ))
while :; do
    # -J joins wrapped lines so a long marker line is matched as one logical line.
    pane="$(tmux capture-pane -J -pt "$TERM_SESSION" -S -5000 2>/dev/null | strip_ansi_pane || true)"
    if printf '%s\n' "$pane" | grep -qF "SEND DONE ${run_id}"; then
        printf '%s\n' "$pane" | awk -v b="SEND BEGIN ${run_id}" -v d="SEND DONE ${run_id}" '
            index($0, d) { inb = 0 }
            inb { print }
            index($0, b) { inb = 1 }
        '
        exit 0
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "[agentic-terminal] Timed out after ${timeout}s waiting for the command to finish. Inspect with read.sh." >&2
        exit 1
    fi
    sleep 0.3
done
