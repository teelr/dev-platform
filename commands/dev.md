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
4. `./tasks/lessons.md` — accumulated gotchas and corrections
5. `./ROADMAP.md` — phase-level milestones (if present)

Also list `./tasks/` to see active spec files: `ls -1t tasks/*.md 2>/dev/null | head -10`

## Step 2: Inspect git state (parallel bash)

Run these in parallel:

- `git log --oneline -20` — recent commit history
- `git status` — working tree state
- `git branch --show-current` — current branch
- `git stash list` — any stashed work

## Step 3: Identify the most recent active spec

From the `tasks/` listing, identify the most recently modified spec file (excluding `lessons.md` and `HARNESS_HANDOFF_QUEUE.md`). Read its progress table or task list to determine which Task is next.

## Step 4: Check the running stack (best-effort, don't block)

Detect the project's startup mechanism without launching anything yet:

- Look for `scripts/start_dev.sh`, `docker-compose.yml`, `Makefile`, `package.json` scripts
- Note which command would bring the stack up — but do NOT run it
- If a `make smoke` or equivalent target exists, mention it as the verification step

## Step 5: Report — concise, structured

Output a single report with these sections. Be terse — the user is reading this to get oriented in seconds, not minutes.

```text
## Project: <name>

**Branch:** <branch> (<N> commits ahead of main, <clean|dirty>)
**Last commit:** <hash> <subject> (<relative time>)

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

## Recent lessons to keep in mind
- <2-3 most relevant items from tasks/lessons.md, if any stand out>

## Suggested entry point
<one sentence: continue current Task with /code, start new feature with /plan, or fix the dirty working tree first>
```

## Rules

- **Do NOT** start the dev server, run smoke tests, or modify any files. This is a read-only orientation.
- **Do NOT** advance to `/plan` or `/code` after reporting. STOP after the report. The user will invoke the next step explicitly.
- **Do NOT** invent state — if `planning.md` doesn't exist, say so. If no spec is active, say so.
- Keep the report under ~40 lines. The user can ask follow-up questions.
- If the working tree is dirty, flag it prominently — uncommitted work from a prior session is the single most common source of confusion at session start.
