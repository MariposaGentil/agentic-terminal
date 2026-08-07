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
#   AGENT_SESSION, AGENT_SUBMIT_DELAY, AGENT_AUTOPING, COMMENT_PREFIX,
#   PING_TRIGGER_FILE
set -o nounset

LOG="${1:-/dev/null}"

: "${AGENT_SESSION:=agent}"
: "${AGENT_SUBMIT_DELAY:=1}"
: "${AGENT_AUTOPING:=1}"
: "${COMMENT_PREFIX:=#}"
: "${PING_TRIGGER_FILE:=}"
# Minimum seconds between two auto-pings. MUST exceed AGENT_SUBMIT_DELAY so a
# ping is fully submitted (Enter delivered) before another can be typed;
# otherwise rapid matches (e.g. IPython prompt redraws) concatenate the typed
# text into "pingping". Default derives from the submit delay.
: "${PING_MIN_INTERVAL:=}"
if [ -z "$PING_MIN_INTERVAL" ]; then
    PING_MIN_INTERVAL=$(( AGENT_SUBMIT_DELAY + 2 ))
fi

# Trigger regex: first non-'##', non-blank line of PING_TRIGGER_FILE, else a
# prompt-agnostic default. A prompt ends in a SYMBOL (non-alnum, non-space: '$',
# '>', '%', ']', or a powerline glyph), so match COMMENT_PREFIX after such a
# symbol + space, or at line start. Works with themed/powerline prompts while
# ignoring mid-output hashes that follow a word.
regex="(^|[^[:alnum:][:space:]][[:space:]]+)${COMMENT_PREFIX}([[:space:]]|\$)"
if [ -n "${PING_TRIGGER_FILE:-}" ] && [ -f "$PING_TRIGGER_FILE" ]; then
    loaded="$(grep -vE '^[[:space:]]*(##|$)' "$PING_TRIGGER_FILE" 2>/dev/null | head -n1)"
    [ -n "$loaded" ] && regex="$loaded"
fi

# Remove terminal escape sequences (colors, bracketed-paste, titles) and CRs so
# matching and the log are clean.
strip_ansi() {
    sed -E $'s/\x1b\\][^\x07]*\x07//g; s/\x1b\\[[0-9;?]*[A-Za-z]//g; s/\x1b[()][A-Za-z0-9]//g; s/\x1b//g; s/\r//g'
}

ping_agent() {
    tmux send-keys -t "$AGENT_SESSION" -l "ping" 2>/dev/null || return 0
    ( sleep "$AGENT_SUBMIT_DELAY"; tmux send-keys -t "$AGENT_SESSION" Enter 2>/dev/null ) &
}

last_ping=""
last_ping_ts=0
while IFS= read -r raw; do
    line="$(printf '%s' "$raw" | strip_ansi)"
    printf '%s\n' "$line" >> "$LOG"

    [ "${AGENT_AUTOPING:-1}" = "1" ] || continue
    # Strip the agent's own send.sh markers (each '#AT#' up to the next '#') so a
    # marker never self-pings. We must NOT drop the whole line: an interactive
    # REPL (e.g. IPython) can redraw a marker and a HUMAN comment onto one line,
    # and that comment must still be detected. What remains is the probe.
    probe="$(printf '%s' "$line" | sed 's/#AT#[^#]*//g')"
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
