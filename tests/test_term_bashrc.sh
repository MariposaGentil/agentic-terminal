# TERM_BASHRC: optional bash --rcfile for the `term` session only.
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

# Shipped term.bashrc in this repo is picked up by default.
repo_rc="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
    SESSION_CWD='$REPO_ROOT' resolve_term_bashrc_path")"
assert_eq "$REPO_ROOT/tmux-agents/term.bashrc" "$repo_rc" \
    "resolve_term_bashrc_path: toolkit term.bashrc when present"

# resolve_term_bashrc_path: disabled when TERM_BASHRC is 0/none/empty.
disabled="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
    SESSION_CWD='$TMP' TERM_BASHRC=none resolve_term_bashrc_path")"
assert_eq "" "$disabled" "resolve_term_bashrc_path: none -> empty"

# resolve_term_bashrc_path: explicit file wins.
mkdir -p "$TMP/explicit"
printf 'alias explicit_marker=1\n' > "$TMP/explicit/term.bashrc"
explicit="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
    SESSION_CWD='$TMP/other' TERM_BASHRC='$TMP/explicit/term.bashrc' \
    resolve_term_bashrc_path")"
assert_eq "$TMP/explicit/term.bashrc" "$explicit" \
    "resolve_term_bashrc_path: explicit path when file exists"

# resolve_term_bashrc_path: project overlay when configured path is missing.
mkdir -p "$TMP/project/tmux-agents"
printf 'alias project_marker=1\n' > "$TMP/project/tmux-agents/term.bashrc"
project="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
    SESSION_CWD='$TMP/project' TERM_BASHRC='tmux-agents/no-such-term.bashrc' \
    resolve_term_bashrc_path")"
assert_eq "$TMP/project/tmux-agents/term.bashrc" "$project" \
    "resolve_term_bashrc_path: project tmux-agents/term.bashrc when toolkit path missing"

# term_shell_argv: bash --rcfile … -i when a rc file is resolved.
argv="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
    TERM_BASHRC='$TMP/explicit/term.bashrc' term_shell_argv | tr '\\0' ' '")"
assert_contains "$argv" "bash --rcfile $TMP/explicit/term.bashrc -i" \
    "term_shell_argv: emits bash --rcfile -i"

if command -v tmux >/dev/null 2>&1; then
    S_TERM="ci_bashrc_term_$$"; S_AGENT="ci_bashrc_agent_$$"
    S_LOGS="tmp/ci-bashrc-$$"
    mkdir -p "$TMP/bashrc-test"
    printf 'ci_term_bashrc_marker() { echo BASHRC_OK; }\n' > "$TMP/bashrc-test/term.bashrc"
    cleanup_bashrc() {
        tmux kill-session -t "$S_TERM" 2>/dev/null
        tmux kill-session -t "$S_AGENT" 2>/dev/null
        rm -rf "${REPO_ROOT:?}/$S_LOGS" "$TMP/bashrc-test"
    }
    trap 'cleanup_bashrc; _helpers_cleanup' EXIT
    st_out="$(env -u TMUX AGENT_ATTACH=none \
        TMPDIR="$TMP" TERM_SESSION="$S_TERM" AGENT_SESSION="$S_AGENT" \
        LOGS_DIR="$S_LOGS" SESSION_CWD="$TMP/bashrc-test" AGENT_CMD=cat \
        AGENT_PROMPT_MODE=none TERM_ATTACH=none AGENT_AUTOPING=0 \
        TERM_BASHRC="$TMP/bashrc-test/term.bashrc" \
        bash -c "cd '$REPO_ROOT' && bash scripts/start.sh" 2>&1)"
    rc=$?
    assert_eq "0" "$rc" "start.sh: exits with TERM_BASHRC set"
    assert_contains "$st_out" "bash --rcfile '$TMP/bashrc-test/term.bashrc'" \
        "start.sh: reports custom term bashrc"
    sleep 0.5
    tmux send-keys -t "$S_TERM" -l "ci_term_bashrc_marker"
    tmux send-keys -t "$S_TERM" Enter
    sleep 0.5
    pane_out="$(tmux capture-pane -pt "$S_TERM" -S -20 2>/dev/null || true)"
    assert_contains "$pane_out" "BASHRC_OK" \
        "term session: custom function from term.bashrc is available"
    cleanup_bashrc
    trap - EXIT
else
    skip "term bashrc end-to-end" "tmux not installed"
fi
