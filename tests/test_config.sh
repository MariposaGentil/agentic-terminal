# Config defaults: sourcing config.sh yields the documented defaults, and env
# overrides win.
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

# Defaults (source in a clean subshell so our env doesn't leak in).
eval "$(env -i bash -c "source '$REPO_ROOT/scripts/config.sh' >/dev/null 2>&1; \
    printf 'D_AGENT_MODEL=%q\n' \"\$AGENT_MODEL\"; \
    printf 'D_AGENT_ARGS=%q\n' \"\$AGENT_ARGS\"; \
    printf 'D_AGENT_SESSION=%q\n' \"\$AGENT_SESSION\"; \
    printf 'D_TERM_SESSION=%q\n' \"\$TERM_SESSION\"; \
    printf 'D_COMMENT_PREFIX=%q\n' \"\$COMMENT_PREFIX\"; \
    printf 'D_SEND_MARKER=%q\n' \"\$SEND_MARKER\"; \
    printf 'D_AGENT_AUTOPING=%q\n' \"\$AGENT_AUTOPING\"; \
    printf 'D_PING_TRIGGER_FILE=%q\n' \"\$PING_TRIGGER_FILE\"; \
    printf 'D_AGENT_CAPS_DIR=%q\n' \"\$AGENT_CAPS_DIR\"; \
    printf 'D_AGENT_RULES_DIR=%q\n' \"\$AGENT_RULES_DIR\"; \
    printf 'D_AGENT_PROMPT_FILE=%q\n' \"\$AGENT_PROMPT_FILE\"; \
    printf 'D_TERM_ATTACH=%q\n' \"\$TERM_ATTACH\"; \
    printf 'D_AGENT_ATTACH=%q\n' \"\$AGENT_ATTACH\"; \
    printf 'D_AGENT_PROMPT_WAIT=%q\n' \"\$AGENT_PROMPT_WAIT\"; \
    printf 'D_AGENT_IDLE_STABLE=%q\n' \"\$AGENT_IDLE_STABLE\"; \
    printf 'D_AGENT_READY_WAIT=%q\n' \"\$AGENT_READY_WAIT\"; \
    printf 'D_AGENT_SUBMIT_DELAY=%q\n' \"\$AGENT_SUBMIT_DELAY\"; \
    printf 'D_AGENT_STATUS_BAR=%q\n' \"\$AGENT_STATUS_BAR\"; \
    printf 'D_AGENT_STATUS_INTERVAL=%q\n' \"\$AGENT_STATUS_INTERVAL\"; \
    printf 'D_LOG_RETENTION_DAYS=%q\n' \"\$LOG_RETENTION_DAYS\"; \
    printf 'D_LOGS_DIR=%q\n' \"\$LOGS_DIR\"")"

# A model is set by default (so start.sh appends --model). The exact value is a
# user preference, not a behavioral contract, so we only assert it's non-empty.
[ -n "$D_AGENT_MODEL" ] && pass "a default AGENT_MODEL is set" \
    || fail "a default AGENT_MODEL is set"
assert_eq "--auto-review" "$D_AGENT_ARGS" "default AGENT_ARGS is --auto-review (no per-command prompts)"
assert_eq "agent" "$D_AGENT_SESSION" "default AGENT_SESSION is 'agent'"
assert_eq "term" "$D_TERM_SESSION" "default TERM_SESSION is 'term'"
assert_eq "#" "$D_COMMENT_PREFIX" "default COMMENT_PREFIX is '#'"
assert_eq ": AT:" "$D_SEND_MARKER" "default SEND_MARKER is ': AT:'"
assert_eq "1" "$D_AGENT_AUTOPING" "auto-ping is on by default"
assert_eq "tmux-agents/ping-trigger.regex" "$D_PING_TRIGGER_FILE" "default PING_TRIGGER_FILE path"
assert_eq "tmux-agents" "$D_AGENT_CAPS_DIR" "default AGENT_CAPS_DIR is 'tmux-agents'"
assert_eq "tmux-agents/rules" "$D_AGENT_RULES_DIR" "default AGENT_RULES_DIR is 'tmux-agents/rules'"
assert_eq "tmux-agents/agent-prompt.md" "$D_AGENT_PROMPT_FILE" "default AGENT_PROMPT_FILE path"
assert_eq "emulator" "$D_TERM_ATTACH" "default TERM_ATTACH opens term in a new window"
assert_eq "current" "$D_AGENT_ATTACH" "default AGENT_ATTACH attaches the launching terminal to the agent"
assert_eq "7" "$D_LOG_RETENTION_DAYS" "default log retention is 7 days"
assert_eq "logs" "$D_LOGS_DIR" "default LOGS_DIR is 'logs'"
assert_eq "90" "$D_AGENT_PROMPT_WAIT" "default AGENT_PROMPT_WAIT waits for the initial prompt"
assert_eq "4" "$D_AGENT_IDLE_STABLE" "default AGENT_IDLE_STABLE marks idle after 4s unchanged"
assert_eq "4" "$D_AGENT_READY_WAIT" "agent gets 4s to boot before the kickoff is typed"
assert_eq "1" "$D_AGENT_STATUS_BAR" "agent status bar is on by default"
assert_eq "1" "$D_AGENT_STATUS_INTERVAL" "status bar refreshes every 1s by default"

# START_COUNTDOWN was removed: the agent-ready wait is the only blocking point.
if grep -q 'START_COUNTDOWN' "$REPO_ROOT/scripts/config.sh"; then
    fail "START_COUNTDOWN is gone from config.sh (replaced by the agent-ready wait)"
else
    pass "START_COUNTDOWN is gone from config.sh (replaced by the agent-ready wait)"
fi

# The blocking wait must be able to skip (open term immediately) via env.
wait_override="$(AGENT_PROMPT_WAIT=0 bash -c "source '$REPO_ROOT/scripts/config.sh' >/dev/null 2>&1; printf '%s' \"\$AGENT_PROMPT_WAIT\"")"
assert_eq "0" "$wait_override" "AGENT_PROMPT_WAIT can be overridden via env (0 opens term immediately)"

# Env override wins.
override="$(AGENT_CMD=claude bash -c "source '$REPO_ROOT/scripts/config.sh' >/dev/null 2>&1; printf '%s' \"\$AGENT_CMD\"")"
assert_eq "claude" "$override" "AGENT_CMD can be overridden via env"

model_override="$(AGENT_MODEL=opus bash -c "source '$REPO_ROOT/scripts/config.sh' >/dev/null 2>&1; printf '%s' \"\$AGENT_MODEL\"")"
assert_eq "opus" "$model_override" "AGENT_MODEL can be overridden via env"

# The default trigger regex file exists and its first active line is a regex.
active="$(grep -vE '^[[:space:]]*(##|$)' "$REPO_ROOT/tmux-agents/ping-trigger.regex" | head -n1)"
[ -n "$active" ] && pass "ping-trigger.regex has an active (non-##) pattern line" \
    || fail "ping-trigger.regex has an active (non-##) pattern line"
