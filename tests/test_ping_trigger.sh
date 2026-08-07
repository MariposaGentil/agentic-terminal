# Auto-ping detection: term-watch.sh reads the pane stream, logs a cleaned
# transcript, and pings the agent when a line matches the trigger regex.
# tmux is stubbed so we can assert exactly when a ping is issued.
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

WATCH="$REPO_ROOT/scripts/term-watch.sh"
DEFAULT_RE="$REPO_ROOT/tmux-agents/ping-trigger.regex"

STUB_LOG=""
TRANS=""

# run_watch <regex_file> <autoping> <line>...
run_watch() {
    local regex_file="$1" autoping="$2"
    shift 2
    STUB_LOG="$TMP/tmux_calls.$RANDOM"
    TRANS="$TMP/transcript.$RANDOM"
    : > "$STUB_LOG"
    : > "$TRANS"
    make_recording_tmux "$STUB_LOG"
    # PING_MIN_INTERVAL defaults to 0 here so these tests can count one ping per
    # matching line; the rate-limit behavior is covered by its own test below.
    printf '%s\n' "$@" | PATH="$BIN:$PATH" \
        AGENT_SESSION=agent TERM_SESSION=term AGENT_SUBMIT_DELAY=0 AGENT_AUTOPING="$autoping" \
        COMMENT_PREFIX='#' PING_TRIGGER_FILE="$regex_file" \
        PING_MIN_INTERVAL="${PING_MIN_INTERVAL_OVERRIDE:-0}" \
        bash "$WATCH" "$TRANS"
    sleep 0.2  # let the backgrounded Enter keystroke land
}

pings() { grep -c -- '-l ping' "$STUB_LOG" 2>/dev/null; }

# 1) Default regex: a comment typed at a shell prompt pings; a normal command
#    and a '#' appearing in mid-output do not.
run_watch "$DEFAULT_RE" 1 \
    'user@host:/tmp$ # run the tests' \
    'user@host:/tmp$ ls -la' \
    'total 0 items # trailing hash in output'
assert_eq "1" "$(pings)" "default: exactly one ping (only the prompt comment)"
assert_contains "$(cat "$TRANS")" "# run the tests" "transcript records the comment line"
assert_contains "$(cat "$TRANS")" "ls -la" "transcript records normal commands too"

# 2) ANSI escape codes are stripped from the transcript (and matching still works).
run_watch "$DEFAULT_RE" 1 "$(printf '\x1b[0;32muser@host\x1b[0m:/tmp$ # colored comment')"
assert_eq "1" "$(pings)" "ansi: still pings on a colored prompt line"
assert_contains "$(cat "$TRANS")" "# colored comment" "ansi: comment text kept in transcript"
assert_not_contains "$(cat "$TRANS")" "$(printf '\x1b')" "ansi: escape codes stripped from transcript"

# 3) Configurable regex: an IPython-style pattern from a different file.
IPY_RE="$TMP/ipython.regex"
printf '## IPython trigger\n^In \\[[0-9]+\\]:[[:space:]]*#\n' > "$IPY_RE"
run_watch "$IPY_RE" 1 'In [3]: # summarize failures' 'In [4]: x = 1'
assert_eq "1" "$(pings)" "ipython regex: pings on 'In [n]: #', not on code"

# 4) Auto-ping disabled: no ping, but the transcript is still written.
run_watch "$DEFAULT_RE" 0 'user@host:/tmp$ # should not ping'
assert_eq "0" "$(pings)" "autoping=0: no ping is sent"
assert_contains "$(cat "$TRANS")" "# should not ping" "autoping=0: transcript still logged"

# 5) Two distinct comments -> two pings.
run_watch "$DEFAULT_RE" 1 'u$ # first' 'u$ echo x' 'u$ # second'
assert_eq "2" "$(pings)" "two distinct comments produce two pings"

# 6) The agent's own send.sh marker lines must NOT trigger a ping (no self-ping).
run_watch "$DEFAULT_RE" 1 \
    'u$ : AT: BEGIN 12345 session:[abc]' \
    'u$ echo hello' \
    'u$ : AT: DONE 12345'
assert_eq "0" "$(pings)" "agent's own : AT: lines do not self-ping"

# 6b) A HUMAN comment merged onto the same line as a marker (as happens when an
#     IPython prompt redraws) MUST still ping — the marker is stripped, not the
#     whole line. Regression for "had to type the comment twice".
run_watch "$DEFAULT_RE" 1 \
    'In [27]: : AT: DONE 748099051 leftover textIn [27]: # print it here'
assert_eq "1" "$(pings)" "human comment merged with a marker still pings"

# 6c) A marker with trailing garbage but NO human comment must NOT ping.
run_watch "$DEFAULT_RE" 1 \
    'In [31]: : AT: DONE 7611624447In [31]: : AT: DONE 7611624447'
assert_eq "0" "$(pings)" "marker-only line (even mangled) does not ping"

# 6d) Welcome-style `:` lines (not `#` comments) must not trigger auto-ping.
run_watch "$DEFAULT_RE" 1 \
    'u$ : ── agentic-terminal ──' \
    'u$ : Detach (leave running):  Ctrl-b  then  d'
assert_eq "0" "$(pings)" "welcome banner : lines do not auto-ping"

# 6e) REPL-style `# AT:` markers (Python/IPython) must not self-ping.
run_watch "$DEFAULT_RE" 1 \
    '>>> # AT: BEGIN 12345 session:[abc]' \
    '>>> print(1)' \
    '>>> # AT: DONE 12345'
assert_eq "0" "$(pings)" "agent's own # AT: REPL markers do not self-ping"

# 7) Rate-limit: a burst of matches within PING_MIN_INTERVAL collapses to ONE
#    ping. This is what prevents the agent receiving a merged "pingping".
PING_MIN_INTERVAL_OVERRIDE=60 run_watch "$DEFAULT_RE" 1 \
    'u$ # first' 'u$ # second' 'u$ # third'
assert_eq "1" "$(pings)" "rate-limit collapses a burst of pings into one (no pingping)"

# 7b) Ping ack: a tmux status message is shown in term when a ping is sent.
run_watch "$DEFAULT_RE" 1 'u$ # ack test'
assert_contains "$(cat "$STUB_LOG")" "display-message" "ping ack: flashes status in term"

# 8) Shared regex loader (used by term-watch.sh AND watch.sh) is consistent.
source "$REPO_ROOT/scripts/_ping_regex.sh"
DEF_RE="$(load_ping_regex '#' '')"                        # no file -> built-in default
matches() { printf '%s' "$1" | grep -qE -- "$DEF_RE" && echo yes || echo no; }
assert_eq "yes" "$(matches 'erik@h:~$ # do it')" "loader default matches a shell-prompt comment"
assert_eq "no"  "$(matches 'ls -la')"            "loader default ignores a normal command"
assert_eq "no"  "$(matches 'watch-status# glued')" "loader default ignores a '#' glued to a word"
FILE_RE="$(load_ping_regex '#' "$DEFAULT_RE")"           # from the repo regex file
assert_eq "$(cat "$DEFAULT_RE" | grep -vE '^[[:space:]]*(##|$)' | head -n1)" "$FILE_RE" \
    "loader uses the first active line of the trigger file"
