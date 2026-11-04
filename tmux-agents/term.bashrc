# term.bashrc — aliases and functions for the `term` tmux session only.
#
# Loaded by start.sh: bash --rcfile <this-file> -i
# The agent session and your regular terminals are unaffected.

# Optional: keep your normal prompt, PATH, and shell setup.
if [ -f "${HOME}/.bashrc" ]; then
    # shellcheck source=/dev/null
    source "${HOME}/.bashrc"
fi

# Toolkit paths (exported into term by start.sh).
: "${AGENTIC_TERMINAL_ROOT:?AGENTIC_TERMINAL_ROOT not set}"
: "${SESSION_CWD:=${SESSION_CWD:-$PWD}}"

_at() { "$AGENTIC_TERMINAL_ROOT/scripts/$1" "${@:2}"; }

alias atread='_at read.sh'
alias atsend='_at send.sh'
alias atsay='_at say.sh'
alias atwatch='_at watch.sh status'
alias atrequests='_at requests.sh'

# Agentic-terminal test suite. The agent can run this from term via send.sh:
#   echo 'make test' | $AGENTIC_TERMINAL_ROOT/scripts/send.sh
#
# When cwd is the toolkit repo (or there is no Makefile here), `make test`
# runs the agentic-terminal suite even if SESSION_CWD was a different project.
make() {
    local root="$AGENTIC_TERMINAL_ROOT"
    if [ $# -ge 1 ] && [ "$1" = "test" ] && [ -f "$root/Makefile" ]; then
        local here toolkit
        here="$(pwd -P)"
        toolkit="$(cd "$root" && pwd -P)"
        if [ "$here" = "$toolkit" ] || [ ! -f ./Makefile ]; then
            shift
            command make -C "$root" test "$@"
            return
        fi
    fi
    command make "$@"
}

# Project-specific term-only additions (when SESSION_CWD is another repo).
_project_rc="${SESSION_CWD}/tmux-agents/term.bashrc"
_toolkit_rc="${AGENTIC_TERMINAL_ROOT}/tmux-agents/term.bashrc"
if [ -n "${SESSION_CWD:-}" ] && [ -f "$_project_rc" ] && [ "$_project_rc" != "$_toolkit_rc" ]; then
    # shellcheck source=/dev/null
    source "$_project_rc"
fi
unset _project_rc _toolkit_rc
