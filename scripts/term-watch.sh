#!/usr/bin/env bash
# Host-side watcher for the `term` session, fed by `tmux pipe-pane`. Because it
# consumes the pane's output stream (not the shell's history/hooks), it is
# completely shell-agnostic: it works whether `term` runs bash, an interactive
# python shell, IPython, or anything else. Nothing shell-specific is ever
# injected into `term`.
#
# It does two things per line shown in `term`:
#   1. appends a cleaned (ANSI-stripped) copy to the session log, and
#   2. if the line matches the trigger regex, pings the agent session.
#
# Invoked by start.sh as the pipe-pane target:
#   tmux pipe-pane -o -t term "... exec term-watch.sh <logfile>"
#
# Configuration comes from the environment (set inline by start.sh):
#   AGENT_SESSION, TERM_SESSION, AGENT_SUBMIT_DELAY, AGENT_AUTOPING,
#   COMMENT_PREFIX, PING_TRIGGER_FILE, PING_ACK, PING_ACK_MS
set -o nounset

LOG="${1:-/dev/null}"

: "${AGENT_SESSION:=agent}"
: "${TERM_SESSION:=term}"
: "${AGENT_SUBMIT_DELAY:=1}"
: "${AGENT_AUTOPING:=1}"
: "${COMMENT_PREFIX:=#}"
: "${SEND_MARKER:=: AT:}"
: "${SEND_MARKER_REPL:=# AT:}"
: "${PING_TRIGGER_FILE:=}"
: "${PING_ACK:=1}"
: "${PING_ACK_MS:=3000}"
# Minimum seconds between two auto-pings. MUST exceed AGENT_SUBMIT_DELAY so a
# ping is fully submitted (Enter delivered) before another can be typed;
# otherwise rapid matches (e.g. IPython prompt redraws) concatenate the typed
# text into "pingping". Default derives from the submit delay.
: "${PING_MIN_INTERVAL:=}"
if [ -z "$PING_MIN_INTERVAL" ]; then
    PING_MIN_INTERVAL=$(( AGENT_SUBMIT_DELAY + 2 ))
fi

# Trigger regex: resolved by the shared loader (first non-'##', non-blank line of
# PING_TRIGGER_FILE, else a prompt-agnostic default). Sourcing this file only
# defines a function -- no set -e -- so the read loop below is unaffected.
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_HERE/_ping_regex.sh"
regex="$(load_ping_regex "$COMMENT_PREFIX" "$PING_TRIGGER_FILE")"

# Remove terminal escape sequences (colors, bracketed-paste, titles) and CRs so
# matching and the log are clean.
strip_ansi() {
    sed -E $'s/\x1b\\][^\x07]*\x07//g; s/\x1b\\[[0-9;?]*[A-Za-z]//g; s/\x1b[()][A-Za-z0-9]//g; s/\x1b//g; s/\r//g'
}

# After stripping send.sh marker blocks, return non-empty human comment text (or
# empty when only prompt residue remains).
human_comment_remainder() {
    local probe="$1"
    probe="$(printf '%s' "$probe" | sed -E 's/^.*[^[:alnum:][:space:]][[:space:]]+//')"
    probe="$(printf '%s' "$probe" | sed -E "s/^${COMMENT_PREFIX}[[:space:]]*//")"
    probe="$(printf '%s' "$probe" | sed 's/[[:space:]]//g')"
    printf '%s' "$probe"
}

PING_DEFER_LOCK="${TMPDIR:-/tmp}/agentic_terminal_${AGENT_SESSION}_ping_defer.lock"
# Max half-second polls while waiting for the agent CLI to become idle.
: "${PING_DEFER_MAX:=240}"

ping_agent() {
    # Coalesce: one deferred delivery picks up all pending comments.
    if [ -f "$PING_DEFER_LOCK" ]; then
        local old_pid
        old_pid="$(cat "$PING_DEFER_LOCK" 2>/dev/null)" || true
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            ping_ack_term queued
            return 0
        fi
        rm -f "$PING_DEFER_LOCK"
    fi

    local busy_at_start=0
    agent_appears_busy && busy_at_start=1

    local ping_pid
    (
        local waited=0
        while agent_appears_busy && [ "$waited" -lt "$PING_DEFER_MAX" ]; do
            sleep 0.5
            waited=$((waited + 1))
        done
        # Drop stale partial input (e.g. a previous "ping" that never submitted).
        tmux send-keys -t "$AGENT_SESSION" C-u 2>/dev/null || true
        tmux send-keys -t "$AGENT_SESSION" -l "ping" 2>/dev/null || exit 0
        sleep "$AGENT_SUBMIT_DELAY"
        tmux send-keys -t "$AGENT_SESSION" Enter 2>/dev/null
    ) &
    ping_pid=$!
    printf '%s' "$ping_pid" > "$PING_DEFER_LOCK"
    (
        wait "$ping_pid" 2>/dev/null || true
        rm -f "$PING_DEFER_LOCK"
    ) &

    if [ "$busy_at_start" = "1" ]; then
        ping_ack_term queued
    else
        ping_ack_term
    fi
}

# Flash a tmux status line in `term` when a ping is dispatched (does not inject
# shell input, so it cannot re-trigger auto-ping).
ping_ack_term() {
    [ "${PING_ACK:-1}" = "1" ] || return 0
    tmux has-session -t "$TERM_SESSION" 2>/dev/null || return 0
    local mode="${1:-}"
    local msg="Auto-ping sent to agent"
    if ! tmux has-session -t "$AGENT_SESSION" 2>/dev/null; then
        msg="Auto-ping failed: agent session '$AGENT_SESSION' missing"
    elif [ "$mode" = "queued" ]; then
        msg="Auto-ping queued — agent busy; will send when idle"
    fi
    tmux display-message -d "${PING_ACK_MS:-3000}" -t "$TERM_SESSION" "$msg" 2>/dev/null || true
}

# Best-effort: is the agent CLI mid-task (not idle at a prompt)?
agent_appears_busy() {
    local tail
    tail="$(tmux capture-pane -pt "$AGENT_SESSION" -S -12 2>/dev/null | strip_ansi | tail -8)" || return 1
    printf '%s' "$tail" | grep -qE '(Thinking|Running|Generating|⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏|\.\.\.$|…)' && return 0
    return 1
}

last_ping=""
last_ping_ts=0
while IFS= read -r raw; do
    line="$(printf '%s' "$raw" | strip_ansi)"
    printf '%s\n' "$line" >> "$LOG"

    [ "${AGENT_AUTOPING:-1}" = "1" ] || continue
    # Strip send.sh markers (SEND_MARKER up to the next '#') so the agent never
    # self-pings. Do not drop the whole line: an interactive REPL can redraw a
    # marker and a HUMAN comment onto one line, and that comment must still be
    # detected.
    probe="$(strip_send_markers "$line")"
    [ -z "$(human_comment_remainder "$probe")" ] && continue
    if printf '%s' "$probe" | grep -qE -- "$regex"; then
        # Debounce identical consecutive matches (e.g. pane redraws).
        [ "$probe" = "$last_ping" ] && continue
        # Rate-limit: never type a new ping before the previous one has been
        # submitted, or the texts merge into "pingping". A single ping already
        # makes the agent re-read ALL pending comments, so collapsing bursts is
        # correct, not lossy.
        if [ "$PING_MIN_INTERVAL" -gt 0 ] 2>/dev/null; then
            now="$(date +%s)"
            [ "$((now - last_ping_ts))" -lt "$PING_MIN_INTERVAL" ] && continue
            last_ping_ts="$now"
        fi
        last_ping="$probe"
        ping_agent
    fi
done
