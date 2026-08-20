---
description: Implement a coding spec file task by task with verification after each step. Use after /plan has produced a spec.
argument-hint: "<path-to-spec-file>"
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, TodoWrite, EnterWorktree
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

**Branch auto-creation:** If the current branch is `main`, start a fresh place to work before writing any code:

```bash
git branch --show-current   # confirm we're on main
```

If on `main`, first derive the branch name (same as always):

- Read `./planning.md` to find the active roadmap phase (e.g. `v0.9`)
- Derive the slug from the spec filename: `tasks/foo-bar-spec.md` → `foo-bar`; strip any `{project}-` prefix if present
- Determine the Phase number: 1 for a fresh spec; for subsequent Phases, check `git log --oneline` for prior phase branches and increment
- The branch name is `v<X.Y>/phase-<N>-<slug>`

Then pick the mode by checking for the project's worktree opt-in marker:

```bash
test -f .claude/worktree-deps && echo "worktree mode" || echo "branch mode"
```

**Branch mode** (no `.claude/worktree-deps` — the default for most projects, including dev-platform itself): create and check out the branch exactly as before, then report it.

```bash
git checkout -b v<X.Y>/phase-<N>-<slug>
```

**Worktree mode** (`.claude/worktree-deps` exists — opted-in projects that run more than one chat at once, e.g. Kermit, Kermit PA, Keystone, SQRL): each chat works in its own copy of the repo so two chats never share a working tree. Do this:

1. Record the main checkout path first: `MAIN=$(git rev-parse --show-toplevel)`.
2. Call the **`EnterWorktree` tool** with `name` set to the branch name (e.g. `v1.4/phase-1-foo`). It creates `.claude/worktrees/v1.4/phase-1-foo` on a fresh branch off `origin/<default>` and switches this session into it. Do NOT run `git worktree add` by hand — the tool also re-roots the session, so your later edits land in the worktree automatically.
3. Link the project's heavy git-ignored files (`.env`, `node_modules`, ...) into the worktree so the app can run:

   ```bash
   bash "${HOME}/.claude/worktree/link-deps.sh" "${MAIN}" "$(pwd)"
   ```

4. Report the worktree path, the branch name, and what got linked.

Worktree mode is opt-in via the project's committed `.claude/worktree-deps` file (see `shell/worktree/README.md`). `/merge` tears the worktree down after the PR lands.

If already in a worktree or already on a feature branch, skip creation and proceed. This is the common case now — `/plan` creates the branch/worktree when it writes the spec, so this is a fallback for hand-authored specs or specs written before that convention.

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

## Step 6: Adversarial Self-Review

Before reporting done, re-read your own staged diff as a hostile reviewer who assumes it is broken. This is distinct from Step 5's build/spec verification — it is a fresh-eyes pass over the *diff*, not the spec.

```bash
git diff --stat
git diff                     # read the full diff, hunk by hunk
```

For every hunk, ask:

- **Logic that still compiles but is wrong** — off-by-one, inverted boolean, wrong variable, missing `await`, swapped args.
- **Edge cases** — empty input, null/undefined, zero-length, first/last element, concurrent access.
- **Boundary sweep** — if a signature, return type, or call path changed, did EVERY caller in `src/` AND `tests/` get updated? (`grep -rn` the symbol.)
- **Did I change something the spec didn't ask for?** Revert it.
- **Did I leave something the spec asked for unimplemented?** Finish it.
- **Secrets / debug output** — no credentials, no `console.log`, no leftover `print`/`dbg!`.

Fix everything you find here before proceeding — do NOT defer it to `/review`. The self-review is your obligation; `/review` is the independent backstop, not a substitute for reading your own work.

## Step 7: Update Project Docs

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

## Step 8: Security Reminder

Before reporting ready, check whether any implemented changes touch:

- Authentication or authorization logic
- Credential handling, secrets, or tokens
- User-supplied input (forms, query params, file uploads, API request bodies)
- New public endpoints or routes
- External API calls or webhook handlers

If YES to any of the above, include this line in your end-of-step report:

> **Consider `/security-review`** before `/gate fast` — this change touches [auth / credentials / external input / new endpoints].

## Step 9: Run `/review` Automatically

`/code` owns the independent review pass — it runs immediately, in the same turn, with no separate invocation. Do NOT stop and wait for the user to ask for it.

Run the review procedure exactly as documented in `commands/review.md` Steps 1-5, unchanged:

1. **Stage everything this spec touched before diffing.** Step 7 only staged the doc files (`planning.md`, `ROADMAP.md`, `README.md`, `tasks/lessons.md`) — it does not stage the implementation files from Steps 1-6. Explicitly `git add` every file this spec's Changes created or modified (use the spec's File Change Summary as the checklist), in addition to what Step 7 already staged. Do NOT use `git add -A` or `git add .` — name each file. Only once everything is staged, gather the diff (`git diff --cached`) per `commands/review.md` Step 1.
2. Load `./CLAUDE.md` and `~/.claude/CLAUDE.md`.
3. Review every changed file across SECURITY, BUG, COMPLIANCE, QUALITY, and ARCHITECTURE (Language Architecture Decision Matrix compliance).
4. Fix SECURITY, BUG, COMPLIANCE, and QUALITY issues immediately — do not wait for approval. Re-read each fixed file to confirm the fix is correct. Surface ARCHITECTURE issues for the user's decision; do NOT fix them.
5. Produce the `# Code Review` report exactly as `commands/review.md` Step 5 defines it (Files reviewed, Verdict, Fixes Applied by category, Needs Your Decision / ARCHITECTURE, Summary).

This review pass is independent of Step 6's Adversarial Self-Review — it is the fresh-eyes backstop `/code` structurally cannot be by re-reading its own diff, run here as `/code`'s own final action rather than a separately invoked command. If any ARCHITECTURE issues surface, they are still unresolved when this step ends — carry them into Step 10's report exactly as `commands/review.md` would.

## Step 10: Report — Next Step Is `/gate fast`

Combine this turn's report: the implementation summary (Changes completed, Step 7's doc updates, Step 8's security reminder if applicable) followed by Step 9's `# Code Review` report block.

If Step 9 found ARCHITECTURE issues, they are unresolved — surface them clearly; the user must decide before proceeding.

End your report with:

> Ready for `/gate fast`.

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
