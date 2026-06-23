# Running more than one chat on the same project

Open two Claude Code chats in the same project folder and they share everything — the same files and branch, the same running app, the same database. One chat's `git checkout -b` switches the branch out from under the other; both try to start the backend on the same port; one chat's cleanup wipes data the other is using. They crash and overwrite each other.

v1.4 fixes the file-and-branch collision for any project that opts in, and makes the chats take turns on the shared app instead of fighting over it.

## What you get when you turn it on

- **Each chat works in its own copy of the repo**, on its own branch, under `.claude/worktrees/<branch>`. Two chats can never share a working tree, so they can't overwrite each other's files or switch each other's branch.
- **`/code` sets this up automatically** — it creates the worktree, switches the session into it, and symlinks your heavy ignored files (`.env`, `node_modules`) in so the app still runs.
- **`/merge` cleans it up** — after the PR lands, it removes the worktree and returns the session to the main checkout.
- **`/gate fast` takes turns on the backend** — if both chats run the gate at once, the second waits for the first to finish stopping and restarting the backend, instead of both grabbing the same port.

## The honest limit

This does NOT let two chats run the app live at the same time. They still share one backend and one database; the lock just makes them take turns. If you ever need two apps running live at once, that's a bigger change — per-chat ports and per-chat databases — and it's out of scope here.

## Turning it on for a project

Worktree mode is **opt-in**. A project without the marker keeps the current `git checkout -b` behavior, unchanged. To turn it on, do this from the project's own repo (each project owns its own config — dev-platform does not write these files for you):

### 1. Add `.claude/worktree-deps`

Create a file at the repo root named `.claude/worktree-deps`, one path per line — the heavy git-ignored files the app needs to run. Blank lines and `#` comments are ignored:

```text
# .claude/worktree-deps
.env
frontend/node_modules
frontend/.next
```

`/code` symlinks each of these from the main checkout into every new worktree. It links, never copies — so `node_modules` is shared from one install and `.env` copies can't drift. A path that doesn't exist yet (e.g. you haven't run `npm install`) is a warning, not an error.

### 2. Gitignore the worktrees

Make sure `.claude/` (or at least `.claude/worktrees/`) is in the project's `.gitignore`, so worktrees are never committed.

### 3. Make the gate take turns

If the project's `scripts/gate_fast.sh` (or equivalent) stops and restarts a backend, wrap that part in the lock so two gates don't fight over the port:

```bash
source ~/.claude/worktree/gate-lock.sh
# ... then, around the backend stop/restart:
with_gate_lock restart_backend     # or: with_gate_lock bash -c '...'
```

The lockfile lives in the repo's shared git directory, so all of the project's worktrees contend on the same lock. `flock` waits its turn; it does not fail fast.

### 4. Check it works

Open two chats, run `/code` in each, and confirm you get two separate `.claude/worktrees/...` directories and that the app runs in each.

## How it's wired

- `shell/worktree/link-deps.sh` — symlinks the manifest paths into a worktree. `/code` runs it after creating the worktree.
- `shell/worktree/gate-lock.sh` — the `with_gate_lock` take-turns helper a project's gate sources.
- Both deploy to `~/.claude/worktree/` via `./scripts/install.sh worktree`.
- `/code` creates and enters the worktree with the harness `EnterWorktree` tool; `/merge` leaves and removes it with `ExitWorktree` + `git worktree remove`.

See `shell/worktree/README.md` for the file-level contract.
