#!/usr/bin/env bash
# Launch agentic-terminal from any directory: term and agent both start in $PWD.
#
# Install (optional):
#   ln -sf "$(pwd)/scripts/atstart.sh" ~/bin/atstart
#
# Usage:
#   cd /path/to/your-project && atstart
#   cd /path/to/your-project && /path/to/agentic-terminal/scripts/atstart.sh
set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SESSION_CWD="$PWD"
export TERM_CWD="$PWD"
exec "$REPO_ROOT/run.sh" "$@"
