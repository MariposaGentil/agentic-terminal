#!/usr/bin/env bash
# Print the current agent status for the `term` tmux status bar.
#
# Used as a tmux `#()` command (see configure_term_status_bar in _common.sh):
#   status-right "#(env AGENT_SESSION=agent …/agent-status.sh)"
#
# Plain text (tests / debugging):
#   AGENT_STATUS_PLAIN=1 scripts/agent-status.sh   -> busy|free|offline|queued
set -o nounset

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_HERE/_agent_status.sh"

: "${AGENT_SESSION:=agent}"

if [ "${AGENT_STATUS_PLAIN:-0}" = "1" ]; then
    agent_status_state
else
    agent_status_tmux
    printf '\n'
fi
