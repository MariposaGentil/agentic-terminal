#!/usr/bin/env bash
# One-time setup for agentic-terminal: verify prerequisites, make the toolkit
# executable, and confirm the configured agent is available.
#
# Usage:
#   scripts/setup.sh                 # check only
#   scripts/setup.sh --install-deps  # also try to apt-install missing deps
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

INSTALL_DEPS=0
[ "${1:-}" = "--install-deps" ] && INSTALL_DEPS=1

ok=0
fail=0
say_ok()   { echo "[setup]  ok   $1"; ok=$((ok + 1)); }
say_warn() { echo "[setup]  warn $1"; }
say_fail() { echo "[setup]  FAIL $1"; fail=$((fail + 1)); }

install_apt() {
    # $1 = package name; returns 0 on success.
    if command -v apt-get >/dev/null 2>&1; then
        echo "[setup] Installing '$1' via apt-get..."
        sudo apt-get update -y && sudo apt-get install -y "$1"
    else
        echo "[setup] apt-get not available; install '$1' manually." >&2
        return 1
    fi
}

echo "[setup] agentic-terminal setup starting..."

# --- 1. tmux ----------------------------------------------------------------
if command -v tmux >/dev/null 2>&1; then
    say_ok "tmux found ($(tmux -V))"
elif [ "$INSTALL_DEPS" -eq 1 ] && install_apt tmux; then
    say_ok "tmux installed ($(tmux -V))"
else
    say_fail "tmux not found. Install it: sudo apt install tmux  (or re-run with --install-deps)"
fi

# --- 2. Make the toolkit executable ----------------------------------------
if chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null; then
    say_ok "scripts/ marked executable"
else
    say_warn "could not chmod scripts/ (continuing)"
fi

# --- 3. Configured agent ----------------------------------------------------
agent_bin="${AGENT_CMD%% *}"   # first word of AGENT_CMD (drop any args)
if command -v "$agent_bin" >/dev/null 2>&1; then
    say_ok "agent '$agent_bin' found on PATH (AGENT_CMD='$AGENT_CMD')"
else
    say_warn "agent '$agent_bin' not found on PATH. Install it or set AGENT_CMD in scripts/config.sh."
fi

# --- 4. Terminal emulator (optional) ---------------------------------------
term_bin="${TERMINAL_EMULATOR%% *}"
if command -v "$term_bin" >/dev/null 2>&1; then
    say_ok "terminal emulator '$term_bin' found"
else
    say_warn "terminal emulator '$term_bin' not found. Set TERMINAL_EMULATOR in scripts/config.sh, or attach manually with: tmux attach -t $TERM_SESSION"
fi

echo
echo "[setup] Summary: $ok ok, $fail failed."
if [ "$fail" -gt 0 ]; then
    echo "[setup] Resolve the FAIL items above, then re-run scripts/setup.sh." >&2
    exit 1
fi

echo "[setup] Done. Next: run 'scripts/start.sh' to launch the agent + terminal."
