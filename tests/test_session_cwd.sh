# SESSION_CWD: both tmux sessions start in the invocation directory.
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

# resolve_session_cwd: SESSION_CWD > TERM_CWD > $PWD > REPO_ROOT
mkdir -p "$TMP/sub" "$TMP/explicit"
resolved="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
    SESSION_CWD='' TERM_CWD='' PWD='$TMP' resolve_session_cwd")"
assert_eq "$TMP" "$resolved" "resolve_session_cwd: defaults to invocation PWD"

legacy="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
    SESSION_CWD='' TERM_CWD='$TMP/sub' PWD='/tmp' resolve_session_cwd")"
assert_eq "$TMP/sub" "$legacy" "resolve_session_cwd: TERM_CWD legacy alias wins over PWD"

explicit="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
    SESSION_CWD='$TMP/explicit' TERM_CWD='/tmp/other' PWD='/tmp' resolve_session_cwd")"
assert_eq "$TMP/explicit" "$explicit" "resolve_session_cwd: SESSION_CWD wins"

fallback="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
    SESSION_CWD='/nonexistent/path' resolve_session_cwd")"
assert_eq "$REPO_ROOT" "$fallback" "resolve_session_cwd: falls back to REPO_ROOT for bad path"

# Makefile start/run pattern: do not clobber a caller-provided SESSION_CWD with $PWD.
make_pattern="$(bash -c "cd '$REPO_ROOT' && export SESSION_CWD='$TMP/explicit' && \
    SESSION_CWD=\"\${SESSION_CWD:-\$PWD}\" TERM_CWD=\"\${TERM_CWD:-\$SESSION_CWD}\" \
    printf '%s' \"\$SESSION_CWD\"")"
assert_eq "$TMP/explicit" "$make_pattern" \
    "make start pattern: preserves pre-set SESSION_CWD over toolkit PWD"

make_default="$(bash -c "cd '$TMP/sub' && unset SESSION_CWD TERM_CWD && \
    SESSION_CWD=\"\${SESSION_CWD:-\$PWD}\" TERM_CWD=\"\${TERM_CWD:-\$SESSION_CWD}\" \
    bash -c 'printf \"%s\" \"\$SESSION_CWD\"'")"
assert_eq "$TMP/sub" "$make_default" \
    "make start pattern: defaults to invocation PWD when SESSION_CWD unset"

# build_agent_kickoff expands toolkit paths for file reads.
kickoff="$(bash -c "source '$REPO_ROOT/scripts/_common.sh'; \
    SESSION_CWD='$TMP' AGENT_BOOTSTRAP='Read \$AGENTIC_TERMINAL_ROOT/foo' \
    build_agent_kickoff")"
assert_contains "$kickoff" "$REPO_ROOT/foo" "build_agent_kickoff: expands AGENTIC_TERMINAL_ROOT"

# Shared tmux helpers for end-to-end SESSION_CWD checks.
_session_pwd() { tmux display-message -pt "$1" -p '#{pane_current_path}' 2>/dev/null || true; }
_session_env() { tmux show-environment -t "$1" "$2" 2>/dev/null | cut -d= -f2- || true; }

if command -v tmux >/dev/null 2>&1; then
    # End-to-end: both sessions get SESSION_CWD, not REPO_ROOT.
    S_TERM="ci_cwd_term_$$"; S_AGENT="ci_cwd_agent_$$"
    S_LOGS="tmp/ci-cwd-$$"
    mkdir -p "$TMP/cwd-test"
    cleanup_cwd() {
        tmux kill-session -t "$S_TERM" 2>/dev/null
        tmux kill-session -t "$S_AGENT" 2>/dev/null
        rm -rf "${REPO_ROOT:?}/$S_LOGS" "$TMP/cwd-test"
    }
    trap 'cleanup_cwd; _helpers_cleanup' EXIT
    st_out="$(env -u TMUX AGENT_ATTACH=none \
        TMPDIR="$TMP" TERM_SESSION="$S_TERM" AGENT_SESSION="$S_AGENT" \
        LOGS_DIR="$S_LOGS" SESSION_CWD="$TMP/cwd-test" AGENT_CMD=cat \
        AGENT_PROMPT_MODE=none TERM_ATTACH=none AGENT_AUTOPING=0 \
        bash -c "cd '$REPO_ROOT' && bash scripts/start.sh" 2>&1)"
    rc=$?
    assert_eq "0" "$rc" "start.sh: exits with SESSION_CWD set"
    assert_contains "$st_out" "Session working directory: $TMP/cwd-test" \
        "start.sh: reports SESSION_CWD"
    assert_eq "$TMP/cwd-test" "$(_session_pwd "$S_TERM")" "term session cwd is SESSION_CWD"
    assert_eq "$TMP/cwd-test" "$(_session_pwd "$S_AGENT")" "agent session cwd is SESSION_CWD"
    assert_eq "$REPO_ROOT" "$(_session_env "$S_TERM" AGENTIC_TERMINAL_ROOT)" \
        "term session has AGENTIC_TERMINAL_ROOT"
    cleanup_cwd
    trap - EXIT

    # atstart: launch from a project directory (not the toolkit repo).
    S_TERM="ci_atstart_term_$$"; S_AGENT="ci_atstart_agent_$$"
    S_LOGS="tmp/ci-atstart-$$"
    mkdir -p "$TMP/atstart-test"
    cleanup_atstart() {
        tmux kill-session -t "$S_TERM" 2>/dev/null
        tmux kill-session -t "$S_AGENT" 2>/dev/null
        rm -rf "${REPO_ROOT:?}/$S_LOGS" "$TMP/atstart-test"
    }
    trap 'cleanup_atstart; _helpers_cleanup' EXIT
    at_out="$(env -u TMUX AGENT_ATTACH=none \
        TMPDIR="$TMP" TERM_SESSION="$S_TERM" AGENT_SESSION="$S_AGENT" \
        LOGS_DIR="$S_LOGS" AGENT_CMD=cat AGENT_PROMPT_MODE=none \
        TERM_ATTACH=none AGENT_AUTOPING=0 \
        bash -c "cd '$TMP/atstart-test' && '$REPO_ROOT/scripts/atstart.sh' --no-setup" 2>&1)"
    rc=$?
    assert_eq "0" "$rc" "atstart: exits from project directory"
    assert_contains "$at_out" "Session working directory: $TMP/atstart-test" \
        "atstart: reports project directory as SESSION_CWD"
    assert_eq "$TMP/atstart-test" "$(_session_pwd "$S_TERM")" \
        "atstart: term session cwd is launch directory"
    assert_eq "$TMP/atstart-test" "$(_session_pwd "$S_AGENT")" \
        "atstart: agent session cwd is launch directory"
    cleanup_atstart
    trap - EXIT

    # run.sh: launch from a project directory.
    S_TERM="ci_run_term_$$"; S_AGENT="ci_run_agent_$$"
    S_LOGS="tmp/ci-run-$$"
    mkdir -p "$TMP/run-test"
    cleanup_run() {
        tmux kill-session -t "$S_TERM" 2>/dev/null
        tmux kill-session -t "$S_AGENT" 2>/dev/null
        rm -rf "${REPO_ROOT:?}/$S_LOGS" "$TMP/run-test"
    }
    trap 'cleanup_run; _helpers_cleanup' EXIT
    run_out="$(env -u TMUX AGENT_ATTACH=none \
        TMPDIR="$TMP" TERM_SESSION="$S_TERM" AGENT_SESSION="$S_AGENT" \
        LOGS_DIR="$S_LOGS" AGENT_CMD=cat AGENT_PROMPT_MODE=none \
        TERM_ATTACH=none AGENT_AUTOPING=0 \
        bash -c "cd '$TMP/run-test' && '$REPO_ROOT/run.sh' --no-setup" 2>&1)"
    rc=$?
    assert_eq "0" "$rc" "run.sh: exits from project directory"
    assert_contains "$run_out" "Session working directory: $TMP/run-test" \
        "run.sh: reports project directory as SESSION_CWD"
    assert_eq "$TMP/run-test" "$(_session_pwd "$S_TERM")" \
        "run.sh: term session cwd is launch directory"
    assert_eq "$TMP/run-test" "$(_session_pwd "$S_AGENT")" \
        "run.sh: agent session cwd is launch directory"
    cleanup_run
    trap - EXIT

    if command -v make >/dev/null 2>&1; then
        # make start: caller sets SESSION_CWD while make runs in the toolkit dir.
        S_TERM="ci_make_term_$$"; S_AGENT="ci_make_agent_$$"
        S_LOGS="tmp/ci-make-$$"
        mkdir -p "$TMP/make-test"
        cleanup_make() {
            tmux kill-session -t "$S_TERM" 2>/dev/null
            tmux kill-session -t "$S_AGENT" 2>/dev/null
            rm -rf "${REPO_ROOT:?}/$S_LOGS" "$TMP/make-test"
        }
        trap 'cleanup_make; _helpers_cleanup' EXIT
        make_out="$(env -u TMUX AGENT_ATTACH=none \
            TMPDIR="$TMP" TERM_SESSION="$S_TERM" AGENT_SESSION="$S_AGENT" \
            LOGS_DIR="$S_LOGS" AGENT_CMD=cat AGENT_PROMPT_MODE=none \
            TERM_ATTACH=none AGENT_AUTOPING=0 \
            bash -c "cd '$REPO_ROOT' && SESSION_CWD='$TMP/make-test' make start" 2>&1)"
        rc=$?
        assert_eq "0" "$rc" "make start: exits with SESSION_CWD set from caller"
        assert_contains "$make_out" "Session working directory: $TMP/make-test" \
            "make start: reports caller SESSION_CWD, not toolkit PWD"
        assert_eq "$TMP/make-test" "$(_session_pwd "$S_TERM")" \
            "make start: term session cwd is caller SESSION_CWD"
        assert_eq "$TMP/make-test" "$(_session_pwd "$S_AGENT")" \
            "make start: agent session cwd is caller SESSION_CWD"
        cleanup_make
        trap - EXIT

        # make -C: launch from a project dir via SESSION_CWD=$PWD make -C … start
        S_TERM="ci_makec_term_$$"; S_AGENT="ci_makec_agent_$$"
        S_LOGS="tmp/ci-makec-$$"
        mkdir -p "$TMP/make-c-test"
        cleanup_make_c() {
            tmux kill-session -t "$S_TERM" 2>/dev/null
            tmux kill-session -t "$S_AGENT" 2>/dev/null
            rm -rf "${REPO_ROOT:?}/$S_LOGS" "$TMP/make-c-test"
        }
        trap 'cleanup_make_c; _helpers_cleanup' EXIT
        make_c_out="$(env -u TMUX AGENT_ATTACH=none \
            TMPDIR="$TMP" TERM_SESSION="$S_TERM" AGENT_SESSION="$S_AGENT" \
            LOGS_DIR="$S_LOGS" AGENT_CMD=cat AGENT_PROMPT_MODE=none \
            TERM_ATTACH=none AGENT_AUTOPING=0 \
            bash -c "cd '$TMP/make-c-test' && SESSION_CWD='$TMP/make-c-test' make -C '$REPO_ROOT' start" 2>&1)"
        rc=$?
        assert_eq "0" "$rc" "make -C start: exits from project directory"
        assert_contains "$make_c_out" "Session working directory: $TMP/make-c-test" \
            "make -C start: reports project directory as SESSION_CWD"
        assert_eq "$TMP/make-c-test" "$(_session_pwd "$S_TERM")" \
            "make -C start: term session cwd is launch directory"
        assert_eq "$TMP/make-c-test" "$(_session_pwd "$S_AGENT")" \
            "make -C start: agent session cwd is launch directory"
        cleanup_make_c
        trap - EXIT
    else
        skip "make start SESSION_CWD end-to-end" "make not installed"
        skip "make -C start SESSION_CWD end-to-end" "make not installed"
    fi

    # Reusing existing sessions does not change cwd.
    S_TERM="ci_reuse_term_$$"; S_AGENT="ci_reuse_agent_$$"
    S_LOGS="tmp/ci-reuse-$$"
    mkdir -p "$TMP/reuse-a" "$TMP/reuse-b"
    cleanup_reuse() {
        tmux kill-session -t "$S_TERM" 2>/dev/null
        tmux kill-session -t "$S_AGENT" 2>/dev/null
        rm -rf "${REPO_ROOT:?}/$S_LOGS" "$TMP/reuse-a" "$TMP/reuse-b"
    }
    trap 'cleanup_reuse; _helpers_cleanup' EXIT
    env -u TMUX AGENT_ATTACH=none \
        TMPDIR="$TMP" TERM_SESSION="$S_TERM" AGENT_SESSION="$S_AGENT" \
        LOGS_DIR="$S_LOGS" SESSION_CWD="$TMP/reuse-a" AGENT_CMD=cat \
        AGENT_PROMPT_MODE=none TERM_ATTACH=none AGENT_AUTOPING=0 \
        bash -c "cd '$REPO_ROOT' && bash scripts/start.sh" >/dev/null 2>&1
    reuse_out="$(env -u TMUX AGENT_ATTACH=none \
        TMPDIR="$TMP" TERM_SESSION="$S_TERM" AGENT_SESSION="$S_AGENT" \
        LOGS_DIR="$S_LOGS" SESSION_CWD="$TMP/reuse-b" AGENT_CMD=cat \
        AGENT_PROMPT_MODE=none TERM_ATTACH=none AGENT_AUTOPING=0 \
        bash -c "cd '$REPO_ROOT' && bash scripts/start.sh" 2>&1)"
    rc=$?
    assert_eq "0" "$rc" "start.sh: reuses existing sessions"
    assert_contains "$reuse_out" "already running" \
        "start.sh: reports reused sessions"
    assert_eq "$TMP/reuse-a" "$(_session_pwd "$S_TERM")" \
        "reuse: term session cwd stays at first SESSION_CWD"
    assert_eq "$TMP/reuse-a" "$(_session_pwd "$S_AGENT")" \
        "reuse: agent session cwd stays at first SESSION_CWD"
    cleanup_reuse
    trap - EXIT
else
    skip "start.sh SESSION_CWD end-to-end" "tmux not installed"
    skip "atstart SESSION_CWD end-to-end" "tmux not installed"
    skip "run.sh SESSION_CWD end-to-end" "tmux not installed"
    skip "make start SESSION_CWD end-to-end" "tmux not installed"
    skip "make -C start SESSION_CWD end-to-end" "tmux not installed"
    skip "reuse keeps original SESSION_CWD" "tmux not installed"
fi
