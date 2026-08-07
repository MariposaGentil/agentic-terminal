#!/usr/bin/env bash
# Shared configuration and helpers for the agentic-terminal scripts/ toolkit.
#
# WIP: sourced by the other scripts; not meant to be run directly.
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load user/config defaults (AGENT_CMD, AGENT_SESSION, TERM_SESSION, ...).
# shellcheck source=/dev/null
source "$SCRIPT_DIR/config.sh"
# Shared trigger-regex resolver (also used by term-watch.sh).
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_ping_regex.sh"

# Tracks how many `# ...` comment requests in the `term` pane have already been
# handed to the agent, so a poke only surfaces new ones. Reset by start.sh.
COMMENT_STATE="${TMPDIR:-/tmp}/agentic_terminal_${TERM_SESSION}_last_comment"

require_tmux() {
    if ! command -v tmux >/dev/null 2>&1; then
        echo "[agentic-terminal] tmux is not installed. Install it with: sudo apt install tmux" >&2
        exit 1
    fi
}

require_term_session() {
    if ! tmux has-session -t "$TERM_SESSION" 2>/dev/null; then
        echo "[agentic-terminal] No tmux session '$TERM_SESSION'. Run start.sh first." >&2
        exit 1
    fi
}

# Absolute path to the configured ping-trigger regex file.
ping_trigger_path() {
    case "$PING_TRIGGER_FILE" in
        /*) printf '%s' "$PING_TRIGGER_FILE" ;;
        *)  printf '%s' "$REPO_ROOT/$PING_TRIGGER_FILE" ;;
    esac
}

# Is `term` currently being piped to a watcher? echoes 1 or 0.
term_is_piped() {
    tmux display-message -pt "$TERM_SESSION" -p '#{pane_pipe}' 2>/dev/null || echo 0
}

# Does the AGENT session (the ping target) exist? A missing agent session is a
# silent ping sink: the watcher stays healthy but send-keys goes nowhere.
agent_session_alive() {
    tmux has-session -t "$AGENT_SESSION" 2>/dev/null
}

# Self-test the detection+delivery path WITHOUT touching the live term/agent:
# feed a canonical comment through a throwaway watcher aimed at a scratch agent
# session and confirm it emits `ping`. Verifies the trigger regex + send path.
# Returns 0 = ping delivered, 1 = not delivered, 2 = could not run.
selftest_ping_path() {
    local scratch="agtping_selftest_$$_$RANDOM" out rc
    out="$(mktemp 2>/dev/null)" || return 2
    if ! tmux new-session -d -s "$scratch" "bash -c 'cat >> \"$out\"'" 2>/dev/null; then
        rm -f "$out"; return 2
    fi
    printf 'x$ # agentic selftest ping\n' | \
        AGENT_SESSION="$scratch" AGENT_SUBMIT_DELAY=0 AGENT_AUTOPING=1 PING_MIN_INTERVAL=0 \
        COMMENT_PREFIX="$COMMENT_PREFIX" PING_TRIGGER_FILE="$(ping_trigger_path)" \
        bash "$SCRIPT_DIR/term-watch.sh" /dev/null >/dev/null 2>&1 || true
    sleep 0.4
    grep -q 'ping' "$out" 2>/dev/null; rc=$?
    tmux kill-session -t "$scratch" 2>/dev/null || true
    rm -f "$out"
    return "$rc"
}

# PIDs of watcher processes for THIS agent/term pair (best-effort; may be empty).
watcher_pids() {
    pgrep -f "term-watch\.sh .*/${AGENT_SESSION}-${TERM_SESSION}-" 2>/dev/null || true
}

# (Re)attach the pipe-pane watcher to `term`. Replaces any existing pipe; uses
# `-o` (output only) so keystrokes are not duplicated in the transcript. Safe
# to call to REPAIR a broken/missing watcher. Starts a fresh transcript and
# repoints the stable <AGENT_SESSION>.current.log symlink.
# Sets globals WATCHER_LOG and WATCHER_LINK for the caller to report.
attach_watcher() {
    local logs_dir="$REPO_ROOT/$LOGS_DIR"
    mkdir -p "$logs_dir"
    local ping_file; ping_file="$(ping_trigger_path)"
    WATCHER_LOG="$logs_dir/${AGENT_SESSION}-${TERM_SESSION}-$(date +%Y%m%d-%H%M%S).log"
    WATCHER_LINK="$logs_dir/${AGENT_SESSION}.current.log"
    printf '=== agentic-terminal session %s :: agent=%s term=%s :: %s %s ===\n' \
        "$(basename "$WATCHER_LOG" .log)" "$AGENT_SESSION" "$TERM_SESSION" \
        "${1:-started}" "$(date)" >> "$WATCHER_LOG"
    ln -sfn "$(basename "$WATCHER_LOG")" "$WATCHER_LINK"
    # Idempotent (re)attach: NEVER use `pipe-pane -o` here -- with an existing
    # pipe `-o` TOGGLES IT OFF instead of replacing, so a reload of a healthy
    # watcher would silently kill auto-ping. Explicitly close any current pipe,
    # then open the new one so we always end up attached to the fresh watcher.
    tmux pipe-pane -t "$TERM_SESSION" 2>/dev/null || true
    tmux pipe-pane -t "$TERM_SESSION" \
        "AGENT_SESSION='$AGENT_SESSION' TERM_SESSION='$TERM_SESSION' AGENT_SUBMIT_DELAY='$AGENT_SUBMIT_DELAY' AGENT_AUTOPING='$AGENT_AUTOPING' COMMENT_PREFIX='$COMMENT_PREFIX' SEND_MARKER='$SEND_MARKER' SEND_MARKER_REPL='$SEND_MARKER_REPL' PING_TRIGGER_FILE='$ping_file' PING_MIN_INTERVAL='$PING_MIN_INTERVAL' PING_ACK='$PING_ACK' PING_ACK_MS='$PING_ACK_MS' exec '$SCRIPT_DIR/term-watch.sh' '$WATCHER_LOG'"
}

# Fingerprint of the agent pane's CURRENTLY VISIBLE screen (no scrollback, so
# stale status text from earlier in the turn can't leak in). Echoes a checksum;
# empty/missing pane yields a stable sentinel.
agent_screen_hash() {
    tmux capture-pane -pt "$AGENT_SESSION" 2>/dev/null | cksum 2>/dev/null || echo "gone"
}

# Wait for the agent to finish processing the initial prompt, then report how
# long it took. Completion is detected by pane STABILITY: once the agent is idle
# its TUI stops redrawing, so when the visible screen is byte-identical for
# AGENT_IDLE_STABLE consecutive seconds we call it done. Agent-CLI-agnostic and
# robust (no brittle status-text matching). Never blocks forever: gives up after
# $1 seconds (the agent keeps working regardless).
#   $1 = max seconds to wait (0/empty = skip)
wait_for_agent_prompt_done() {
    local timeout="${1:-0}" need="${AGENT_IDLE_STABLE:-4}"
    local start_ts now waited stable=0 prev="" cur
    [ "${timeout:-0}" -gt 0 ] 2>/dev/null || return 0
    echo "[agentic-terminal] Waiting for '$AGENT_SESSION' to finish the initial prompt (up to ${timeout}s; the agent keeps working if it takes longer)..."
    start_ts=$(date +%s)
    sleep 2   # grace so the agent has started working before we sample stability
    prev="$(agent_screen_hash)"
    while :; do
        now=$(date +%s); waited=$((now - start_ts))
        if [ "$waited" -ge "$timeout" ]; then
            [ -t 1 ] && printf '\r\033[K'
            printf "[agentic-terminal] Initial prompt still processing after %ds - continuing (watch it: tmux attach -t %s).\n" "$timeout" "$AGENT_SESSION"
            return 0
        fi
        cur="$(agent_screen_hash)"
        if [ "$cur" = "$prev" ]; then
            stable=$((stable + 1))
            if [ "$stable" -ge "$need" ]; then
                [ -t 1 ] && printf '\r\033[K'
                printf "[agentic-terminal] Initial prompt processed - '%s' has been idle for %ds (took ~%ds).\n" "$AGENT_SESSION" "$need" "$waited"
                return 0
            fi
        else
            stable=0   # screen changed -> still working
        fi
        prev="$cur"
        [ -t 1 ] && printf '\r[agentic-terminal] Agent processing the initial prompt... %ds (idle %ds/%ds)\033[K' "$waited" "$stable" "$need"
        sleep 1
    done
}

# Tell the human how to reach the detached `agent` session. Printed instead of
# taking over the terminal that ran start.
print_agent_attach_hint() {
    echo "[agentic-terminal] The agent is running DETACHED in tmux session '$AGENT_SESSION'."
    echo "[agentic-terminal] This terminal is untouched. To watch or drive the agent:"
    if [ -n "${TMUX:-}" ]; then
        echo "        tmux switch-client -t $AGENT_SESSION    # you are already inside tmux"
    else
        echo "        tmux attach -t $AGENT_SESSION"
    fi
    echo "    Leave it again with:  Ctrl-b  then  d"
    echo "[agentic-terminal] (Set AGENT_ATTACH=current to attach automatically instead.)"
}

# Prompt the human how to reach BOTH detached tmux sessions. `term` is normally
# opened for you in a new window (TERM_ATTACH=emulator); this also shows the
# manual command so you can reattach either session from anywhere.
print_session_attach_hints() {
    local attach="tmux attach -t" verb="attach"
    [ -n "${TMUX:-}" ] && { attach="tmux switch-client -t"; verb="switch to"; }
    echo "[agentic-terminal] Both sessions run DETACHED in tmux. To ${verb} them:"
    echo "        term  ->  ${attach} ${TERM_SESSION}"
    echo "        agent ->  ${attach} ${AGENT_SESSION}"
    echo "    Detach again with:  Ctrl-b  then  d"
}

# Print a short welcome banner in `term` (`:` lines — bash no-ops, not `#` prompts).
show_term_welcome() {
    _show_session_welcome "$TERM_SESSION" \
        ": ── agentic-terminal ─────────────────────────────" \
        ": You work here. The agent watches this session." \
        ": Detach (leave running):  Ctrl-b  then  d" \
        ": Reattach later:          tmux attach -t ${TERM_SESSION}" \
        ": ────────────────────────────────────────────────" \
        ""
}

# Print a short welcome banner in `agent` before the CLI starts (`:` no-ops).
show_agent_welcome() {
    _show_session_welcome "$AGENT_SESSION" \
        ": ── agentic-terminal ─────────────────────────────" \
        ": Agent session — watch or drive the CLI here." \
        ": Detach (leave running):  Ctrl-b  then  d" \
        ": Reattach later:          tmux attach -t ${AGENT_SESSION}" \
        ": ────────────────────────────────────────────────" \
        ""
}

_show_session_welcome() {
    local target="$1"
    shift
    local line
    for line in "$@"; do
        if [ -n "$line" ]; then
            tmux send-keys -t "$target" -l "$line"
        fi
        tmux send-keys -t "$target" Enter
    done
}
