---
description: Standalone doc update. Normally handled by /code automatically. Use only to recover when /code's doc step was interrupted, or for docs-only fixes.
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
- Mark the completed task as `✅ COMPLETE` with verification date
- Update entity counts, version numbers, and status bullets to current values
- Add the phase to the **Execution Order** block at the bottom
- **NEVER write commit hashes for the spec being shipped this session.** /docs runs BEFORE the bundled commit lands, so the current spec's hash doesn't exist yet — writing it produces a chicken-and-egg paradox (placeholder → backfill commit). Use descriptive entries; `git log` is the authoritative hash record. Existing entries with valid hashes from prior commits stay as-is.

### ROADMAP.md

- Move the phase from "Remaining Work" to a "Completed" table (with date — no commit hash, same reason as planning.md)
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
git log --oneline -3                                                # context
grep "kermit-harness" pyproject.toml setup.cfg requirements*.txt 2>/dev/null | head -3   # version pins
```

Cross-check:

- Every `✅ COMPLETE` phase in planning.md has a matching entry in ROADMAP.md
- Version numbers are consistent across all docs
- No doc still says "PENDING" or "(pending)" for something that's live
- No commit hashes for the current-spec entry (they don't exist yet — the bundled commit hasn't landed)

## Step 5: Stage Doc Updates — DO NOT COMMIT

Per the project bundling rule (see `/home/rich/dev/CLAUDE.md` "Docs Before Commit"): feature code and doc updates go into ONE atomic commit, never separate. /docs stages the doc changes; the upcoming feature commit will bundle them.

```bash
git add planning.md ROADMAP.md README.md tasks/lessons.md
# Add any docs/ files if changed
```

**Do NOT run `git commit`.** The user (or the next workflow step) creates the bundled commit covering both the feature implementation and these doc updates. Splitting into a `docs:` commit followed by a `feat:` commit pollutes history and violates the bundling rule.

If the work is genuinely docs-only (no feature changes — rare, e.g., a doc typo fix), the user explicitly invokes a `docs:` commit themselves; /docs still doesn't auto-commit.

## Rules

- **Be accurate** — only mark things complete that are actually complete. Don't claim PASS without checking.
- **Be specific** — include dates, entity counts, version numbers (NOT commit hashes for the current-shipping spec — see Step 3 planning.md guidance).
- **Don't over-document** — update what changed, don't rewrite sections that are still accurate.
- **Stage; never commit** — the bundled feat commit takes both feature code and doc updates. /docs only stages.
- **Do NOT modify CLAUDE.md** — that's for rules, not status. If a lesson consolidates into a rule, note it but ask the user before changing CLAUDE.md.
- **Do NOT push** — that's a separate explicit step after the bundled commit lands.
