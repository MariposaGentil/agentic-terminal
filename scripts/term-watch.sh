#!/usr/bin/env bash
# Host-side watcher for the `term` session, fed by `tmux pipe-pane`. Because it
# consumes the pane's output stream (not the shell's history/hooks), it is
# completely shell-agnostic: it works whether `term` runs bash, an interactive
# python shell, IPython, or anything else. Nothing shell-specific is ever
# injected into `term`.
#
# It does two things per line shown in `term`:
#   1. appends a cleaned (ANSI-stripped) copy to the session log, and
#   2. when a fresh prompt appears after Enter, pings the agent if the committed
#      line's first non-whitespace character is COMMENT_PREFIX (default `#`).
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

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_HERE/_ping_regex.sh"
# shellcheck source=/dev/null
source "$_HERE/_agent_status.sh"

# Remove terminal escape sequences (colors, bracketed-paste, titles) and CRs so
# matching and the log are clean.
strip_ansi() {
    strip_ansi_status
}

# Distinguish a human prompt comment from inline/output hashes (e.g. print text
# containing "ninonano)  # erik@..." or "items # trailing"). Those can match
# the broad trigger regex but must not auto-ping or they flood/rate-limit real
# prompts — especially in a Python REPL where agent exec() output is common.
is_human_prompt_comment() {
    local line="$1"
    # Explicit REPL prompt comments (IPython / stdlib / continuation).
    if printf '%s' "$line" | grep -qE '^[[:space:]]*(In \[[0-9]+\]:|\.\.\.:|>>>)[[:space:]]*#'; then
        return 0
    fi
    if printf '%s' "$line" | grep -qE '[[:alnum:]_\)][[:space:]]+#'; then
        return 1
    fi
    return 0
}

# True when the pane line is an empty / fresh prompt (no command text yet). A new
# prompt after input means the previous buffer was committed with Enter — unlike
# a soft-wrap redraw mid-typing, which never emits a prompt-only line.
is_prompt_only_line() {
    local line="$1"
    line="${line%"${line##*[![:space:]]}"}"  # rtrim
    [ -z "$line" ] && return 0
    if printf '%s' "$line" | grep -qE '^[[:space:]]*(In \[[0-9]+\]:|>>>|\.\.\.:)[[:space:]]*$'; then
        return 0
    fi
    # Shell prompt ends in a classic prompt symbol with only spaces after it.
    printf '%s' "$line" | grep -qE '[]$#>%|][[:space:]]*$'
}

# After Enter, the committed command is the first line of the buffer (wrapped
# continuations follow on later lines). Ping only when that command's first
# non-whitespace character is COMMENT_PREFIX.
committed_buffer_is_comment() {
    local buf="$1" first probe
    [ -n "$buf" ] || return 1
    first="${buf%%$'\n'*}"
    probe="$(strip_send_markers "$first")"
    if ! is_human_prompt_comment "$probe"; then
        return 1
    fi
    probe="$(printf '%s' "$probe" | sed -E 's/^[[:space:]]*(In \[[0-9]+\]:|\.\.\.:|>>>)[[:space:]]*//')"
    # Do not put '#' in the prompt-char class: it is both a root prompt suffix and
    # COMMENT_PREFIX, so `user$ # comment` would strip through the comment hash.
    probe="$(printf '%s' "$probe" | sed -E 's/^.*[]$>%|][[:space:]]+//')"
    # Root-style prompt ending in '#' before the comment: host:path# # comment
    if printf '%s' "$probe" | grep -qE '^[^#]*#[[:space:]]+#'; then
        probe="$(printf '%s' "$probe" | sed -E 's/^.*[^#]#[[:space:]]+//')"
    fi
    probe="${probe#"${probe%%[![:space:]]*}"}"  # ltrim
    [ -n "$probe" ] || return 1
    [ "${probe:0:1}" = "$COMMENT_PREFIX" ]
}

# Max half-second polls while waiting for the agent CLI to become idle.
: "${PING_DEFER_MAX:=240}"

ping_agent() {
    local lock
    lock="$(agent_ping_defer_lock)"
    # Coalesce: one deferred delivery picks up all pending comments.
    if agent_ping_queued; then
        ping_ack_term queued
        return 0
    fi
    rm -f "$lock"

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
    printf '%s' "$ping_pid" > "$lock"
    (
        wait "$ping_pid" 2>/dev/null || true
        rm -f "$lock"
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

last_ping=""
last_ping_ts=0
input_buffer=""
while IFS= read -r raw; do
    line="$(printf '%s' "$raw" | strip_ansi)"
    printf '%s\n' "$line" >> "$LOG"

    if is_prompt_only_line "$line"; then
        if [ "${AGENT_AUTOPING:-1}" = "1" ] && committed_buffer_is_comment "$input_buffer"; then
            probe="$(strip_send_markers "${input_buffer%%$'\n'*}")"
            # Debounce identical consecutive matches (e.g. pane redraws).
            [ "$probe" = "$last_ping" ] && { input_buffer=""; continue; }
            # Rate-limit: never type a new ping before the previous one has been
            # submitted, or the texts merge into "pingping". A single ping already
            # makes the agent re-read ALL pending comments, so collapsing bursts is
            # correct, not lossy.
            if [ "$PING_MIN_INTERVAL" -gt 0 ] 2>/dev/null; then
                now="$(date +%s)"
                [ "$((now - last_ping_ts))" -lt "$PING_MIN_INTERVAL" ] && { input_buffer=""; continue; }
                last_ping_ts="$now"
            fi
            last_ping="$probe"
            ping_agent
        fi
        input_buffer=""
    else
        if [ -n "$input_buffer" ]; then
            input_buffer="${input_buffer}"$'\n'"${line}"
        else
            input_buffer="$line"
        fi
    fi
done
