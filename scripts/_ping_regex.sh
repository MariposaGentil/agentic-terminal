#!/usr/bin/env bash
# Shared resolver for the auto-ping trigger regex. No side effects and no
# `set -e`, so it is safe to source from term-watch.sh (which must not abort its
# read loop) as well as from _common.sh / watch.sh.
#
# load_ping_regex [comment_prefix] [trigger_file]
#   Echoes the POSIX ERE used to decide whether a `term` line is a ping trigger.
#   Uses the first non-'##', non-blank line of trigger_file if present, else a
#   prompt-agnostic default that matches a comment_prefix typed at any prompt
#   (symbol + space + prefix, or start of line) but not a '#' following a word.
load_ping_regex() {
    local prefix="${1:-${COMMENT_PREFIX:-#}}"
    local file="${2:-${PING_TRIGGER_FILE:-}}"
    local regex="(^|[^[:alnum:][:space:]][[:space:]]+)${prefix}([[:space:]]|\$)"
    if [ -n "$file" ] && [ -f "$file" ]; then
        local loaded
        loaded="$(grep -vE '^[[:space:]]*(##|$)' "$file" 2>/dev/null | head -n1)"
        [ -n "$loaded" ] && regex="$loaded"
    fi
    printf '%s' "$regex"
}

# Strip send.sh begin/done markers from a pane line. Strips SEND_MARKER (`: AT:`)
# and SEND_MARKER_REPL (`# AT:`) up to the next `#` so a human comment merged
# onto the same line as a marker (e.g. IPython redraw) is still detected.
strip_send_markers() {
    local line="$1"
    local sm="${SEND_MARKER:-: AT:}"
    local smr="${SEND_MARKER_REPL:-# AT:}"
    local esc esr
    esc="$(printf '%s' "$sm" | sed 's/[][\\.*^$()+?{|]/\\&/g')"
    esr="$(printf '%s' "$smr" | sed 's/[][\\.*^$()+?{|]/\\&/g')"
    line="$(printf '%s' "$line" | sed -E "s/${esc} ?(BEGIN|DONE)[^#]*//g")"
    printf '%s' "$line" | sed -E "s/${esr} ?(BEGIN|DONE)[^#]*//g"
}
