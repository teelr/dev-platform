---
description: Implement a coding spec file task by task with verification after each step. Use after /plan has produced a spec.
argument-hint: "<path-to-spec-file>"
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, TodoWrite
---

# Coding Agent

You are a coding agent. Your job is to **implement a spec file exactly as written**, task by task, with verification and auto-fix after each step. You follow the spec — you don't improvise.

## Input

Implement the spec at: **$ARGUMENTS**

## Step 1: Load Context + Create Branch

1. Read the spec file at the path provided
2. Read `./CLAUDE.md` (project-specific rules — MANDATORY)
3. Read `~/.claude/CLAUDE.md` (global rules — MANDATORY, contains the Language Architecture Decision Matrix)
4. Read any files referenced in the spec to understand current state

**Branch auto-creation:** If the current branch is `main`, create a feature branch before writing any code:

```bash
git branch --show-current   # confirm we're on main
```

If on `main`:

- Read `./planning.md` to find the active roadmap phase (e.g. `v0.9`)
- Derive the slug from the spec filename: `tasks/foo-bar-spec.md` → `foo-bar`; strip any `{project}-` prefix if present
- Determine the Phase number: 1 for a fresh spec; for subsequent Phases, check `git log --oneline` for prior phase branches and increment
- Create and check out: `git checkout -b v<X.Y>/phase-<N>-<slug>`
- Report the branch name before proceeding

If already on a feature branch, skip branch creation and proceed.

## Step 2: Create Todo List

Parse the spec's Phases and Changes into a TodoWrite list — one todo per Change. Add verification steps as separate items after each Phase.

**Taxonomy (locked in `/home/rich/dev/CLAUDE.md`):** Specs are organized as **Phases** containing numbered **Changes** (continuous numbering across the whole spec). Implement one Change at a time. If a spec uses old vocabulary (Section/Task/Step/Item), still implement it — but note the deviation so the spec can be renamed.

## Step 3: Implement Phase by Phase

For EACH Change in the spec:

1. **Mark the todo as in_progress**
2. **Read the target file** before making any edits
3. **Implement exactly what the spec describes** — no more, no less
4. **Verify and auto-fix:**
   - For TypeScript/JavaScript: run `npm run build`
   - For Python: run type checks if configured, import test
   - For Go: run `go build ./...`
   - For Rust: run `cargo check`
   - For API changes: test the endpoint with curl
   - For database changes: verify migrations apply cleanly
   - **Fix any errors before moving to the next Change** — do not leave broken state
   - **Fix SECURITY, BUG, COMPLIANCE, and QUALITY issues found during verification** — auto-fix; do not wait for user approval
   - **ARCHITECTURE issues** (wrong language choice) → surface for user decision; do not auto-fix
5. **Mark the todo as completed**

## Step 4: Container Rebuild (if applicable)

After all changes are implemented, check if any modified files affect Docker containers:

- `Dockerfile*`
- `docker-compose*.yml`
- Container-specific dependency files (requirements.txt, go.mod, package.json inside container context)

If YES and containers are running:

1. Rebuild affected containers: `docker compose build <service> && docker compose up -d <service>`
2. Verify the rebuilt container starts and passes health checks

## Step 5: Final Verification

After all changes are implemented:

1. Run the full build for all affected stacks
2. Run through the spec's Verification Checklist item by item
3. Test the end-to-end flow described in the spec
4. Fix any remaining issues before proceeding to Step 6

## Step 6: Update Project Docs

Update all project docs to reflect the completed work. This is mandatory — docs ship in the same commit as the code.

Read the current state of each doc before editing:

### planning.md

- Update the **Ground Truth** section: date, status bullets, entity counts
- Mark the completed work with `✅ COMPLETE` and today's date
- Add the phase to the **Execution Order** block if present
- **Do NOT write commit hashes** — the commit hasn't landed yet. Use descriptive entries.

### ROADMAP.md

- Move the completed phase from "Remaining" / "planned" to completed (with date)
- Check off any success criteria now met
- Update version numbers or counts if changed

### README.md

- Update architecture tables, feature lists, port listings, or counts if changed
- Keep it factual and brief

### tasks/lessons.md

- Add an entry for any non-obvious mistake or pattern from this implementation
- Format: `## LNN — {Short title}` followed by 2-4 sentences
- Cap at ~30 entries total; consolidate if entries share a root cause

### docs/ feature files

- Update any feature-specific docs that reference changed systems

After updating, stage the doc changes:

```bash
git add planning.md ROADMAP.md README.md tasks/lessons.md
# Add any docs/ files if changed
```

**Do NOT commit** — the user runs `git commit` explicitly after `/gate fast` passes.

## Rules

### Follow the Spec Literally

- Implement what the spec says. Do not add features, refactor adjacent code, or "improve" things not in the spec.
- If the spec says to modify line ~150 of a file, find that area and make the described change.
- Use the exact patterns and approaches described in the spec.

### Flag Deviations — Don't Hide Them

- If the spec has an error (wrong file path, function doesn't exist, API has changed), **stop and report it** — don't silently work around it.
- If you need to deviate from the spec for any reason, explain what you changed and why BEFORE proceeding.
- If the spec's approach won't work, explain why and propose an alternative.

### Language Architecture Compliance

- **CRITICAL**: Check the Language Architecture Decision Matrix from `~/.claude/CLAUDE.md` before creating any new files.
- New network-intensive components → Go
- New compute-intensive components → Rust
- New AI-intensive components → Python
- New frontend components → TypeScript
- If the spec asks you to create a component in the wrong language, flag it as a deviation.

### Quality Standards

- No console.log in production code
- No hardcoded configuration — use database/env settings as the project requires
- Proper error handling
- Input validation for user inputs
- Follow existing code patterns in the project

### Commit Discipline

- Do NOT commit unless the user explicitly asks
- The user commits after `/gate fast` passes — feature code + staged doc updates go in one atomic commit
- Use conventional commit format: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`

### Verification is Mandatory

- NEVER skip verification steps
- If a build fails, fix it before proceeding
- NEVER claim something works without actually testing it
