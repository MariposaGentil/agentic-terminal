#!/usr/bin/env bash
# Print ALL comment-prompts typed by the human in `term` that have not been
# processed yet (in order), then mark them processed. Run this on a "poke".
#
# A request is a line typed at the shell prompt beginning with the configured
# COMMENT_PREFIX (default `#`). A shell comment is a no-op, so it is safe to
# type at the prompt purely as an instruction to the agent, e.g.:
#
#   erik@host:~/proj$ # run the test suite and summarize failures
#
# Processed state is tracked by a running count in COMMENT_STATE so repeated
# pokes never resurface the same comment.
#
# WIP: detection scrapes the pane and strips a best-effort prompt prefix.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_tmux
require_term_session

last=0
if [ -f "$COMMENT_STATE" ]; then
    last="$(cat "$COMMENT_STATE" 2>/dev/null || echo 0)"
fi

prefix="$COMMENT_PREFIX"

# Extract typed comment lines: strip an optional prompt prefix that ends in a
# SYMBOL (non-alnum, non-space: $, >, %, ], or a powerline glyph) + whitespace,
# then keep lines whose command starts with the comment prefix. Also match
# comments at the very start of a line. Symbol-anchoring is prompt-agnostic
# (works with themed/powerline prompts) while ignoring mid-output hashes.
mapfile -t comments < <(
    tmux capture-pane -pt "$TERM_SESSION" -S -5000 2>/dev/null \
        | sed -nE "s/^(.*[^[:alnum:][:space:]][[:space:]]+)?(${prefix}[[:space:]]?.*)$/\2/p" \
        | sed -E "s/^${prefix}[[:space:]]?//" \
        | grep -vE '^(AT#|AGENT CMD|--- )' || true
)

total="${#comments[@]}"
if [ "$total" -le "$last" ]; then
    echo "[agentic-terminal] No new comment requests."
    exit 0
fi

idx=0
for comment in "${comments[@]}"; do
    idx=$((idx + 1))
    if [ "$idx" -gt "$last" ]; then
        printf '[%d] %s\n' "$idx" "$comment"
    fi
done

printf '%s' "$total" > "$COMMENT_STATE"
