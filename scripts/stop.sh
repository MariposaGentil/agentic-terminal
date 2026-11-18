#!/usr/bin/env bash
# Tear down agentic-terminal: kill both tmux sessions. The agent session is
# stopped first (Ctrl-C then Ctrl-D so the CLI agent can exit cleanly), then the
# term session.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_tmux

for session in "$AGENT_SESSION" "$TERM_SESSION"; do
    if tmux has-session -t "$session" 2>/dev/null; then
        tmux send-keys -t "$session" C-c 2>/dev/null || true
        tmux send-keys -t "$session" C-d 2>/dev/null || true
        sleep 1
        tmux kill-session -t "$session" 2>/dev/null || true
        echo "[agentic-terminal] Stopped session '$session'."
    else
        echo "[agentic-terminal] No session '$session' to stop."
    fi
done

rm -f "$COMMENT_STATE" "$PROMPT_WORK_STATE"
