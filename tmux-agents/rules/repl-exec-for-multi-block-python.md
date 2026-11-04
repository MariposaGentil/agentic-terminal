# Rule: multi-block Python in `term` (REPL)

**Scope:** when `term` is in a Python / IPython interactive console (e.g.
`make qapi-client`) and you drive it with `scripts/send.sh`.

**Rule:** Do **not** paste multi-statement scripts as bare REPL input. Wrap the
whole block in `exec('''…''')` when sending via `send.sh`.

## Why

The stdlib REPL treats each paste chunk as one compound statement. A `for` loop
followed by a top-level `if`/`else` (same paste) causes `SyntaxError: invalid
syntax`. Long f-strings with `\n` can break when `send.sh` line-wraps in the
pane.

## Do

- One `exec('''…''')` per `send.sh` heredoc for multi-line Python.
- Use plain `print("a", "b")` or string concatenation — avoid `\n` inside
  f-strings in `exec` payloads.
- On failure: `print(...)` and `if/else` — never `SystemExit` / `sys.exit` (see
  `no-system-exit.md`).
- When the human should copy the same logic manually, also log a **paste-ready**
  version (no `exec`) via `scripts/log-snippet.sh` — see
  `skills/qapi-client-debug/SKILL.md`.

## Don't

```python
# BAD — pasted into REPL via send.sh without exec
for code in GVA_CODES:
    ...
if errors:          # SyntaxError: not part of the for-loop block
    print("FAIL")
```

```python
# BAD — \n inside f-strings in exec (pane wrap can break the string)
print(f"\n--- {code} ---")
```

## Do (minimal pattern)

```python
exec('''
errors = []
for code in GVA_CODES:
    print("---", code, "---")
    ...
print("")
if errors:
    print("FAIL:", errors)
else:
    print("OK")
''')
```
