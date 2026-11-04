#!/usr/bin/env bash
# Bootstrap agentic-terminal: create the two tmux sessions and wire them up.
#
#   1. `term`  - interactive shell the human works in. Opened in the system's
#                default terminal emulator (attached to the tmux session so the
#                agent can read/write it too).
#   2. `agent` - runs the configured CLI agent ($AGENT_CMD), started DETACHED so
#                it drives `term` in the background.
#
# The agent is created and kicked off FIRST. There is no fixed countdown: start
# blocks until the agent has finished processing its initial prompt (detected by
# pane stability, capped at AGENT_PROMPT_WAIT), and only THEN opens `term` in a
# new terminal window -- so `term` never appears before the agent is ready. The
# terminal that ran start is then attached to `agent` (AGENT_ATTACH=current,
# default); AGENT_ATTACH=none leaves it at its own shell with attach hints.
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

SESSION_CWD="$(resolve_session_cwd)"
export SESSION_CWD TERM_CWD="$SESSION_CWD"
echo "[agentic-terminal] Session working directory: $SESSION_CWD (toolkit: $REPO_ROOT)"

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
    # Self-heal: if the watcher pipe was lost (e.g. closed during development),
    # re-attach it so re-running start REPAIRS a broken auto-ping.
    if [ "$(term_is_piped)" = "1" ]; then
        echo "[agentic-terminal] Watcher is attached. (Run 'make reload-watcher' to force a reload.)"
    else
        echo "[agentic-terminal] Watcher pipe missing on '$TERM_SESSION' -- repairing..."
        attach_watcher "repaired"
        echo "[agentic-terminal] Watcher re-attached. Transcript: $WATCHER_LOG"
    fi
else
    echo "[agentic-terminal] Creating interactive session '$TERM_SESSION' (cwd: $SESSION_CWD)..."
    term_bashrc="$(resolve_term_bashrc_path)"
    if [ -n "$term_bashrc" ]; then
        echo "[agentic-terminal] Term shell: bash --rcfile '$term_bashrc'"
        tmux new-session -d -s "$TERM_SESSION" -c "$SESSION_CWD" \
            -e "AGENTIC_TERMINAL_ROOT=$REPO_ROOT" -e "SESSION_CWD=$SESSION_CWD" \
            bash --rcfile "$term_bashrc" -i
    else
        tmux new-session -d -s "$TERM_SESSION" -c "$SESSION_CWD" \
            -e "AGENTIC_TERMINAL_ROOT=$REPO_ROOT" -e "SESSION_CWD=$SESSION_CWD"
    fi
    set_session_env "$TERM_SESSION"
    # Fresh term -> forget which comment requests were already processed.
    rm -f "$COMMENT_STATE"

    # Attach the host-side watcher (pipe-pane): logs the transcript AND auto-pings
    # the agent on a trigger match. Because it consumes the pane stream (not the
    # shell), nothing shell-specific is injected into term. The transcript name
    # ties it to the agent+term sessions and a stable
    # "<AGENT_SESSION>.current.log" symlink always points at the live one.
    attach_watcher "started"
    echo "[agentic-terminal] Logging session transcript to: $WATCHER_LOG"
    echo "[agentic-terminal] Stable pointer: $WATCHER_LINK"
    if [ "${AGENT_AUTOPING:-1}" = "1" ]; then
        echo "[agentic-terminal] Auto-ping enabled: matches in '$TERM_SESSION' will poke '$AGENT_SESSION' (regex file: $(ping_trigger_path))."
    fi
    show_term_welcome
    term_created=1
fi

# Agent busy/free indicator in the term status bar (also on reuse / repair).
configure_term_status_bar

# --- agent session (detached) + kickoff --------------------------------------
agent_created=0
# Set to 1 once the kickoff prompt has actually been typed into the agent, so we
# know whether there is anything to wait on before opening `term`.
kickoff_sent=0
if tmux has-session -t "$AGENT_SESSION" 2>/dev/null; then
    echo "[agentic-terminal] Session '$AGENT_SESSION' already running. Reusing it."
else
    # Build the launch command: AGENT_CMD + model + extra args. AGENT_ARGS makes
    # the agent non-interactive (e.g. cursor-agent --force --trust) so it doesn't
    # stop for per-command approval while driving `term` unattended.
    agent_cmd="$AGENT_CMD"
    if [ -n "${AGENT_MODEL:-}" ]; then
        agent_cmd="$agent_cmd --model $AGENT_MODEL"
    fi
    if [ -n "${AGENT_ARGS:-}" ]; then
        agent_cmd="$agent_cmd $AGENT_ARGS"
    fi
    echo "[agentic-terminal] Starting agent session '$AGENT_SESSION' (detached, cwd: $SESSION_CWD): $agent_cmd"
    tmux new-session -d -s "$AGENT_SESSION" -c "$SESSION_CWD" \
        -e "AGENTIC_TERMINAL_ROOT=$REPO_ROOT" -e "SESSION_CWD=$SESSION_CWD"
    set_session_env "$AGENT_SESSION"
    show_agent_welcome
    tmux send-keys -t "$AGENT_SESSION" -l "$agent_cmd"
    tmux send-keys -t "$AGENT_SESSION" Enter
    agent_created=1

    # Connect the agent to `term`: tell it its role by pointing it at the prompt
    # file. Delivered by typing into the (detached) agent session once the CLI
    # has had a moment to boot. Agent-CLI-agnostic: it just reads the file.
    if [ "$AGENT_PROMPT_MODE" = "send-keys" ]; then
        if [ ! -f "$REPO_ROOT/$AGENT_PROMPT_FILE" ]; then
            echo "[agentic-terminal] Warning: prompt file '$AGENT_PROMPT_FILE' not found; agent will start without instructions." >&2
        fi
        # Load the agent's capabilities: agent-prompt.md + every rule in the
        # rules dir (the kickoff message tells the agent to read them all).
        rules_dir="$REPO_ROOT/$AGENT_RULES_DIR"
        if [ -d "$rules_dir" ]; then
            n_rules="$(find "$rules_dir" -type f -name '*.md' 2>/dev/null | wc -l)"
        else
            n_rules=0
            echo "[agentic-terminal] Warning: rules dir '$AGENT_RULES_DIR' not found; loading the prompt only." >&2
        fi
        kickoff="$(build_agent_kickoff)"
        if [ -n "${AGENT_PROJECT_CAPS_DIR:-}" ] && [ -d "$AGENT_PROJECT_CAPS_DIR/rules" ]; then
            n_project_rules="$(find "$AGENT_PROJECT_CAPS_DIR/rules" -type f -name '*.md' 2>/dev/null | wc -l)"
            echo "[agentic-terminal] Project overlay: ${AGENT_PROJECT_CAPS_DIR}/ (${n_project_rules} rule(s))."
        fi
        # Step 1/3: give the CLI a moment to draw its TUI before we type at it.
        echo "[agentic-terminal] Step 1/3: initializing agent CLI '$AGENT_CMD' (waiting ${AGENT_READY_WAIT}s for it to boot)..."
        sleep "$AGENT_READY_WAIT"
        # Step 2/3: type the kickoff, let the TUI settle, then submit with Enter as
        # a separate keystroke (sending them together often leaves the prompt typed
        # but not submitted).
        echo "[agentic-terminal] Step 2/3: loading initial prompt from '$AGENT_CAPS_DIR/' (agent-prompt.md + ${n_rules:-0} rule(s) in $AGENT_RULES_DIR/)..."
        tmux send-keys -t "$AGENT_SESSION" -l "$kickoff"
        sleep "$AGENT_SUBMIT_DELAY"
        tmux send-keys -t "$AGENT_SESSION" Enter
        kickoff_sent=1
    else
        echo "[agentic-terminal] AGENT_PROMPT_MODE=$AGENT_PROMPT_MODE; not sending a kickoff prompt."
    fi
fi

# --- block until the agent is ready ------------------------------------------
# This is the ONLY blocking point (there is no fixed countdown any more): `term`
# is not opened until the agent has finished processing its initial prompt, so
# it appears with the agent already primed. Skipped when we're attaching to the
# agent (you'll watch it boot live) or when AGENT_PROMPT_WAIT=0.
if [ "$kickoff_sent" -eq 1 ] && [ "$AGENT_ATTACH" != "current" ]; then
    echo "[agentic-terminal] Step 3/3: waiting for the agent to be ready before opening '$TERM_SESSION'..."
    wait_for_agent_prompt_done "${AGENT_PROMPT_WAIT:-0}"
fi

# --- open term (only now that the agent is ready) ----------------------------
# term -> a NEW terminal-emulator window. Only spawn one if we just created the
# session, to avoid duplicate windows when start is re-run.
case "$TERM_ATTACH" in
    emulator)
        if [ "$term_created" -eq 1 ]; then
            if command -v "${TERMINAL_EMULATOR%% *}" >/dev/null 2>&1; then
                echo "[agentic-terminal] Agent is ready -- opening '$TERMINAL_EMULATOR' for '$TERM_SESSION'..."
                $TERMINAL_EMULATOR -e tmux attach -t "$TERM_SESSION" >/dev/null 2>&1 &
            else
                echo "[agentic-terminal] '$TERMINAL_EMULATOR' not found; open term yourself:"
                echo "    tmux attach -t $TERM_SESSION"
            fi
        fi
        ;;
    *)
        : # term is left detached; the attach hints below tell the user how to reach it.
        ;;
esac

# --- how to reach the sessions -----------------------------------------------
# Prompt how to attach to BOTH sessions, then take this terminal over with the
# agent (AGENT_ATTACH=current, default). AGENT_ATTACH=none keeps this shell.
print_session_attach_hints
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
        echo "[agentic-terminal] (Unset AGENT_ATTACH or set it to 'current' to take this terminal over with the agent.)"
        ;;
esac
