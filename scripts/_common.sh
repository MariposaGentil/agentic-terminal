#!/usr/bin/env bash
# Shared configuration and helpers for the agentic-terminal .agents scripts.
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
