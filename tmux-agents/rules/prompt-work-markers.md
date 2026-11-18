# Rule: one BEGIN/DONE per human prompt + step status in `term`

For **each** human instruction you take from `requests.sh` (one `# …` task), show
in `term` exactly **one** prompt-level begin marker, **zero or more** short step
messages, then **one** prompt-level done marker. Never repeat the begin/done pair
for the same task.

## Bookends (once per task)

At the **start** of working on that instruction (before the first `send.sh`):

```bash
$AGENTIC_TERMINAL_ROOT/scripts/prompt-work.sh begin
```

At the **end** (after the last action and summary for that instruction):

```bash
$AGENTIC_TERMINAL_ROOT/scripts/prompt-work.sh done
```

These type the visible `# AT: BEGIN … session:[…]` / `# AT: DONE …` lines (or the
`: AT:` shell equivalents). `prompt-work.sh begin` is idempotent — if a pair is
already open, it does not send a second BEGIN.

`send.sh` only emits **SEND** markers for command sync; do **not** rely on
`send.sh` for prompt-level BEGIN/DONE.

## Step messages (each meaningful step)

Whenever you **start** a new step (read pane, run a command, run tests, edit,
report), send one short line **in `term`** so a human watching there knows what
you are doing:

```bash
$AGENTIC_TERMINAL_ROOT/scripts/say.sh 'Reading term output…'
$AGENTIC_TERMINAL_ROOT/scripts/say.sh 'Running tests…'
```

Keep each message under ~80 characters, plain language, present tense. Use
`say.sh` only — never `#` comments (see `term-status-output.md`).

## Order for a typical task

1. `prompt-work.sh begin`
2. `say.sh` → `read.sh` (in agent) as needed
3. `say.sh` → `send.sh` for each action
4. Final `say.sh` summary if useful
5. `prompt-work.sh done`

On a **`ping`** with no new `#` tasks, do **not** call `prompt-work.sh begin/done`.

If you were interrupted mid-task, call `prompt-work.sh done` before starting the
next human instruction (or call `done` then `begin` for the new one).
