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

cleanup_sessions() {
    for s in "$TERM_A" "$AGENT_A" "$TERM_B" "$TERM_PY"; do
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
    "AGENT_SESSION='$AGENT_A' AGENT_SUBMIT_DELAY=0 AGENT_AUTOPING=1 COMMENT_PREFIX='#' PING_TRIGGER_FILE='$REPO_ROOT/.agents/ping-trigger.regex' exec '$REPO_ROOT/scripts/term-watch.sh' '$watch_log'"
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
else
    skip "send.sh python3 REPL test" "python3 not installed"
fi
