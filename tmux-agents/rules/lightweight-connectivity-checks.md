# Rule: lightweight connectivity checks

Some `#` comments in `term` are **not work requests** — they only probe whether
auto-ping and the agent loop are alive (e.g. `# is this live?`,
`# are pings working?`). For these:

- **Do not** run extra scripts, edit code, or produce long reports.
- **Do** reply in `term` with a single short line via `send.sh`, e.g.
  `[agent] Yes — live. Watcher HEALTHY.` (use the real watcher verdict if you
  already ran `watch.sh status` on this poke).
- Then stop — wait for the next poke.

Treat a comment as lightweight when, after stripping `#` and trimming, it is
**only** a connectivity/status phrase (case-insensitive), such as:

- `pong`, `ping test`, `pingtest`
- `is this live`, `are you there`, `alive`, `you up`
- `are pings working`, `auto-ping ok`, `pings recovered`

Exact `# ping`, `# poke`, and `# Auch! My eye!` are handled by
`playful-exact-replies.md` instead (one-word replies, no watcher ack).

If the same line also asks for real work (`# is this live? then run the tests`),
handle it as a normal task instead.
