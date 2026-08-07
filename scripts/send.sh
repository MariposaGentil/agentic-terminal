#!/usr/bin/env bash
# Send a command (read from stdin) to the interactive `term` session and print
# its output. Blocks until the command finishes.
#
# SHELL-AGNOSTIC: this does NOT wrap the command in any shell builtins. It only
# TYPES lines into term with `tmux send-keys`, using COMMENT lines as markers.
# A line starting with '#' is a no-op in bash, python, IPython, etc., so the
# very same mechanism works across shells (no `printf`, no `{ ...; }`, no `$?`).
#
# Markers use the '#AT#' sentinel so the auto-ping watcher (term-watch.sh) and
# requests.sh ignore them — the agent never pings itself or treats its own
# commands as prompts. The agent identifier is typed as part of the marker.
#
# Because it stays shell-agnostic, it does NOT report a numeric exit code.
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
begin="#AT# BEGIN ${run_id} session:[${agent_id}]"
done_marker="#AT# DONE ${run_id}"

# Type one line, then submit it with a separate Enter keystroke.
send_line() {
    tmux send-keys -t "$TERM_SESSION" -l "$1"
    tmux send-keys -t "$TERM_SESSION" Enter
}

# 1) Attribution + begin marker (a comment: no-op in every shell).
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
