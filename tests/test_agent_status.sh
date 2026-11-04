# Agent busy/free status for the term tmux status bar.
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

STATUS="$REPO_ROOT/scripts/agent-status.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/scripts/_agent_status.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/scripts/_common.sh"

# --- unit: state classification with a recording/stub tmux -------------------
STUB_LOG="$TMP/tmux_status.$RANDOM"
: > "$STUB_LOG"

# Offline when has-session fails.
cat > "$BIN/tmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "has-session" ]; then exit 1; fi
printf '%s\n' "\$*" >> "$STUB_LOG"
exit 0
EOF
chmod +x "$BIN/tmux"

out="$(PATH="$BIN:$PATH" AGENT_STATUS_PLAIN=1 AGENT_SESSION=agent bash "$STATUS")"
assert_eq "offline" "$out" "agent-status: offline when agent session missing"

# Busy when capture-pane shows a spinner / Thinking.
cat > "$BIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
    has-session) exit 0 ;;
    capture-pane)
        printf '%s\n' 'Thinking about the request...'
        printf '%s\n' '⠋ Running tool'
        exit 0
        ;;
esac
printf '%s\n' "\$*" >> "$STUB_LOG"
exit 0
EOF
chmod +x "$BIN/tmux"
out="$(PATH="$BIN:$PATH" AGENT_STATUS_PLAIN=1 AGENT_SESSION=agent bash "$STATUS")"
assert_eq "busy" "$out" "agent-status: busy when Thinking/spinner visible"

# Free when idle prompt text only.
cat > "$BIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
    has-session) exit 0 ;;
    capture-pane)
        printf '%s\n' 'Agent bootstrap complete.'
        printf '%s\n' '→ Add a follow-up'
        exit 0
        ;;
esac
exit 0
EOF
chmod +x "$BIN/tmux"
out="$(PATH="$BIN:$PATH" AGENT_STATUS_PLAIN=1 AGENT_SESSION=agent bash "$STATUS")"
assert_eq "free" "$out" "agent-status: free when idle"

# Queued when defer lock is alive and agent is not busy.
lock="$(PATH="$BIN:$PATH" AGENT_SESSION=agent bash -c 'source "'"$REPO_ROOT"'/scripts/_agent_status.sh"; agent_ping_defer_lock')"
sleep 30 &
keeper=$!
printf '%s' "$keeper" > "$lock"
out="$(PATH="$BIN:$PATH" AGENT_STATUS_PLAIN=1 AGENT_SESSION=agent bash "$STATUS")"
assert_eq "queued" "$out" "agent-status: queued when ping defer lock is held"
kill "$keeper" 2>/dev/null || true
rm -f "$lock"

# Coloured tmux fragment (default mode) contains BUSY marker.
cat > "$BIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
    has-session) exit 0 ;;
    capture-pane) printf '%s\n' 'Generating response…'; exit 0 ;;
esac
exit 0
EOF
chmod +x "$BIN/tmux"
out="$(PATH="$BIN:$PATH" AGENT_SESSION=agent bash "$STATUS")"
assert_contains "$out" "BUSY" "agent-status: tmux fragment includes BUSY"
assert_contains "$out" "#[" "agent-status: tmux fragment includes colour codes"

# --- configure_term_status_bar wires status-right to agent-status.sh ----------
STUB_LOG="$TMP/tmux_cfg.$RANDOM"
: > "$STUB_LOG"
make_recording_tmux "$STUB_LOG"
# has-session must succeed for configure to proceed
cat > "$BIN/tmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "has-session" ]; then exit 0; fi
printf '%s\n' "\$*" >> "$STUB_LOG"
exit 0
EOF
chmod +x "$BIN/tmux"

TERM_SESSION=term AGENT_SESSION=agent AGENT_STATUS_BAR=1 AGENT_STATUS_INTERVAL=2 \
    PATH="$BIN:$PATH" bash -c '
        source "'"$REPO_ROOT"'/scripts/_common.sh"
        configure_term_status_bar
    '
cfg="$(cat "$STUB_LOG")"
assert_contains "$cfg" "status on" "status bar: enables status"
assert_contains "$cfg" "status-interval 2" "status bar: uses AGENT_STATUS_INTERVAL"
assert_contains "$cfg" "agent-status.sh" "status bar: status-right runs agent-status.sh"
assert_contains "$cfg" "status-right" "status bar: sets status-right"

# Disabled via AGENT_STATUS_BAR=0
: > "$STUB_LOG"
TERM_SESSION=term AGENT_STATUS_BAR=0 PATH="$BIN:$PATH" bash -c '
    source "'"$REPO_ROOT"'/scripts/_common.sh"
    configure_term_status_bar
'
assert_eq "" "$(cat "$STUB_LOG")" "status bar: AGENT_STATUS_BAR=0 is a no-op"
