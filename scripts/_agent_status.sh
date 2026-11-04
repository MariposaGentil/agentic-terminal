#!/usr/bin/env bash
# Shared agent busy/free helpers for the status bar and ping deferral.
#
# Safe to source from term-watch.sh (no `set -e` / errexit side effects).
# Depends only on: tmux on PATH, AGENT_SESSION (default: agent).

: "${AGENT_SESSION:=agent}"

# Remove terminal escape sequences and CRs (status / busy probes).
strip_ansi_status() {
    sed -E $'s/\x1b\\][^\x07]*\x07//g; s/\x1b\\[[0-9;?]*[A-Za-z]//g; s/\x1b[()][A-Za-z0-9]//g; s/\x1b//g; s/\r//g'
}

agent_ping_defer_lock() {
    printf '%s' "${TMPDIR:-/tmp}/agentic_terminal_${AGENT_SESSION}_ping_defer.lock"
}

# Best-effort: is the agent CLI mid-task (not idle at a prompt)?
agent_appears_busy() {
    local tail
    tail="$(tmux capture-pane -pt "$AGENT_SESSION" -S -12 2>/dev/null | strip_ansi_status | tail -8)" || return 1
    # Cursor Agent idle footer ("→ Add a follow-up") must not block auto-ping. While
    # executing, the footer shows braille spinners plus "Running … tokens"; require both.
    if printf '%s' "$tail" | grep -qE 'Running[[:space:]]+[0-9]'; then
        if printf '%s' "$tail" | grep -qE '⠘|⠆|⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏'; then
            return 0
        fi
    fi
    if printf '%s' "$tail" | grep -qE '(Thinking|Generating|Working)([[:space:]]|\.\.\.|…|$)'; then
        return 0
    fi
    if printf '%s' "$tail" | grep -qE '[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]'; then
        return 0
    fi
    if printf '%s' "$tail" | grep -qE '(\.\.\.|…)[[:space:]]*$'; then
        return 0
    fi
    return 1
}

# True when a deferred auto-ping is waiting to be delivered.
agent_ping_queued() {
    local lock pid
    lock="$(agent_ping_defer_lock)"
    [ -f "$lock" ] || return 1
    pid="$(cat "$lock" 2>/dev/null)" || return 1
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# Echo one of: busy | free | offline | queued
agent_status_state() {
    if ! tmux has-session -t "$AGENT_SESSION" 2>/dev/null; then
        printf '%s\n' offline
        return 0
    fi
    if agent_appears_busy; then
        printf '%s\n' busy
        return 0
    fi
    if agent_ping_queued; then
        printf '%s\n' queued
        return 0
    fi
    printf '%s\n' free
}

# tmux status-format fragment with colours (for status-right `#()`).
agent_status_tmux() {
    local state
    state="$(agent_status_state)"
    case "$state" in
        busy)
            printf 'agent #[fg=colour232,bg=colour214,bold] BUSY #[default]'
            ;;
        queued)
            printf 'agent #[fg=colour232,bg=colour178,bold] WAIT #[default]'
            ;;
        offline)
            printf 'agent #[fg=colour250,bg=colour240] OFF #[default]'
            ;;
        *)
            printf 'agent #[fg=colour232,bg=colour114,bold] FREE #[default]'
            ;;
    esac
}
