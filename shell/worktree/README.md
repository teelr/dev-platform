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

- **The live deployment tracks the main checkout.** `scripts/install.sh` and `scripts/verify.sh` both resolve their repo root through `git rev-parse --git-common-dir`, so they act on the main checkout no matter which worktree invokes them (v1.25). That is what keeps `~/.claude` symlinks from dangling when `/merge` removes a worktree, and what stops a worktree-invoked `verify.sh` reporting every symlink as an orphan. Both print a notice when the resolved root differs from their own location. Trade-off: worktree edits to `commands/`/`skills/` go live only after merge.
- **dev-platform's own `.claude/worktree-deps` is comment-only, deliberately.** It ships rules and scripts, not a service — no `.env`, no `node_modules` — and `link-deps.sh` treats a manifest with no live paths as a clean no-op. The marker's presence is what enables the mode; the empty list is not an oversight.
- **Invoke it as `bash ~/.claude/worktree/link-deps.sh` — no arguments, no variables.** A worktree-isolated session's command guard analyses commands statically and refuses any it cannot verify stays inside the worktree. **Every** dynamic element trips it: `"${HOME}"`, `"${MAIN}"`, `"$(pwd)"` and `"${PWD}"` alike. Only a fully literal command is accepted, which is why the script derives its own paths rather than taking them. Do not "simplify" the callers back to passing arguments — the command gets refused outright and the linking step silently never runs, leaving a worktree that looks fine until the app cannot start.
- **`link-deps.sh`** — with no arguments (the form `/plan`, `/code` and `/merge` use) it derives the worktree from `git rev-parse --show-toplevel` and the main checkout from the parent of `git rev-parse --git-common-dir`, matching the rest of the worktree tooling. `link-deps.sh <main-checkout-dir> <worktree-dir>` still works for explicit use and fixtures. Either way it reads `<main>/.claude/worktree-deps` and symlinks each listed path into the worktree. It **refuses when both paths resolve to the same directory** (exit 2) — that is what running the no-argument form from the main checkout looks like, and without the guard it would replace real files with symlinks to themselves.
- **`gate-lock.sh`** — sourceable take-turns lock. A project's `scripts/gate_fast.sh` does `source ~/.claude/worktree/gate-lock.sh`, then takes the lock. The lockfile lives in the shared git common dir, so all worktrees of one repo contend on the same lock. `flock` blocks (waits its turn); it does not fail fast.

  Three public functions:

  | Function | Use |
  | -------- | --- |
  | `with_gate_lock <cmd> [args...]` | Wrap a single command. Runs in a subshell. |
  | `gate_lock_acquire [label]` | Hold across a region — what a gate that stops a backend and runs tests against its ports needs. |
  | `gate_lock_release` | Release. Safe to call without a prior acquire, and safe to repeat. |

  **`fd 9` is reserved by this helper** — `gate_lock_acquire` uses `exec 9>` so the descriptor outlives the function, which is why it can't be a subshell like `with_gate_lock`. Callers must not use fd 9 for anything else.

  Contention is announced on stderr, naming the holding pid and the wait duration; an uncontended acquire is silent, so the common single-session case adds no noise.

  Two traps worth knowing before editing this file. Holder metadata lives in a **sibling** `gate.lock.holder` file, never in the lockfile: `9>` truncates at open, *before* `flock` runs, so a waiter opening the lockfile would erase the holder's stamp before it ever blocked. And that holder file is **advisory** — `flock` releases automatically when a holder dies, so the file can outlive its process; a recorded pid is a hint, never proof. Separately, never write `exec 9>"${lf}" 2>/dev/null`: `exec` with no command applies *every* redirection to the shell permanently, so that `2>/dev/null` silences the shell's stderr for the rest of the run.

## What does NOT go here

- Claude Code hooks (PostToolUse, SessionStart, ...) → `hooks/`.
- Git hooks (`pre-commit`, ...) → `shell/git-hooks/`.
- General shell helpers → `shell/*.sh`.

This directory is only the worktree-isolation toolset.
