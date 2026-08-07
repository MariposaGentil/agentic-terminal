# Startup flow: there is no fixed countdown any more. start.sh kicks off the
# agent, BLOCKS until it has finished the initial prompt, and only then opens
# `term` -- while prompting how to attach to BOTH sessions.
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

# --- the hard countdown is gone -----------------------------------------------
if grep -q 'run_start_countdown\|START_COUNTDOWN' "$REPO_ROOT/scripts/start.sh"; then
    fail "start.sh: no fixed countdown (removed run_start_countdown/START_COUNTDOWN)"
else
    pass "start.sh: no fixed countdown (removed run_start_countdown/START_COUNTDOWN)"
fi
if grep -q 'run_start_countdown' "$REPO_ROOT/scripts/_common.sh"; then
    fail "_common.sh: run_start_countdown helper removed"
else
    pass "_common.sh: run_start_countdown helper removed"
fi

# --- attach hints: BOTH sessions are prompted ---------------------------------
hints="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
    unset TMUX; AGENT_SESSION=A TERM_SESSION=T print_session_attach_hints" 2>&1)"
assert_contains "$hints" "tmux attach -t T" "attach hints: shows how to reach term"
assert_contains "$hints" "tmux attach -t A" "attach hints: shows how to reach agent"

hints_tmux="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
    TMUX=/tmp/fake AGENT_SESSION=A TERM_SESSION=T print_session_attach_hints" 2>&1)"
assert_contains "$hints_tmux" "switch-client -t T" "attach hints: uses switch-client for term inside tmux"
assert_contains "$hints_tmux" "switch-client -t A" "attach hints: uses switch-client for agent inside tmux"

# --- the agent is left detached, with instructions ----------------------------
hint="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
    unset TMUX; AGENT_SESSION=A print_agent_attach_hint" 2>&1)"
assert_contains "$hint" "DETACHED" "hint: says the agent is left detached"
assert_contains "$hint" "AGENT_ATTACH=current" "hint: mentions how to opt into auto-attach"

# --- end to end: start.sh returns instead of taking over the terminal ---------
# With AGENT_PROMPT_MODE=none there is no kickoff and thus no agent-ready wait,
# so start.sh sets both sessions up, prints how to attach to each, and exits.
if command -v tmux >/dev/null 2>&1; then
    S_TERM="ci_sterm_$$"; S_AGENT="ci_sagent_$$"
    S_LOGS="tmp/ci-start-$$"
    cleanup_start() {
        tmux kill-session -t "$S_TERM" 2>/dev/null
        tmux kill-session -t "$S_AGENT" 2>/dev/null
        rm -rf "${REPO_ROOT:?}/$S_LOGS"
    }
    trap 'cleanup_start; _helpers_cleanup' EXIT
    st_out="$(env -u AGENT_ATTACH -u TMUX \
        TMPDIR="$TMP" TERM_SESSION="$S_TERM" AGENT_SESSION="$S_AGENT" \
        LOGS_DIR="$S_LOGS" TERM_CWD="$TMP" AGENT_CMD=cat \
        AGENT_PROMPT_MODE=none TERM_ATTACH=none AGENT_AUTOPING=0 \
        timeout 30 bash "$REPO_ROOT/scripts/start.sh" 2>&1)"
    rc=$?
    assert_eq "0" "$rc" "start.sh: exits normally instead of attaching"
    assert_contains "$st_out" "tmux attach -t $S_AGENT" "start.sh: prints how to reach the agent"
    assert_contains "$st_out" "tmux attach -t $S_TERM" "start.sh: prints how to reach term"
    assert_not_contains "$st_out" "Attaching this terminal" "start.sh: does not take over the terminal"
    assert_not_contains "$st_out" "Switching this tmux client" "start.sh: does not hijack an outer tmux client"
    cleanup_start
else
    skip "start.sh end-to-end" "tmux not installed"
fi

# --- initial-prompt completion detection (pane stability) ---------------------
# Robust against the "busy forever" bug: detection watches the VISIBLE screen and
# waits for it to stop changing, rather than matching (possibly stale) status text.
if command -v tmux >/dev/null 2>&1; then
    ST="ci_stab_$$"; CH="ci_chg_$$"
    cleanup_stab() { tmux kill-session -t "$ST" 2>/dev/null; tmux kill-session -t "$CH" 2>/dev/null; }
    trap 'cleanup_stab; _helpers_cleanup' EXIT

    # A static pane (prints once, then idle) must be detected as "processed".
    tmux new-session -d -s "$ST" "bash -c 'clear; echo READY; sleep 300'"
    sleep 1
    stat_out="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
        AGENT_SESSION=$ST AGENT_IDLE_STABLE=3 wait_for_agent_prompt_done 15" 2>&1)"
    assert_contains "$stat_out" "Initial prompt processed" \
        "prompt-wait: a static agent pane is detected as done"

    # A continuously-redrawing pane must NOT be called done (it times out instead).
    tmux new-session -d -s "$CH" "bash -c 'i=0; while :; do printf \"\\rworking %d\" \$i; i=\$((i+1)); sleep 0.3; done'"
    sleep 1
    chg_out="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
        AGENT_SESSION=$CH AGENT_IDLE_STABLE=3 wait_for_agent_prompt_done 6" 2>&1)"
    assert_contains "$chg_out" "still processing" \
        "prompt-wait: a busy (changing) pane is NOT falsely called done"
    assert_not_contains "$chg_out" "Initial prompt processed" \
        "prompt-wait: no premature 'processed' while the pane keeps changing"

    # 0 (or unset) skips the wait entirely (term opens immediately).
    skip_out="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
        AGENT_SESSION=$ST wait_for_agent_prompt_done 0" 2>&1)"
    assert_eq "" "$skip_out" "prompt-wait: AGENT_PROMPT_WAIT=0 skips the wait"
    cleanup_stab
else
    skip "initial-prompt completion detection" "tmux not installed"
fi

# --- start.sh opens term only AFTER the agent-ready wait ----------------------
# Source order matters: kickoff -> block on agent-ready -> open term. If term
# opened before the wait it could appear while the agent is still booting.
kick_line="$(grep -n 'send-keys -t "\$AGENT_SESSION" -l "\$AGENT_BOOTSTRAP"' "$REPO_ROOT/scripts/start.sh" | head -n1 | cut -d: -f1)"
wait_line="$(grep -n 'wait_for_agent_prompt_done "\${AGENT_PROMPT_WAIT' "$REPO_ROOT/scripts/start.sh" | head -n1 | cut -d: -f1)"
term_line="$(grep -n 'TERMINAL_EMULATOR%%' "$REPO_ROOT/scripts/start.sh" | head -n1 | cut -d: -f1)"
if [ -n "$kick_line" ] && [ -n "$wait_line" ] && [ -n "$term_line" ] \
    && [ "$kick_line" -lt "$wait_line" ] && [ "$wait_line" -lt "$term_line" ]; then
    pass "start.sh: kickoff -> agent-ready wait -> open term (in that order)"
else
    fail "start.sh: kickoff -> agent-ready wait -> open term (in that order)" \
        "kickoff@$kick_line wait@$wait_line term@$term_line"
fi
