# Rule: never use SystemExit in `term`

**Scope:** any code you type into `term` via `scripts/send.sh` — especially Python
`exec('''…''')` blocks in an interactive REPL (`make qapi-client`, IPython, etc.).

**Rule:** **Never** use process-exit mechanisms in code sent to `term`:

- `raise SystemExit(...)`
- `sys.exit(...)`
- `exit()` / `quit()`

These propagate **out of** `exec()` and tear down the whole interactive session
(e.g. `now exiting InteractiveConsole…`, `make qapi-client` exits). One failed
step must not kill the human's REPL.

## On error instead

- **Print** a short message (`print(...)`, `scripts/say.sh`, or shell `echo`).
- **Branch:** `if not ok: print("…"); else: …` — skip the rest without exiting.
- **Return early** inside helpers; in a one-off `exec` block, use `if/else` rather
  than aborting the interpreter.
- **Report** the failure in your agent session on the next poke; let the human
  decide whether to retry.

## Examples

```python
# BAD — kills the debug client on 402 Max devices
device = create_device(account, name, PLATFORM_WINDOWS)
if not device:
    raise SystemExit("device creation failed")

# GOOD — session stays alive
device = create_device(account, name, PLATFORM_WINDOWS)
if not device:
    print("device creation failed — account may be at device limit")
else:
    link_device_to_profile(account, profile, device)
    ...
```

See also `driving-rules.md` (stop and explain on error; never assume success).
