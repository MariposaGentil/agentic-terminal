#!/usr/bin/env bash
# Print a raw snapshot of the `term` pane, including scrollback. The agent uses
# this to catch up on state: what the human typed, what commands ran, and their
# output.
#
# Usage:
#   read.sh [lines]   # default 200 lines of scrollback
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_tmux
require_term_session

tmux capture-pane -pt "$TERM_SESSION" -S "-${1:-200}"
