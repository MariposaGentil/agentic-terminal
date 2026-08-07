---
name: review
description: >-
  Performs a comprehensive review of git changes (unstaged, staged, branch vs
  base, or a specific commit). Use when the user asks for a review, PR review,
  code review, or uses the review alias on current or specified changes.
---
# Review

Perform a full code review of the requested git scope. This project has **no
Jira tickets** — do not fetch or reference issue trackers.

## 1. Determine scope

Parse what the user wants reviewed. Default to **branch changes** when unclear.

| User intent | Git commands (run in parallel where useful) |
|---|---|
| **Unstaged only** | `git diff` |
| **Staged only** | `git diff --cached` |
| **Unstaged + staged (working tree)** | `git diff` and `git diff --cached` |
| **Branch vs base** | Find base (see below), then `git diff <base>...HEAD` |
| **Specific commit** | `git show <commit>` or `git diff <commit>^..<commit>` |
| **Specific branch** | Checkout or diff against that branch: `git diff <branch>...HEAD` |

Also gather context:

```bash
git branch --show-current
git status
git log --oneline -10
```

**Finding the base branch** (for branch reviews): use `git log --oneline --decorate`
and pick the first ancestor that belongs to another branch (typically `main`).
Compare with `git diff <base>...HEAD`.

If the user names a commit hash, tag, or branch explicitly, use that instead.

## 2. Analyze the diff

Read the diff carefully. Separate **production code** from **tests** and **docs**.

For this repo, production code is mainly `scripts/`, `run.sh`, `Makefile`, and
`tmux-agents/`. Tests live in `tests/`.

## 3. Output the review

Use this structure:

---

### What Is This Doing

Brief summary (1–5 lines) of what the changes accomplish and whether they look
complete for the stated goal.

### Code Review (Production Code Only)

Review **production code only** (exclude test files unless the change *is* tests).
Focus on:

- **Correctness**: Logic errors, edge cases, race conditions, error handling
- **Shell safety**: quoting, `set -euo pipefail` usage, tmux/session edge cases
- **Architecture**: Fits existing `scripts/` patterns; no unnecessary complexity
- **UX / operability**: Clear messages, safe defaults, recovery paths (e.g. watcher reload)

For each finding, cite the file and line. Severity levels:

- **Critical**: Bugs, data loss, broken sessions, security issues
- **Warning**: Edge cases, reliability under stress
- **Nit**: Style, naming, minor improvements

### Test Coverage Review

- Are new behaviors covered in `tests/`?
- Edge cases and failure paths tested?
- Integration tests where tmux behavior matters?

### Suggestions

- Missing comments for non-obvious logic
- DRY violations, naming, simpler alternatives
- Design trade-offs worth discussing

### Final Conclusion

1–5 lines: approve, request changes, or needs discussion. List top action items.

---

## Guidelines

- Be critical but constructive — explain *why* and suggest a fix
- Prioritize critical > warning > nit
- Do not comment on obvious diff noise (e.g. "you added an import")
- Do not mention Jira or external ticket systems
- For large diffs, review the highest-impact files first (`scripts/`, watcher, send/read)
