---
description: Orient to the current project at the start of a dev session — load recent state, run smoke checks, and report where work stands.
argument-hint: "(no arguments — operates on the current working directory)"
allowed-tools: Read, Bash, Glob, Grep
---

# Dev Session Bootstrap

You are bootstrapping a development session for an in-progress project. The user has just opened the project (likely in VSCode) and wants to recover context fast. Your job is to load state, surface what matters, and report — not to start coding.

## Step 1: Load project rules and context (parallel reads)

Read these in a single batch — skip any that don't exist, don't error:

1. `./CLAUDE.md` — project-specific rules
2. `./planning.md` — current roadmap / development state
3. `./README.md` — project overview
4. `./tasks/lessons/` — accumulated gotchas and corrections, one file per lesson. Read the newest few:
   `ls -1 tasks/lessons/*.md 2>/dev/null | sort -r | head -5`. Sort by NAME, not `ls -t` — the filename leads with the date, whereas mtime is checkout order and reshuffles on every clone
5. `./ROADMAP.md` — phase-level milestones (if present)

Also list `./tasks/` to see active spec files: `ls -1t tasks/*.md 2>/dev/null | head -10`

## Step 2: Inspect git state (parallel bash)

Run these in parallel:

- `git log --oneline -20` — recent commit history
- `git status` — working tree state
- `git branch --show-current` — current branch
- `git stash list` — any stashed work

## Step 3: Identify the most recent active spec

From the `tasks/` listing, identify the most recently modified spec file (excluding `HARNESS_HANDOFF_QUEUE.md`; lessons live in the `tasks/lessons/` subdirectory and are handled in Step 1). Read its progress table or task list to determine which Task is next.

## Step 4: Check the running stack (best-effort, don't block)

Detect the project's startup mechanism without launching anything yet:

- Look for `scripts/start_dev.sh`, `docker-compose.yml`, `Makefile`, `package.json` scripts
- Note which command would bring the stack up — but do NOT run it
- If a `make smoke` or equivalent target exists, mention it as the verification step

## Step 5: Check for other live sessions

`cc --new` makes two, three, or four sessions on one project routine, so find out
what else is running before you advise anything:

```bash
bash /home/rich/dev/scripts/check-concurrent-sessions.sh
```

It prints four things: the live sessions in this repo, whether worktree mode
isolates them, what stays shared, and whether a concurrent `/gate fast` takes
turns on the backend.

**Report its lines as facts.** Do NOT re-derive any of this yourself from `ps`,
`git worktree list`, or process inspection, and do NOT add caveats it did not
print. The script exists because that improvisation produced confidently wrong
advice — see the Rules below.

## Step 6: Report — concise, structured

Output the report as **plain markdown** — do NOT wrap it in a fenced code block. Be terse — the user is reading this to get oriented in seconds, not minutes.

Use exactly these sections and this formatting (the template below is an illustration — output it as plain markdown, not inside a code block). Include **## Other sessions** only when the detector reports more than one session, or reports `unknown` — a single-session run must not grow the report:

````text
## Project: <name>

**Branch:** <branch> (<N> commits ahead of main, <clean|dirty>)
**Last commit:** <hash> <subject> (<relative time>)

## Other sessions
- <the detector's session lines, verbatim>
- <its isolation, shared, and gate lines, verbatim>

## Where work stands
- <1-3 bullets summarizing the current Phase / Spec / Task from planning.md + most recent spec>
- <next concrete Task if one is in progress, or "no spec in flight" if not>

## Recent activity (last 5 commits)
- <hash> <subject>
- ...

## Working tree
- <summary of git status — modified files, untracked, stashes — or "clean">

## To bring the stack up
```bash
<the actual command, e.g. ./scripts/start_dev.sh>
```
Verify with: `<smoke command>`
<if another session is live: one sentence noting the app and database are shared, so starting or restarting the stack affects that session too>

## Recent lessons to keep in mind
- <2-3 most relevant items from the newest tasks/lessons/ files, if any stand out>

## Suggested entry point
<one sentence: continue current Task with /code, start new feature with /plan, or fix the dirty working tree first>
````

## Rules

- **Do NOT** start the dev server, run smoke tests, or modify any files. This is a read-only orientation.
- **Do NOT** advance to `/plan` or `/code` after reporting. STOP after the report. The user will invoke the next step explicitly.
- **Do NOT** invent state — if `planning.md` doesn't exist, say so. If no spec is active, say so.
- Keep the report under ~40 lines. The user can ask follow-up questions.
- **Never tell the user to avoid `/gate fast` because another session is running.** The gate lock is what makes that safe, and Step 5's detector reports whether it is wired — report that, don't guess. Improvised advice here is the exact defect this step exists to fix.
- **Another session's worktree is off-limits** — don't read into it, don't touch its stashes, don't `git worktree remove` it. But being unable to work in *that* worktree is not a reason to tell the user they can't work at all: in a worktree-mode project, `/plan` gives this session its own.
- If the working tree is dirty, flag it prominently — uncommitted work from a prior session is the single most common source of confusion at session start.
