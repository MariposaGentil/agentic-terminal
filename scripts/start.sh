#!/usr/bin/env bash
# Bootstrap agentic-terminal: create the two tmux sessions and wire them up.
#
#   1. `term`  - interactive shell the human works in. Opened in the system's
#                default terminal emulator (attached to the tmux session so the
#                agent can read/write it too).
#   2. `agent` - runs the configured CLI agent ($AGENT_CMD), started DETACHED so
#                it drives `term` in the background.
#
# start.sh reuses existing sessions if they are already running, so it is safe
# to call again.
#
# WIP: terminal-emulator detection is best-effort; adjust TERMINAL_EMULATOR in
# config.sh for your desktop.
#
# Usage:
#   start.sh            # uses AGENT_CMD from config.sh
#   AGENT_CMD=claude start.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_tmux

# --- session logs: prune old ones --------------------------------------------
logs_dir="$REPO_ROOT/$LOGS_DIR"
mkdir -p "$logs_dir"
if [ "${LOG_RETENTION_DAYS:-7}" -gt 0 ] 2>/dev/null; then
    deleted="$(find "$logs_dir" -type f -name '*.log' -mtime "+${LOG_RETENTION_DAYS}" -print -delete 2>/dev/null | wc -l)"
    if [ "${deleted:-0}" -gt 0 ]; then
        echo "[agentic-terminal] Pruned $deleted session log(s) older than ${LOG_RETENTION_DAYS} day(s)."
    fi
fi

# --- term session ------------------------------------------------------------
term_created=0
if tmux has-session -t "$TERM_SESSION" 2>/dev/null; then
    echo "[agentic-terminal] Session '$TERM_SESSION' already running. Reusing it."
else
    echo "[agentic-terminal] Creating interactive session '$TERM_SESSION'..."
    tmux new-session -d -s "$TERM_SESSION" -c "$REPO_ROOT"
    # Fresh term -> forget which comment requests were already processed.
    rm -f "$COMMENT_STATE"

    # Resolve the trigger-regex file to an absolute path for the watcher.
    case "$PING_TRIGGER_FILE" in
        /*) ping_file="$PING_TRIGGER_FILE" ;;
        *)  ping_file="$REPO_ROOT/$PING_TRIGGER_FILE" ;;
    esac

    # Attach a single host-side watcher to the term pane via tmux pipe-pane. It
    # logs a transcript AND auto-pings the agent on a trigger match. Because it
    # consumes the pane stream (not the shell), NOTHING shell-specific is
    # injected into term -- it works for bash, python, ipython, etc.
    #
    # Log name ties the transcript to the agent+term sessions; a stable
    # "<AGENT_SESSION>.current.log" symlink always points at the live one, so you
    # (or the agent) can find it without guessing timestamps.
    session_log="$logs_dir/${AGENT_SESSION}-${TERM_SESSION}-$(date +%Y%m%d-%H%M%S).log"
    current_link="$logs_dir/${AGENT_SESSION}.current.log"
    printf '=== agentic-terminal session %s :: agent=%s term=%s :: started %s ===\n' \
        "$(basename "$session_log" .log)" "$AGENT_SESSION" "$TERM_SESSION" "$(date)" >> "$session_log"
    ln -sfn "$(basename "$session_log")" "$current_link"
    tmux pipe-pane -o -t "$TERM_SESSION" \
        "AGENT_SESSION='$AGENT_SESSION' AGENT_SUBMIT_DELAY='$AGENT_SUBMIT_DELAY' AGENT_AUTOPING='$AGENT_AUTOPING' COMMENT_PREFIX='$COMMENT_PREFIX' PING_TRIGGER_FILE='$ping_file' PING_MIN_INTERVAL='$PING_MIN_INTERVAL' exec '$REPO_ROOT/scripts/term-watch.sh' '$session_log'"
    echo "[agentic-terminal] Logging session transcript to: $session_log"
    echo "[agentic-terminal] Stable pointer: $current_link"
    if [ "${AGENT_AUTOPING:-1}" = "1" ]; then
        echo "[agentic-terminal] Auto-ping enabled: matches in '$TERM_SESSION' will poke '$AGENT_SESSION' (regex file: $ping_file)."
    fi
    term_created=1
fi

# --- agent session (detached) ------------------------------------------------
if tmux has-session -t "$AGENT_SESSION" 2>/dev/null; then
    echo "[agentic-terminal] Session '$AGENT_SESSION' already running. Reusing it."
else
    # Append the configured model (if any) to the launch command.
    agent_cmd="$AGENT_CMD"
    if [ -n "${AGENT_MODEL:-}" ]; then
        agent_cmd="$AGENT_CMD --model $AGENT_MODEL"
    fi
    echo "[agentic-terminal] Starting agent session '$AGENT_SESSION' (detached): $agent_cmd"
    tmux new-session -d -s "$AGENT_SESSION" -c "$REPO_ROOT" "$agent_cmd"

    # Connect the agent to `term`: tell it its role by pointing it at the prompt
    # file. Delivered by typing into the (detached) agent session once the CLI
    # has had a moment to boot. Agent-CLI-agnostic: it just reads the file.
    if [ "$AGENT_PROMPT_MODE" = "send-keys" ]; then
        if [ ! -f "$REPO_ROOT/$AGENT_PROMPT_FILE" ]; then
            echo "[agentic-terminal] Warning: prompt file '$AGENT_PROMPT_FILE' not found; agent will start without instructions." >&2
        fi
        echo "[agentic-terminal] Sending the agent its instructions in the background (~${AGENT_READY_WAIT}s)..."
        # Deliver the kickoff in the background so we can attach to term now.
        # Type the kickoff text first, let the TUI settle, then submit with
        # Enter as a separate keystroke (sending them together often leaves the
        # prompt typed but not submitted). Survives the exec below.
        (
            sleep "$AGENT_READY_WAIT"
            tmux send-keys -t "$AGENT_SESSION" -l "$AGENT_BOOTSTRAP"
            sleep "$AGENT_SUBMIT_DELAY"
            tmux send-keys -t "$AGENT_SESSION" Enter
        ) >/dev/null 2>&1 &
    else
        echo "[agentic-terminal] AGENT_PROMPT_MODE=$AGENT_PROMPT_MODE; not sending a kickoff prompt."
    fi
fi

# --- show the sessions -------------------------------------------------------
# term -> a NEW terminal-emulator window. Only spawn one if we just created the
# session, to avoid duplicate windows when start is re-run.
case "$TERM_ATTACH" in
    emulator)
        if [ "$term_created" -eq 1 ]; then
            if command -v "${TERMINAL_EMULATOR%% *}" >/dev/null 2>&1; then
                echo "[agentic-terminal] Opening '$TERMINAL_EMULATOR' for '$TERM_SESSION'..."
                $TERMINAL_EMULATOR -e tmux attach -t "$TERM_SESSION" >/dev/null 2>&1 &
            else
                echo "[agentic-terminal] '$TERMINAL_EMULATOR' not found; open term yourself:"
                echo "    tmux attach -t $TERM_SESSION"
            fi
        fi
        ;;
    *)
        echo "[agentic-terminal] term window: tmux attach -t $TERM_SESSION"
        ;;
esac

# agent -> the terminal that ran start (this shell becomes the agent view).
echo "[agentic-terminal] Ready. term: tmux attach -t $TERM_SESSION"
case "$AGENT_ATTACH" in
    current)
        if [ -n "${TMUX:-}" ]; then
            echo "[agentic-terminal] Switching this tmux client to '$AGENT_SESSION'..."
            exec tmux switch-client -t "$AGENT_SESSION"
        elif [ -t 0 ] && [ -t 1 ]; then
            echo "[agentic-terminal] Attaching this terminal to '$AGENT_SESSION' (detach with Ctrl-b d)..."
            exec tmux attach -t "$AGENT_SESSION"
        else
            echo "[agentic-terminal] No interactive terminal; attach the agent manually with:"
            echo "    tmux attach -t $AGENT_SESSION"
        fi
        ;;
    *)
        echo "[agentic-terminal] agent: tmux attach -t $AGENT_SESSION"
        ;;
esac
