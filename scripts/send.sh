#!/usr/bin/env bash
# Send a command (read from stdin) to the interactive `term` session and print
# its output. Blocks until the command finishes.
#
# SHELL-AGNOSTIC for the command itself: this does NOT wrap the command in any
# shell builtins. It only TYPES lines into term with `tmux send-keys`.
#
# Markers use SEND_MARKER (default `: AT:`) — a leading `:` is a no-op in
# bash/zsh and deliberately does NOT use COMMENT_PREFIX (`#`), so auto-ping
# never fires on the agent's own begin/done lines. term-watch.sh and
# requests.sh strip/ignore these markers.
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

# Identifier of the agent running this command (shown in the typed marker).
agent_id="${AGENT_SESSION_ID:-${CURSOR_CONVERSATION_ID:-}}"
if [ -z "$agent_id" ]; then
    agent_id="$(whoami)@$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo host)"
fi

# Keep run_id short so the marker line is unlikely to line-wrap in the pane.
run_id="$$${RANDOM}"

# Pick a marker prefix valid for the active interpreter (: no-op in bash/zsh;
# # comment in Python/IPython). Auto-ping strips both forms before matching.
pick_send_marker() {
    if term_is_repl_hash_comment; then
        printf '%s' "${SEND_MARKER_REPL:-# AT:}"
    else
        printf '%s' "${SEND_MARKER:-: AT:}"
    fi
}
marker="$(pick_send_marker)"
begin="${marker} BEGIN ${run_id} session:[${agent_id}]"
done_marker="${marker} DONE ${run_id}"

# Type one line, then submit it with a separate Enter keystroke.
send_line() {
    tmux send-keys -t "$TERM_SESSION" -l "$1"
    tmux send-keys -t "$TERM_SESSION" Enter
}

# 1) Attribution + begin marker (a `:` no-op line in bash/zsh).
send_line "$begin"
# 2) The command itself, typed verbatim.
send_line "$cmd"
# 3) Done marker: only echoed once the command returns and the prompt is back.
send_line "$done_marker"

# Strip terminal escape sequences for clean matching and output.
strip_ansi() {
    sed -E $'s/\x1b\\][^\x07]*\x07//g; s/\x1b\\[[0-9;?]*[A-Za-z]//g; s/\x1b[()][A-Za-z0-9]//g; s/\x1b//g; s/\r//g'
}

# Poll the pane until the done marker appears, then print everything between the
# begin and done markers (the command echo and its output).
timeout="${AGENT_TIMEOUT:-120}"
deadline=$(( $(date +%s) + timeout ))
while :; do
    # -J joins wrapped lines so a long marker line is matched as one logical line.
    pane="$(tmux capture-pane -J -pt "$TERM_SESSION" -S -5000 2>/dev/null | strip_ansi || true)"
    if printf '%s\n' "$pane" | grep -qF "DONE ${run_id}"; then
        printf '%s\n' "$pane" | awk -v b="BEGIN ${run_id}" -v d="DONE ${run_id}" '
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
