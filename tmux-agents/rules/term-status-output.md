# Rule: status output in `term` (never `#` comments)

When you need to show progress, acks, or summaries **in `term`**, never type a
`# ...` line. In this project `#` at a prompt is reserved for **human prompts**
and triggers **auto-ping** — including your own status lines.

Use the language's normal visible output instead:

| Active environment | Use |
|---|---|
| Shell (bash/zsh) | `echo '…'` (or `scripts/say.sh '…'`) |
| Python / IPython REPL | `print('…')` (or `scripts/say.sh '…'`) |

**Prefer `scripts/say.sh`** — it picks `echo` vs `print()` from the current
prompt (same detection as `send.sh` markers).

Examples:

```bash
scripts/say.sh '[agent] Running tests...'
scripts/say.sh '[agent] Done — 3 failures.'
```

Do **not** do this (will auto-ping you):

```bash
echo '# working on tests' | scripts/send.sh   # BAD in shell
echo '# checking status' | scripts/send.sh    # BAD in IPython too
```

Report in your **`agent`** session when that is enough; use `say.sh` in `term`
when the human is watching there.
