# Config defaults: sourcing config.sh yields the documented defaults, and env
# overrides win.
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

# Defaults (source in a clean subshell so our env doesn't leak in).
eval "$(env -i bash -c "source '$REPO_ROOT/scripts/config.sh' >/dev/null 2>&1; \
    printf 'D_AGENT_MODEL=%q\n' \"\$AGENT_MODEL\"; \
    printf 'D_AGENT_SESSION=%q\n' \"\$AGENT_SESSION\"; \
    printf 'D_TERM_SESSION=%q\n' \"\$TERM_SESSION\"; \
    printf 'D_COMMENT_PREFIX=%q\n' \"\$COMMENT_PREFIX\"; \
    printf 'D_AGENT_AUTOPING=%q\n' \"\$AGENT_AUTOPING\"; \
    printf 'D_PING_TRIGGER_FILE=%q\n' \"\$PING_TRIGGER_FILE\"; \
    printf 'D_TERM_ATTACH=%q\n' \"\$TERM_ATTACH\"; \
    printf 'D_AGENT_ATTACH=%q\n' \"\$AGENT_ATTACH\"; \
    printf 'D_LOG_RETENTION_DAYS=%q\n' \"\$LOG_RETENTION_DAYS\"; \
    printf 'D_LOGS_DIR=%q\n' \"\$LOGS_DIR\"")"

assert_eq "composer" "$D_AGENT_MODEL" "default AGENT_MODEL is 'composer'"
assert_eq "agent" "$D_AGENT_SESSION" "default AGENT_SESSION is 'agent'"
assert_eq "term" "$D_TERM_SESSION" "default TERM_SESSION is 'term'"
assert_eq "#" "$D_COMMENT_PREFIX" "default COMMENT_PREFIX is '#'"
assert_eq "1" "$D_AGENT_AUTOPING" "auto-ping is on by default"
assert_eq ".agents/ping-trigger.regex" "$D_PING_TRIGGER_FILE" "default PING_TRIGGER_FILE path"
assert_eq "emulator" "$D_TERM_ATTACH" "default TERM_ATTACH opens term in a new window"
assert_eq "current" "$D_AGENT_ATTACH" "default AGENT_ATTACH attaches agent in the current terminal"
assert_eq "7" "$D_LOG_RETENTION_DAYS" "default log retention is 7 days"
assert_eq "logs" "$D_LOGS_DIR" "default LOGS_DIR is 'logs'"

# Env override wins.
override="$(AGENT_CMD=claude bash -c "source '$REPO_ROOT/scripts/config.sh' >/dev/null 2>&1; printf '%s' \"\$AGENT_CMD\"")"
assert_eq "claude" "$override" "AGENT_CMD can be overridden via env"

model_override="$(AGENT_MODEL=opus bash -c "source '$REPO_ROOT/scripts/config.sh' >/dev/null 2>&1; printf '%s' \"\$AGENT_MODEL\"")"
assert_eq "opus" "$model_override" "AGENT_MODEL can be overridden via env"

# The default trigger regex file exists and its first active line is a regex.
active="$(grep -vE '^[[:space:]]*(##|$)' "$REPO_ROOT/.agents/ping-trigger.regex" | head -n1)"
[ -n "$active" ] && pass "ping-trigger.regex has an active (non-##) pattern line" \
    || fail "ping-trigger.regex has an active (non-##) pattern line"
