# Running several sessions on one project

This is the orientation piece: what the multi-session setup is, why each part of it exists, and what it costs you. For the how-to — turning worktree mode on for a project, wiring the gate lock — see [CONCURRENT-DEV.md](CONCURRENT-DEV.md).

## The problem

You want to run several Claude Code sessions on one project at the same time. Everything below came out of doing that and watching it break.

Two sessions working the same project stepped on each other in three different ways:

- **They shared one folder and one branch.** One session's `git checkout -b` moved the ground under the other.
- **They appended to the same few doc files** — the bottom of the lessons table, the top of the "recently shipped" list. Every pair of finishes was a merge conflict, or worse: git merged them cleanly at different line offsets and left a silent duplicate that nothing caught.
- **They queued on the gate in silence.** The lock worked, but `flock` blocks with no output, so a session waiting its turn looked identical to one that had hung.

The collisions were not random. Each was a place where two sessions had to write to *the same spot in the same file*, or where a shared resource had no way to say "busy". That shape is what the fixes target.

## What changed

**Each session gets its own copy of the repo.** `/plan` puts you in a separate folder under `.claude/worktrees/`, so two sessions cannot share files or switch each other's branch. This existed from v1.4 but was opt-in and used by five projects; dev-platform now uses it, and every newly scaffolded project starts with it.

**The shared doc files became directories.** Lessons and shipped-phase notes are one file each, named by date — `tasks/lessons/2026-09-03-<slug>.md`, `tasks/shipped/2026-09-03-v1.24-<slug>.md`. Two sessions finishing at once simply write different files. The conflict cannot happen, rather than being detected and resolved.

**`planning.md` stopped being edited per phase at all.** It is a short static orientation page now. That also removed its "In flight" section, which had sat six phases out of date because nothing owned keeping it current — the honest fix for a hand-maintained section is usually to delete it, not to remember harder.

**The gate says when it is queued.** A contended run names the holding process and reports how long it waited. An uncontended run stays silent, so the message means something when it appears.

Supporting pieces: `cc --new` starts the next session without you inventing a name, and `/dev` reports what else is running from a script rather than improvising it from process output — it used to guess, and it guessed wrong.

## What it costs you

**A worktree session's edits to `commands/` and `skills/` are not live in `~/.claude` until they merge.**

`install.sh` symlinks `~/.claude/*` at repo paths, so a worktree path there would dangle the moment `/merge` removes that worktree. `install.sh`, `verify.sh` and `uninstall.sh` therefore all resolve to the **main checkout**, whichever copy you run them from. Nothing dangles — but it does mean you can no longer edit a command and exercise it in the same session before merging. To test a command change, read the tracked file directly, or merge first.

This is the deliberate trade: deployed means shipped, never mid-phase.

## What we deliberately did not do

- **Two apps running live at once.** Sessions still share one backend and one database; the gate lock makes them take turns. Per-session ports and per-session databases is a much bigger change and remains out of scope.
- **Split `ROADMAP.md`.** It is still one shared file with a per-phase append — the only remaining one. The atomic version-claim guard reads it from `origin/main`, and splitting it would put the mechanism that hands out version numbers at risk to fix its least frequent conflict.
- **Migrate existing projects.** New projects start in worktree mode; existing ones each add a `.claude/worktree-deps` file from their own session. A deps manifest names the heavy git-ignored paths *that project* needs symlinked into a worktree, and nothing outside the project can know them — an empty manifest on a Node project produces worktrees with no `node_modules`, which is worse than not migrating.

## Where the pieces live

| Piece | Where |
| ----- | ----- |
| Worktree isolation, gate lock, the how-to | [CONCURRENT-DEV.md](CONCURRENT-DEV.md), `shell/worktree/` |
| What is running right now | `scripts/check-concurrent-sessions.sh`, reported by `/dev` |
| Starting another session | `cc --new` (see `shell/README.md`) |
| Per-lesson and per-phase records | `tasks/lessons/`, `tasks/shipped/` (each has a README) |

Roadmap Phases v1.19 through v1.25 in [ROADMAP.md](../ROADMAP.md) carry the full history, and `tasks/shipped/` has the per-phase narrative including what each one got wrong on the first attempt.
