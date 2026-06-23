# shell/worktree/

Tooling for running more than one Claude Code chat against the same project at once without the chats tripping over each other. Deployed to `~/.claude/worktree/` by `scripts/install.sh worktree`.

## The problem this solves

Open two chats in the same project folder and they share everything: the same files and branch (one chat's `git checkout -b` switches the tree out from under the other), the same running app (both bind the same port), and the same database. They crash and overwrite each other.

The fix has two layers:

1. **Files and branch** — each chat gets its own copy of the repo on its own branch under `.claude/worktrees/<name>`, created by the harness `EnterWorktree` tool. Two chats can't share a working tree.
2. **Running app and database** — these stay shared. The chats **take turns**: a lock (`gate-lock.sh`) makes the second `/gate fast` wait while the first stops and restarts the backend, instead of both fighting over the port. This does NOT give each chat its own live app — that would need per-chat ports and per-chat databases, which is out of scope.

## Turning it on for a project (opt-in)

A project opts in by committing a file named `.claude/worktree-deps` at its repo root. **Presence of the file = opt-in.** Without it, `/code` keeps its current `git checkout -b` behavior, unchanged.

### `.claude/worktree-deps` format

One path per line, relative to the repo root. Blank lines and lines starting with `#` are ignored. Each path is a heavy, git-ignored file or directory that a fresh worktree needs in order to run but should not be rebuilt per worktree (slow, or would drift). Example:

```text
# .claude/worktree-deps — paths symlinked from the main checkout into each worktree
.env
frontend/node_modules
frontend/.next
```

`link-deps.sh` (below) symlinks each listed path from the main checkout into the worktree. It **links, never copies** — `node_modules` is shared from one install, and `.env` copies can't drift. A missing source path is a warning, not an error (the project may not have run `npm install` yet).

### Required: gitignore the worktrees

`EnterWorktree` creates worktrees under `.claude/worktrees/`. Each opting-in project MUST have `.claude/` (or at least `.claude/worktrees/`) in its `.gitignore` so worktrees are never committed. (dev-platform already ignores `.claude/`.)

## Files

- **`link-deps.sh`** — `link-deps.sh <main-checkout-dir> <worktree-dir>` reads `<main>/.claude/worktree-deps` and symlinks each listed path into the worktree. `/code` runs this right after `EnterWorktree`.
- **`gate-lock.sh`** — sourceable take-turns lock. A project's `scripts/gate_fast.sh` does `source ~/.claude/worktree/gate-lock.sh`, then wraps its backend stop/restart in `with_gate_lock <command>`. The lockfile lives in the shared git common dir, so all worktrees of one repo contend on the same lock. `flock` blocks (waits its turn); it does not fail fast.

## What does NOT go here

- Claude Code hooks (PostToolUse, SessionStart, ...) → `hooks/`.
- Git hooks (`pre-commit`, ...) → `shell/git-hooks/`.
- General shell helpers → `shell/*.sh`.

This directory is only the worktree-isolation toolset.
