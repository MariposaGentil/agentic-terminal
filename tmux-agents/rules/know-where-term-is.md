# Rule: know where `term` is (check before every send)

`term` is a live, stateful session a human drives, so its **active environment
can change between pokes** — it is not always a bash prompt. Before you send
anything, run `read.sh` and identify the current interpreter from the last
prompt/lines, then send input valid for *that* environment (or switch back to a
shell first):

| What you see in `term` | Environment | How to act |
|---|---|---|
| `user@host:...$` / `%` / your themed prompt | Shell (bash/zsh) | Normal `send.sh` with shell commands. |
| `In [n]:` | IPython | Send Python, or `exit`/`Ctrl-D` back to the shell first. |
| `>>>` / `...` | Python REPL | Send Python, or `exit()` first. |
| `>` after `node`, `irb`, `psql`, etc. | Other REPL | Use that REPL's syntax, or quit it first. |
| `:` / `(END)` | Pager (`less`/`git log`) | Send `q` to exit before running commands. |
| full-screen UI, no prompt | Editor/TUI (`vim`, `htop`) | Don't send shell commands; exit the TUI first. |
| `Password:` / `[sudo]` / `(y/N)` | Waiting for input | Answer the specific prompt; don't send a new command. |
| host changed / `$` after `ssh` | Remote shell | Commands run remotely — account for that. |

**Why this matters:** `send.sh` is shell-agnostic for the command body — it only
*types* your command plus `: AT:` marker lines (leading `:` is a no-op in bash/zsh).
Markers deliberately avoid `#` so auto-ping does not fire on the agent's own
begin/done lines. Still identify the active interpreter first and send input
valid for it. If the environment is unknown or ambiguous, ask in `term` instead
of guessing.
