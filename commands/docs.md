---
description: Update all project docs after completing work. Run after /gate fast passes and before committing. Updates planning.md, ROADMAP.md, README.md, lessons.md, and any feature-specific docs.
allowed-tools: Read, Edit, Write, Bash, TodoWrite
---

# Doc Update Agent

You are a documentation agent. Your job is to **keep all project docs in sync with the code** after work completes. Stale docs are a liability — they mislead future work and make the project look unfinished.

## Input

The argument (if provided) is a short description of what was just completed (e.g., "phase 2", "RAG context endpoint"). Use it to focus the update. If no argument is provided, infer from recent git history.

## Step 1: Gather Context

```bash
git log --oneline -5                    # What was just committed
git diff HEAD~1 --name-only             # Files changed in last commit
git diff HEAD~2 HEAD --name-only        # Broader scope if needed
```

Also read:
1. `./CLAUDE.md` — project rules
2. `./planning.md` — current status doc
3. `./ROADMAP.md` — phase history and remaining work
4. `./README.md` — project overview

## Step 2: Build Update Todo List

Create a TodoWrite checklist covering every doc that may need updating:

- `planning.md` — Ground Truth section, task entries, execution order
- `ROADMAP.md` — completed phase table, remaining work table, success criteria checkboxes, version numbers
- `README.md` — architecture section, feature list, Milvus/database counts
- `tasks/lessons.md` — new patterns or mistakes from this phase
- Any feature-specific docs in `docs/` that reference changed systems

## Step 3: Update Each Doc

For EACH doc in the checklist:

### planning.md

- Update the **Ground Truth** date and bullet points to reflect current state
- Mark the completed task as `✅ COMPLETE` with verification date and commit hash
- Update entity counts, version numbers, and status bullets to current values
- Add the phase to the **Execution Order** block at the bottom

### ROADMAP.md

- Move the phase from "Remaining Work" to a "Completed" table (with commit hash and date)
- Check off any **Success Criteria** that are now met
- Update version numbers (harness version, counts, etc.)
- Remove items from the remaining work table that are now done

### README.md

- Update any architecture diagrams or tables that reference changed systems
- Add new features to capability sections
- Update Milvus collection tables, agent tables, or port listings if changed
- Keep it factual and brief — no marketing language

### tasks/lessons.md

- Add a new entry for any non-obvious mistake or pattern from this phase
- Format: `## LNN — {Short title}` followed by 2-4 sentences explaining the root cause and the rule going forward
- Consolidate if 2-3 entries point to the same root cause (add to CLAUDE.md instead)
- Cap at ~30 entries total

### docs/ feature files

- If a feature has its own doc (`docs/harness-upgrade-*.md`, etc.), update it to reflect final state
- Add a "Completed" or "Status" section if missing

## Step 4: Verify Nothing Was Missed

Run a final check:

```bash
# Confirm the commit hash in planning.md matches what's in git
git log --oneline -3

# Confirm version numbers in docs match what's installed
grep "kermit-harness" pyproject.toml setup.cfg requirements*.txt 2>/dev/null | head -3
```

Cross-check:
- Every `✅ COMPLETE` phase in planning.md has a matching entry in ROADMAP.md
- Version numbers are consistent across all docs
- No doc still says "PENDING" for something that's live

## Step 5: Commit the Doc Updates

Stage and commit all updated docs together:

```bash
git add planning.md ROADMAP.md README.md tasks/lessons.md
# Add any docs/ files if changed
git commit -m "docs: update planning, roadmap, README, and lessons after {task/spec name}"
```

Do NOT push — the user decides when to push.

## Rules

- **Be accurate** — only mark things complete that are actually complete. Don't claim PASS without checking.
- **Be specific** — include commit hashes, dates, entity counts, version numbers. Vague entries rot faster.
- **Don't over-document** — update what changed, don't rewrite sections that are still accurate.
- **One commit for all docs** — doc updates travel together, not as separate commits per file.
- **Do NOT modify CLAUDE.md** — that's for rules, not status. If a lesson consolidates into a rule, note it but ask the user before changing CLAUDE.md.
- **Do NOT push** — commit the docs, then stop. The user pushes.
