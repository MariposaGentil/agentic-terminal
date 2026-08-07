# Shared helpers for the agentic-terminal test suite. Sourced by each test_*.sh.
# No external test framework is required — just bash.
set -o pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

TESTS_PASSED=0
TESTS_FAILED=0

# Per-test scratch space and a dir to hold stub executables (e.g. a fake tmux).
TMP="$(mktemp -d)"
BIN="$TMP/bin"
mkdir -p "$BIN"

_helpers_cleanup() {
    rm -rf "$TMP" 2>/dev/null || true
    [ "$TESTS_FAILED" -gt 0 ] && exit 1
    exit 0
}
trap _helpers_cleanup EXIT

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf '  ok   %s\n' "$1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL %s\n' "$1"
    [ -n "${2:-}" ] && printf '       -> %s\n' "$2"
    return 0
}

assert_eq() { # expected actual message
    if [ "$1" = "$2" ]; then pass "$3"; else fail "$3" "expected [$1] got [$2]"; fi
}

assert_contains() { # haystack needle message
    case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "output missing [$2]" ;; esac
}

assert_not_contains() { # haystack needle message
    case "$1" in *"$2"*) fail "$3" "output unexpectedly contains [$2]" ;; *) pass "$3" ;; esac
}

skip() { printf '  skip %s%s\n' "$1" "${2:+ ($2)}"; }

# Install a fake `tmux` in $BIN that just records its arguments to a log file.
# Useful for asserting which tmux commands a script issued.
make_recording_tmux() { # logfile
    cat > "$BIN/tmux" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$1"
EOF
    chmod +x "$BIN/tmux"
}
