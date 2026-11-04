#!/usr/bin/env bash
# agentic-terminal entrypoint: verify the environment, then launch the agent +
# terminal. This is the one command to bind to your terminal keyboard shortcut.
#
# Usage:
#   ./run.sh                  # setup (check only) + start
#   ./run.sh --install-deps   # setup may apt-install missing deps, then start
#   ./run.sh --no-setup       # skip setup, just start
#   AGENT_CMD=claude ./run.sh # override the agent for this launch
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/scripts"
# Launch directory: where the user ran run.sh / atstart (atstart may pre-set SESSION_CWD).
LAUNCH_CWD="${SESSION_CWD:-$PWD}"

usage() {
    cat <<'EOF'
run.sh — agentic-terminal entrypoint

Verifies the environment, then launches the CLI agent alongside an interactive
terminal (setup + start). Bind this command to your terminal keyboard shortcut.

Usage:
  ./run.sh [options]

Options:
  --install-deps   Let setup try to apt-install missing dependencies (e.g. tmux).
  --no-setup       Skip environment checks and launch directly.
  -h, --help       Show this help and exit.

Environment:
  AGENT_CMD          Agent to run in the detached 'agent' session (e.g. claude).
  TERMINAL_EMULATOR  How to open the human 'term' window (default: x-terminal-emulator).
  (See scripts/config.sh for all configurable values.)

Examples:
  ./run.sh                    # verify, then launch
  ./run.sh --install-deps     # install missing deps, then launch
  ./run.sh --no-setup         # launch without checks
  AGENT_CMD=claude ./run.sh   # override the agent for this launch
EOF
}

run_setup=1
setup_args=()

for arg in "$@"; do
    case "$arg" in
        --no-setup)     run_setup=0 ;;
        --install-deps) setup_args+=("--install-deps") ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[run] Unknown option: $arg" >&2
            echo "[run] Try './run.sh --help' for usage." >&2
            exit 1
            ;;
    esac
done

if [ "$run_setup" -eq 1 ]; then
    echo "[run] Verifying environment..."
    "$SCRIPTS/setup.sh" ${setup_args[@]+"${setup_args[@]}"}
fi

echo "[run] Launching agentic-terminal..."
export SESSION_CWD="$LAUNCH_CWD"
export TERM_CWD="$SESSION_CWD"
exec "$SCRIPTS/start.sh"
