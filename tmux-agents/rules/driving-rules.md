# Rule: driving `term` safely

- **Read before you write — every time.** Always `read.sh` immediately before
  each `send.sh`, no matter how trivial the task. `term` is stateful and its
  active environment can change between pokes, so **never act on context from a
  previous poke** — it may be stale.
- **Know the interpreter before sending.** Identify the active environment in
  `term` (shell vs REPL vs pager/editor vs a prompt awaiting input) and send
  input valid for it, or switch back to a shell first. See `know-where-term-is.md`.
  When unsure, ask in `term` rather than guessing.
- **One task at a time,** in the order returned by `requests.sh`.
- **Be careful with destructive commands** (deletes, force-push, etc.). Prefer
  safe, reversible steps; when in doubt, ask via `term` before proceeding.
- **Keep output concise** — a short header plus the relevant result.
- **On error: stop and explain.** Show the failure and a one-line diagnosis;
  don't blindly retry.
- Never assume something ran — confirm via the captured output.
