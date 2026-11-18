# prompt-work.sh: one BEGIN/DONE pair per task; send.sh uses SEND markers only.
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

PW="$REPO_ROOT/scripts/prompt-work.sh"
SEND="$REPO_ROOT/scripts/send.sh"

if ! command -v tmux >/dev/null 2>&1; then
    skip "prompt-work" "tmux not installed"
    exit 0
fi

TERM_PW="at_pw_$$"
STATE="${TMPDIR:-/tmp}/agentic_terminal_${TERM_PW}_prompt_work"
export TERM_SESSION="$TERM_PW"
export PROMPT_WORK_STATE="$STATE"

tmux kill-session -t "$TERM_PW" 2>/dev/null || true
tmux new-session -d -s "$TERM_PW" -c "$REPO_ROOT" bash --noprofile --norc
sleep 0.3

rm -f "$STATE"
bash "$PW" begin
if [ -f "$STATE" ]; then pass "prompt-work begin: records active run_id"; else fail "prompt-work begin: records active run_id" "state file missing"; fi
run1="$(cat "$STATE" 2>/dev/null || true)"

bash "$PW" begin
run2="$(cat "$STATE" 2>/dev/null || true)"
assert_eq "$run1" "$run2" "prompt-work begin: idempotent while active"

pane_begin="$(tmux capture-pane -pt "$TERM_PW" 2>/dev/null || true)"
assert_contains "$pane_begin" "BEGIN ${run1}" "prompt-work begin: types BEGIN in term"
assert_contains "$pane_begin" "session:[" "prompt-work begin: includes session id"

bash "$PW" done
if [ ! -f "$STATE" ]; then pass "prompt-work done: clears state file"; else fail "prompt-work done: clears state file" "state still present"; fi
pane_done="$(tmux capture-pane -pt "$TERM_PW" 2>/dev/null || true)"
assert_contains "$pane_done" "DONE ${run1}" "prompt-work done: types matching DONE"

TERM_SEND="at_send_$$"
tmux kill-session -t "$TERM_SEND" 2>/dev/null || true
tmux new-session -d -s "$TERM_SEND" -c "$REPO_ROOT" bash --noprofile --norc
sleep 0.3
out="$(printf 'echo PW_OK\n' | TERM_SESSION="$TERM_SEND" AGENT_TIMEOUT=20 bash "$SEND")"
assert_contains "$out" "PW_OK" "send.sh still captures output"
pane_send="$(tmux capture-pane -pt "$TERM_SEND" 2>/dev/null || true)"
assert_contains "$pane_send" "SEND BEGIN" "send.sh: types SEND BEGIN in term"
assert_contains "$pane_send" "SEND DONE" "send.sh: types SEND DONE in term"
case "$pane_send" in
    *"SEND BEGIN"*"session:["*|*"SEND DONE"*"session:["*)
        fail "send.sh: SEND markers do not carry session id" "found session on SEND line"
        ;;
    *) pass "send.sh: SEND markers do not carry session id" ;;
esac
tmux kill-session -t "$TERM_SEND" 2>/dev/null || true

tmux kill-session -t "$TERM_PW" 2>/dev/null || true
rm -f "$STATE"
