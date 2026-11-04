# End-to-end tests using a REAL tmux server (skipped if tmux is unavailable):
#   A) auto-ping: a comment typed in `term` reaches the agent as `ping`.
#   B) send.sh / read.sh: run a command in `term` and capture its output.
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

if ! command -v tmux >/dev/null 2>&1; then
    skip "integration tests" "tmux not installed"
    exit 0
fi

TERM_A="ci_term_$$"
AGENT_A="ci_agent_$$"
TERM_B="ci_send_$$"
TERM_PY="ci_py_$$"
TERM_W="ci_watch_$$"
AGENT_W="ci_wagent_$$"

cleanup_sessions() {
    for s in "$TERM_A" "$AGENT_A" "$TERM_B" "$TERM_PY" "$TERM_W" "$AGENT_W" "${TERM_A}_say" "${TERM_A}_say_agent" "ci_agent_py_$$"; do
        tmux kill-session -t "$s" 2>/dev/null
    done
}
trap 'cleanup_sessions; _helpers_cleanup' EXIT

# ---------------------------------------------------------------------------
# A) Auto-ping end to end.
# The "agent" session runs `cat` so anything typed into it is appended to a
# file — that's how we detect the ping.
# ---------------------------------------------------------------------------
agent_in="$TMP/agent_in.txt"
: > "$agent_in"
tmux new-session -d -s "$AGENT_A" "bash -c 'cat >> \"$agent_in\"'"
# A clean shell with a simple, static prompt (no user rc / async prompt themes).
tmux new-session -d -s "$TERM_A" "bash --norc --noprofile"
tmux send-keys -t "$TERM_A" "PS1='T\$ '" Enter
sleep 0.4

watch_log="$TMP/term_watch.log"
tmux pipe-pane -o -t "$TERM_A" \
    "AGENT_SESSION='$AGENT_A' AGENT_SUBMIT_DELAY=0 AGENT_AUTOPING=1 COMMENT_PREFIX='#' PING_TRIGGER_FILE='$REPO_ROOT/tmux-agents/ping-trigger.regex' exec '$REPO_ROOT/scripts/term-watch.sh' '$watch_log'"
sleep 0.4

tmux send-keys -t "$TERM_A" "# please do the thing" Enter
got_ping=0
for _ in $(seq 1 40); do
    if grep -q "ping" "$agent_in" 2>/dev/null; then got_ping=1; break; fi
    sleep 0.2
done
assert_eq "1" "$got_ping" "auto-ping: a comment in term pings the agent"

before="$(grep -c "ping" "$agent_in" 2>/dev/null || true)"
tmux send-keys -t "$TERM_A" "echo just-a-command" Enter
sleep 1.2
after="$(grep -c "ping" "$agent_in" 2>/dev/null || true)"
assert_eq "$before" "$after" "auto-ping: a normal command does not ping"

# ---------------------------------------------------------------------------
# B) send.sh captures output in bash; read.sh shows the pane.
# ---------------------------------------------------------------------------
tmux new-session -d -s "$TERM_B" "bash --norc --noprofile"
tmux send-keys -t "$TERM_B" "PS1='S\$ '" Enter
sleep 0.4

out="$(printf 'echo HELLO_$((3+4))\n' | TERM_SESSION="$TERM_B" AGENT_TIMEOUT=20 bash "$REPO_ROOT/scripts/send.sh")"
assert_contains "$out" "HELLO_7" "send.sh: captures command stdout (bash)"

rd="$(TERM_SESSION="$TERM_B" bash "$REPO_ROOT/scripts/read.sh" 200)"
assert_contains "$rd" "HELLO_7" "read.sh: shows the pane content"

# ---------------------------------------------------------------------------
# C) send.sh is shell-agnostic: the SAME script drives a python3 REPL, where the
# old printf/`{ ...; }` wrapping would be a SyntaxError.
# ---------------------------------------------------------------------------
if command -v python3 >/dev/null 2>&1; then
    tmux new-session -d -s "$TERM_PY" "python3 -q"
    sleep 1.2
    outp="$(printf 'print(6*7)\n' | TERM_SESSION="$TERM_PY" AGENT_TIMEOUT=20 bash "$REPO_ROOT/scripts/send.sh")"
    assert_contains "$outp" "42" "send.sh: works in a python3 REPL (shell-agnostic)"

    # C2) Auto-ping in a python3 REPL (`>>> # comment`).
    agent_py="ci_agent_py_$$"
    py_in="$TMP/agent_py_in.txt"
    : > "$py_in"
    tmux new-session -d -s "$agent_py" "bash -c 'cat >> \"$py_in\"'"
    tmux pipe-pane -o -t "$TERM_PY" \
        "AGENT_SESSION='$agent_py' AGENT_SUBMIT_DELAY=0 AGENT_AUTOPING=1 COMMENT_PREFIX='#' PING_TRIGGER_FILE='$REPO_ROOT/tmux-agents/ping-trigger.regex' PING_MIN_INTERVAL=0 exec '$REPO_ROOT/scripts/term-watch.sh' /dev/null"
    sleep 0.4
    tmux send-keys -t "$TERM_PY" "# repl auto-ping please" Enter
    py_ping=0
    for _ in $(seq 1 40); do
        grep -q "ping" "$py_in" 2>/dev/null && { py_ping=1; break; }
        sleep 0.2
    done
    assert_eq "1" "$py_ping" "auto-ping: a '# comment' in python3 REPL pings the agent"
    tmux kill-session -t "$agent_py" 2>/dev/null || true
else
    skip "send.sh python3 REPL test" "python3 not installed"
fi

# ---------------------------------------------------------------------------
# E) say.sh uses echo/print (never #) and does not trigger auto-ping.
# ---------------------------------------------------------------------------
tmux new-session -d -s "${TERM_A}_say" "bash --norc --noprofile"
tmux send-keys -t "${TERM_A}_say" "PS1='Y\$ '" Enter
sleep 0.4
agent_say="${TERM_A}_say_agent"
agent_say_in="$TMP/agent_say_in.txt"
: > "$agent_say_in"
tmux new-session -d -s "$agent_say" "bash -c 'cat >> \"$agent_say_in\"'"
tmux pipe-pane -o -t "${TERM_A}_say" \
    "AGENT_SESSION='$agent_say' AGENT_SUBMIT_DELAY=0 AGENT_AUTOPING=1 COMMENT_PREFIX='#' PING_TRIGGER_FILE='$REPO_ROOT/tmux-agents/ping-trigger.regex' exec '$REPO_ROOT/scripts/term-watch.sh' /dev/null"
sleep 0.4
before_say="$(grep -c "ping" "$agent_say_in" 2>/dev/null || true)"
TERM_SESSION="${TERM_A}_say" AGENT_TIMEOUT=20 bash "$REPO_ROOT/scripts/say.sh" '[agent] working on it'
sleep 1.2
after_say="$(grep -c "ping" "$agent_say_in" 2>/dev/null || true)"
assert_eq "$before_say" "$after_say" "say.sh: status line does not auto-ping"
rd_say="$(TERM_SESSION="${TERM_A}_say" bash "$REPO_ROOT/scripts/read.sh" 80)"
assert_contains "$rd_say" "[agent] working on it" "say.sh: message visible in term"
tmux kill-session -t "${TERM_A}_say" 2>/dev/null || true
tmux kill-session -t "$agent_say" 2>/dev/null || true

# ---------------------------------------------------------------------------
# D) watch.sh can DIAGNOSE and REPAIR a broken watcher. Uses scratch sessions
#    and a temp logs dir so it never touches the real agent/term or repo logs.
# ---------------------------------------------------------------------------
w_in="$TMP/wagent_in.txt"; : > "$w_in"
tmux new-session -d -s "$AGENT_W" "bash -c 'cat >> \"$w_in\"'"
tmux new-session -d -s "$TERM_W" "bash --norc --noprofile"
tmux send-keys -t "$TERM_W" "PS1='W\$ '" Enter
sleep 0.4

# Common env so watch.sh targets the scratch sessions + temp logs.
wenv=(AGENT_SESSION="$AGENT_W" TERM_SESSION="$TERM_W" LOGS_DIR="$TMP/wlogs"
      PING_MIN_INTERVAL=0 AGENT_SUBMIT_DELAY=0
      PING_TRIGGER_FILE="$REPO_ROOT/tmux-agents/ping-trigger.regex")

env "${wenv[@]}" bash "$REPO_ROOT/scripts/watch.sh" reload >/dev/null
assert_eq "1" "$(tmux display-message -pt "$TERM_W" -p '#{pane_pipe}')" \
    "watch.sh reload: attaches the pipe"

st_ok="$(env "${wenv[@]}" bash "$REPO_ROOT/scripts/watch.sh" status || true)"
assert_contains "$st_ok" "HEALTHY" "watch.sh status: reports HEALTHY when piped"

# Auto-ping works after reload.
tmux send-keys -t "$TERM_W" "# please ping now" Enter
w_ping=0
for _ in $(seq 1 40); do
    grep -q "ping" "$w_in" 2>/dev/null && { w_ping=1; break; }
    sleep 0.2
done
assert_eq "1" "$w_ping" "watch.sh reload: auto-ping works again after repair"

# Break the pipe and confirm status detects it.
tmux pipe-pane -t "$TERM_W"; sleep 0.3
st_bad="$(env "${wenv[@]}" bash "$REPO_ROOT/scripts/watch.sh" status || true)"
assert_contains "$st_bad" "BROKEN" "watch.sh status: detects a broken pipe"

# Repair again.
env "${wenv[@]}" bash "$REPO_ROOT/scripts/watch.sh" reload >/dev/null
assert_eq "1" "$(tmux display-message -pt "$TERM_W" -p '#{pane_pipe}')" \
    "watch.sh reload: repairs a broken pipe"

# Regression: reloading an ALREADY-attached watcher must NOT toggle the pipe off.
# (`pipe-pane -o` used to toggle, silently killing auto-ping after a reload.)
env "${wenv[@]}" bash "$REPO_ROOT/scripts/watch.sh" reload >/dev/null 2>&1
assert_eq "1" "$(tmux display-message -pt "$TERM_W" -p '#{pane_pipe}')" \
    "watch.sh reload: reloading a healthy watcher stays attached (no -o toggle)"

# Non-disruptive self-test proves detection+delivery (uses its own scratch agent).
if env "${wenv[@]}" bash "$REPO_ROOT/scripts/watch.sh" selftest >/dev/null 2>&1; then
    assert_eq "ok" "ok" "watch.sh selftest: passes (comment -> ping)"
else
    assert_eq "pass" "fail" "watch.sh selftest: passes (comment -> ping)"
fi

# reload verifies the whole chain and reports VERIFIED when the agent is alive.
rel="$(env "${wenv[@]}" bash "$REPO_ROOT/scripts/watch.sh" reload 2>&1 || true)"
assert_contains "$rel" "VERIFIED working" "watch.sh reload: verifies the full ping chain"

# If the AGENT session is missing, status/reload must FLAG it (silent ping sink).
tmux kill-session -t "$AGENT_W" 2>/dev/null
st_noagent="$(env "${wenv[@]}" bash "$REPO_ROOT/scripts/watch.sh" status 2>&1 || true)"
assert_contains "$st_noagent" "MISSING" "watch.sh status: flags a missing agent session"
if env "${wenv[@]}" bash "$REPO_ROOT/scripts/watch.sh" reload >/dev/null 2>&1; then
    assert_eq "should-fail" "ok" "watch.sh reload: fails when agent session is missing"
else
    assert_eq "ok" "ok" "watch.sh reload: fails when agent session is missing"
fi
