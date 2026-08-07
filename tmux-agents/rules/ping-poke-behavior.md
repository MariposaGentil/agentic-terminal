# Rule: `ping` poke behavior

When you receive a prompt that is **exactly** the single word `ping` (and nothing
else), treat it as a status-refresh poke — do **not** treat it as a task. On
`ping`:

1. Run `scripts/read.sh` to re-read the current state of `term` (latest input
   and output).
2. Run `scripts/requests.sh` to scan the comment lines for any new `#` prompts.
3. **Echo pending prompts first.** If `requests.sh` returned any tasks, print
   them immediately as your first output (numbered list, verbatim text) before
   doing anything else — so a developer watching the `agent` session sees what
   triggered this poke. If there are none, say so briefly.
4. Update your understanding of the current status from what you just read.
5. If there are new prompts, act on them (see the loop in `agent-prompt.md`). If
   there are none, report the current status briefly and wait.
6. **Self-heal auto-ping.** A manual `ping` reaches you even when the pane watcher
   is down (you read the pane directly). So on `ping`, also run
   `scripts/watch.sh status`; if it reports `BROKEN`, run
   `scripts/watch.sh reload` (idempotent — it closes then reopens the pipe, so it
   never toggles a healthy watcher off) to restore automatic pinging and verify
   the chain, then mention that you repaired it.

Any prompt that is **not** exactly `ping` is a normal instruction — handle it as
a task, **unless** it is a lightweight connectivity check (see
`lightweight-connectivity-checks.md`).
