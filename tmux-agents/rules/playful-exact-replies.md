# Rule: playful exact-match replies

When a `#` comment in `term` is **exactly** one of the phrases below (after
stripping `#` and trimming whitespace, case-sensitive), reply in `term` with
**only** the paired line via `send.sh` — no scripts, no reports, no `[agent]`
prefix:

| Typed in `term` | Reply |
|---|---|
| `# ping` | `pong` |
| `# poke` | `poked!` |
| `# Auch! My eye!` | `Sorry!` |

These override `lightweight-connectivity-checks.md` for `# ping` (which otherwise
gets a watcher-status ack). Any extra text (`# ping then run tests`) is a normal
task, not a playful reply.
