# Comment-prompt collection: requests.sh scrapes the pane, extracts comment
# lines typed at a prompt, and marks them processed so pokes don't repeat them.
# tmux is stubbed to return a canned pane snapshot.
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

REQ="$REPO_ROOT/scripts/requests.sh"
export TMPDIR="$TMP"          # so COMMENT_STATE lives in our scratch dir
export TERM_SESSION="reqtest"
FIXTURE="$TMP/pane.txt"

# Stub tmux: succeed for has-session; print the fixture for capture-pane.
cat > "$BIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
    has-session) exit 0 ;;
    capture-pane) cat "$FIXTURE" ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$BIN/tmux"

cat > "$FIXTURE" <<'EOF'
T$ # first task
T$ ls -la
total 0
T$ # second task
EOF

out1="$(PATH="$BIN:$PATH" bash "$REQ")"
assert_contains "$out1" "[1] first task" "requests: returns the first comment"
assert_contains "$out1" "[2] second task" "requests: returns the second comment"
assert_not_contains "$out1" "ls -la" "requests: ignores non-comment commands"

# Second poke with no new comments -> nothing new.
out2="$(PATH="$BIN:$PATH" bash "$REQ")"
assert_contains "$out2" "No new comment requests" "requests: does not resurface processed comments"

# A newly typed comment shows up on the next poke.
printf 'T$ # third task\n' >> "$FIXTURE"
out3="$(PATH="$BIN:$PATH" bash "$REQ")"
assert_contains "$out3" "[3] third task" "requests: surfaces a newly typed comment"
assert_not_contains "$out3" "first task" "requests: only new comments are returned"

# A comment typed at a THEMED/POWERLINE prompt (ends in a U+E0B0 glyph, not
# $/#/>) must still be extracted.
printf ' \xee\x82\xb0 # fourth task\n' >> "$FIXTURE"
out4="$(PATH="$BIN:$PATH" bash "$REQ")"
assert_contains "$out4" "[4] fourth task" "requests: extracts a comment after a powerline prompt"
