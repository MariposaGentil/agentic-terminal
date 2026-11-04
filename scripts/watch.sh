#!/usr/bin/env bash
# Inspect and repair the `term` pane watcher (the pipe-pane process that logs the
# transcript and auto-pings the agent). Use this when auto-ping stops working.
#
# Why this exists: the watcher is attached to `term` via `tmux pipe-pane`. If the
# pipe is closed/toggled off (e.g. a manual `pipe-pane -o` during development) or
# the watcher process dies, `term` keeps working but auto-ping silently stops.
# start.sh only wires the watcher when it CREATES `term`, so re-running it does
# not repair a live session. This script does.
#
# You can run it straight from the `term` window (it targets tmux by name, so it
# works from anywhere):
#   make reload-watcher            # repair
#   make watch-status              # diagnose
#   bash scripts/watch.sh reload   # repair (explicit path)
#
# Commands:
#   status   Show whether the watcher is healthy (default).
#   reload   Re-attach the watcher AND verify the full ping chain (repairs a
#            broken/missing pipe, reaps duplicate watchers, checks the agent
#            session is alive, and self-tests detection+delivery).
#   selftest Non-disruptively prove a '# comment' is detected and pings the agent.
#   stop     Detach the watcher (turns auto-ping off).
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_tmux

cmd="${1:-status}"

log_age_secs() {
    local target="$1"
    [ -e "$target" ] || { echo "-"; return; }
    local mtime now
    mtime="$(stat -c %Y "$target" 2>/dev/null || stat -f %m "$target" 2>/dev/null || echo 0)"
    now="$(date +%s)"
    echo "$((now - mtime))"
}

print_status() {
    local link="$REPO_ROOT/$LOGS_DIR/${AGENT_SESSION}.current.log"
    local piped pids count healthy="yes"

    if ! tmux has-session -t "$TERM_SESSION" 2>/dev/null; then
        echo "[agentic-terminal] watcher status"
        echo "  term session '$TERM_SESSION' : NOT running"
        echo "  verdict                       : DOWN (run 'make start')"
        return 1
    fi

    piped="$(term_is_piped)"
    pids="$(watcher_pids)"
    count="$(printf '%s\n' "$pids" | grep -c . || true)"
    local agent_ok="no"; agent_session_alive && agent_ok="yes"

    echo "[agentic-terminal] watcher status"
    echo "  term session '$TERM_SESSION' : running"
    echo "  agent session '$AGENT_SESSION'  : $([ "$agent_ok" = yes ] && echo running || echo 'MISSING (pings vanish)')"
    echo "  pipe-pane attached            : $([ "$piped" = "1" ] && echo yes || echo no)"
    echo "  watcher process(es)           : ${count} ${pids:+[$(echo $pids | tr '\n' ' ')]}"
    echo "  auto-ping (AGENT_AUTOPING)    : ${AGENT_AUTOPING}"
    if [ -L "$link" ] || [ -e "$link" ]; then
        echo "  current transcript            : $link -> $(readlink "$link" 2>/dev/null || echo '?')"
        echo "  last transcript write         : $(log_age_secs "$link")s ago"
    else
        echo "  current transcript            : (none)"
    fi

    [ "$piped" = "1" ] || healthy="no"
    [ "${count:-0}" -ge 1 ] 2>/dev/null || healthy="no"
    [ "$agent_ok" = "yes" ] || healthy="no"
    [ "${count:-0}" -gt 1 ] 2>/dev/null && { echo "  note                          : ${count} watchers (duplicates) -> run 'make reload-watcher'"; healthy="no"; }
    if [ "$healthy" = "yes" ]; then
        echo "  verdict                       : HEALTHY"
        return 0
    fi
    echo "  verdict                       : BROKEN -> run 'make reload-watcher'"
    return 1
}

# Verify the full ping chain after a (re)attach. Prints PASS/FAIL lines and
# returns non-zero if anything is wrong.
verify_ping_chain() {
    local ok=0
    if [ "$(term_is_piped)" = "1" ]; then
        echo "  [PASS] pipe-pane attached to '$TERM_SESSION'"
    else
        echo "  [FAIL] pipe-pane NOT attached to '$TERM_SESSION'"; ok=1
    fi

    local count; count="$(watcher_pids | grep -c . || true)"
    if [ "${count:-0}" -ge 1 ]; then
        echo "  [PASS] watcher process running (${count})"
        [ "${count}" -gt 1 ] && echo "  [WARN] more than one watcher attached; a duplicate can cause extra pings"
    else
        echo "  [FAIL] no watcher process running"; ok=1
    fi

    if agent_session_alive; then
        echo "  [PASS] agent session '$AGENT_SESSION' is running (ping target reachable)"
    else
        echo "  [FAIL] agent session '$AGENT_SESSION' is MISSING -> pings go nowhere. Start it (make start)."; ok=1
    fi

    case "$(selftest_ping_path; echo $?)" in
        *0) echo "  [PASS] self-test: a '# comment' is detected and a ping is delivered" ;;
        *2) echo "  [WARN] self-test skipped (could not create a scratch tmux session)" ;;
        *)  echo "  [FAIL] self-test: a canonical '# comment' did NOT produce a ping (check $(ping_trigger_path))"; ok=1 ;;
    esac
    return "$ok"
}

case "$cmd" in
    status)
        print_status
        ;;
    reload|repair|restart)
        require_term_session
        # Snapshot pre-existing watchers so we can reap strays after replacing the
        # pipe (replacing already EOFs the live one; this mops up any leftovers,
        # so we always end with exactly ONE watcher).
        old_pids="$(watcher_pids)"
        attach_watcher "reloaded"
        sleep 0.4
        for p in $old_pids; do kill "$p" 2>/dev/null || true; done
        # Wait for reaped strays to actually leave the process table so the
        # verification below sees a single watcher.
        for _ in 1 2 3 4 5 6 7 8; do
            [ "$(watcher_pids | grep -c . || true)" -le 1 ] && break
            sleep 0.2
        done

        echo "[agentic-terminal] Watcher re-attached to '$TERM_SESSION'."
        echo "  transcript : $WATCHER_LOG"
        echo "  pointer    : $WATCHER_LINK"
        configure_term_status_bar
        echo "[agentic-terminal] Verifying the ping chain..."
        if verify_ping_chain; then
            echo "[agentic-terminal] RESULT: auto-ping VERIFIED working."
            echo "  Tip: type your prompt as a clean comment line, e.g.  # run the tests"
            echo "       (a space after '#'; don't glue it onto a command like 'ls# ...')."
        else
            echo "[agentic-terminal] RESULT: auto-ping is NOT fully working -- see [FAIL] lines above." >&2
            exit 1
        fi
        ;;
    selftest)
        # Non-disruptive: proves detection+delivery via a scratch agent session.
        if selftest_ping_path; then
            echo "[agentic-terminal] self-test PASSED: a '# comment' is detected and pings the agent."
        else
            echo "[agentic-terminal] self-test FAILED: check $(ping_trigger_path)." >&2
            exit 1
        fi
        ;;
    stop)
        require_term_session
        tmux pipe-pane -t "$TERM_SESSION"   # no command => close the pipe
        for p in $(watcher_pids); do kill "$p" 2>/dev/null || true; done
        echo "[agentic-terminal] Watcher detached from '$TERM_SESSION' (auto-ping off). Re-enable with: make reload-watcher"
        ;;
    -h|--help|help)
        sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        echo "[agentic-terminal] Unknown command: $cmd" >&2
        echo "Usage: watch.sh [status|reload|selftest|stop]" >&2
        exit 2
        ;;
esac
