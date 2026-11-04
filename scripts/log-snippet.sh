#!/usr/bin/env bash
# Append a copy-paste snippet to the current session transcript log — NOT to `term`.
#
# The human (or agent) can tail logs/agent.current.log and copy the block into the
# REPL without it being typed into `term` or firing auto-ping.
#
# Usage:
#   scripts/log-snippet.sh 'one line'
#   scripts/log-snippet.sh <<'PY'
#   profiles = qapi.setup.Profile.list_items(account["id"])
#   PY
#   scripts/log-snippet.sh --title "GVA icon check" <<'PY'
#   ...
#   PY
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

resolve_session_log() {
    local link="$REPO_ROOT/$LOGS_DIR/${AGENT_SESSION}.current.log"
    if [ ! -e "$link" ]; then
        return 1
    fi
    if [ -L "$link" ]; then
        local target
        target="$(readlink "$link")"
        case "$target" in
            /*) printf '%s' "$target" ;;
            *)  printf '%s' "$REPO_ROOT/$LOGS_DIR/$target" ;;
        esac
        return 0
    fi
    printf '%s' "$link"
}

title=""
if [ "${1:-}" = "--title" ]; then
    title="${2:-}"
    shift 2
fi

if [ "$#" -ge 1 ]; then
    body="$*"
else
    body="$(cat)"
fi

if [ -z "$body" ]; then
    exit 0
fi

log_file="$(resolve_session_log)" || {
    echo "[agentic-terminal] No session log (logs/${AGENT_SESSION}.current.log). Run start.sh first." >&2
    exit 1
}

{
    printf '\n'
    if [ -n "$title" ]; then
        printf '=== agentic-terminal copy-paste snippet :: %s :: %s ===\n' "$title" "$(date -Iseconds 2>/dev/null || date)"
    else
        printf '=== agentic-terminal copy-paste snippet :: %s ===\n' "$(date -Iseconds 2>/dev/null || date)"
    fi
    printf '(for the REPL in term — not executed; copy from here)\n\n'
    printf '%s\n' "$body"
    printf '\n=== end copy-paste snippet ===\n\n'
} >> "$log_file"

echo "[agentic-terminal] Snippet appended to $log_file"
