# Post-Merge Change Summary

## Coding Specification for Implementation

## Design Philosophy

Every merged Roadmap Phase already gets a rich "problem → what shipped" narrative — it's the bullet `/code`'s doc-update step writes into `planning.md`'s "Recently shipped" section before commit (per "Docs Ship With the Code"). But that narrative is buried in a running list the user has to go dig up; nothing surfaces it back to them at the moment the work actually lands (after CI-green, after `/merge` squashes it onto `main`). The existing standard post-merge sub-step — Roadmap-Phase completion (v1.10) — only fires when a merge happens to close out the *last* Change of a Roadmap Phase. Most merges are mid-phase Changes or standalone chores/fixes, so most merges currently get **no** summary at all.

This spec adds a second standard (non-bespoke) post-merge sub-step, unconditional on phase completion: **every** `/merge` invocation ends by printing a short "Problem/Opportunity → What shipped" summary in its chat report. Nothing new is written to disk — no `CHANGELOG.md`, no GitHub Release, no PR comment (the user chose chat-report-only over three other options when this was scoped). The summary is **surfaced, not regenerated**: it's derived mechanically from context that already exists at merge time, in a strict fallback order —

1. **Preferred — the `planning.md` diff.** The just-landed squash commit already contains whatever `/code` wrote into `planning.md`'s "Recently shipped" section pre-commit. `git diff HEAD~1 HEAD -- planning.md` on the newly-synced `main` shows exactly those added lines — no new authoring, just reading back what already exists.
2. **Fallback — the spec's own framing.** If `planning.md` wasn't touched by this merge (a project without dev-platform's exact planning.md convention, or an edge case where the doc step was skipped), fall back to the merged spec's Problem/Design-Philosophy framing plus its Change titles — still just reading, not inventing.
3. **Last resort — the PR itself.** No spec touched at all (a pure chore/fix merge) — use the PR title and body via `gh pr view`.

This ordering matters: Tier 1 is the richest and already-vetted-by-`/review` prose; Tiers 2-3 exist so the step degrades gracefully instead of silently doing nothing on chores, which is exactly the class of merge that most needed a summary (mid-phase Changes and one-off fixes currently get zero visibility).

**Control-flow change required:** `/merge`'s current Step 7 stops immediately ("no post-merge step — this PR is fully shipped") when no spec was touched (today's Step 7.2). That early exit predates this spec and would skip the new summary for exactly the chore/fix case Tier 3 exists to cover. The summary generation must run **before** that early-exit check, unconditionally, every single time — the existing spec-driven/phase-completion logic continues to run (or not) after it, unchanged.

**Scope guardrail:** this spec does NOT touch the workflow chain string itself (`/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge` is unchanged — no step is added, renamed, or reordered at the chain level; the new sub-step lives entirely inside the existing `post-merge` box). `audit-project-drift.sh`'s chain-detection regex keys on that literal chain string, which this spec never modifies — so `audit-project-drift.sh` and `migrate-workflow-chain.sh` need no changes and no consumer-project propagation beyond the normal "read `CLAUDE.md`" path every project already uses.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| Contract-file edits (`CLAUDE.md`, `settings/claude-global.md`, `WORKFLOW_MANUAL.md`) | Markdown | Documentation of the workflow step; not code. |
| `commands/merge.md` Step 7 instructions | Markdown + inline Bash (`git diff`, `gh pr view`) | Consistent with every other `/merge` sub-step — this command is a set of agent instructions, not a standalone script; no new script file is warranted for a 3-tier text-extraction fallback. |

No new script, no new test suite — this is an instruction-file change to an existing agent command, same shape as the v1.7 "Plan-Time Isolation" and "Workflow redesign chore" precedents (which also shipped with zero new `tests/` coverage because there's no runtime behavior to unit-test, only agent-followed prose).

## Overview

- Change 1: Add the standard **Change Summary** post-merge sub-step to `dev/CLAUDE.md`.
- Change 2: Add the same standard shape to `settings/claude-global.md`.
- Change 3: Document the step in `skills/WORKFLOW_MANUAL.md`.
- Change 4: Restructure `/merge` Step 7 so the summary generation runs unconditionally, before the existing "no spec touched" early exit.
- Change 5: Roadmap/planning/README doc updates for v1.15.

---

## Phase 1: Standard step + `/merge` wiring

### Change 1: Standard Change-Summary post-merge sub-step in `dev/CLAUDE.md`

**Problem:** `dev/CLAUDE.md`'s post-merge bullet ([CLAUDE.md:118](../CLAUDE.md#L118)) names exactly one standard sub-step (Roadmap-Phase completion), which only fires on phase-closing merges. Most merges are mid-phase or standalone and currently get no post-merge summary at all.

**File:** `/home/rich/dev/CLAUDE.md` (existing — the `- **post-merge**` bullet at line ~118).

**Implementation:**

Append a new sentence to the existing bullet (do not replace anything — the Roadmap-Phase-completion text stays verbatim). After the existing sentence ending "...per the general rule on hard-to-reverse actions.", add:

```markdown
A second standard (non-bespoke) sub-step, unconditional on phase completion: **Change Summary.** Every `/merge` invocation ends its report with a short **Problem/Opportunity → What shipped** summary — chat-report only, no new file, no CHANGELOG, no GitHub Release/PR comment. Derived from context already available at merge time, in order: (1) the lines this merge added to `planning.md`'s "Recently shipped" section (`git diff HEAD~1 HEAD -- planning.md` on the just-synced `main` — the prose `/code` already wrote pre-commit); (2) if `planning.md` wasn't touched, the merged spec's Problem/Design-Philosophy framing + Change titles; (3) if no spec was touched at all, the PR title/body via `gh pr view`. This step runs even when the merge is a chore with no spec and no phase completion — it is the ONE thing post-merge always does.
```

Do NOT introduce the literal review-less chain string `…/code → /gate fast…` anywhere in this edit (the `audit-project-drift.sh` DRIFT detector greps dev-platform's own `CLAUDE.md` for it — a bare occurrence would self-flag the repo; recurring hazard, lessons 2026-05-11 / 2026-06-07). This edit adds no new chain-string examples, so the hazard doesn't apply here — verify anyway.

**Acceptance Test:**

```bash
grep -n "Change Summary" /home/rich/dev/CLAUDE.md                    # the new standard sub-step is present
grep -n "Problem/Opportunity" /home/rich/dev/CLAUDE.md                # summary shape documented
./scripts/audit-project-drift.sh --project dev-platform | grep -E "dev-platform.*CLEAN"   # still CLEAN, no self-flag
./scripts/gate_fast.sh                                                # constitutional + taxonomy checks still PASS
```

---

### Change 2: Same standard shape in `settings/claude-global.md`

**Problem:** `settings/claude-global.md` (deployed as `~/.claude/CLAUDE.md`, the always-loaded behavior file) describes post-merge at [settings/claude-global.md:38](../settings/claude-global.md#L38) with only the Roadmap-Phase-completion sub-step named — same gap as Change 1, in the file that actually governs every session's behavior.

**File:** `/home/rich/dev/settings/claude-global.md` (existing — the post-merge sentence at line ~38).

**Implementation:**

After the existing sentence ending "...Full shape in `/home/rich/dev/CLAUDE.md`.", append:

```markdown
A second standard sub-step, unconditional on phase completion: **Change Summary** — every `/merge` ends its report with a chat-only Problem/Opportunity → What shipped summary, derived from the `planning.md` diff (preferred), the spec's framing, or the PR title (in that fallback order). No new file is written. Full shape in `/home/rich/dev/CLAUDE.md`.
```

**Acceptance Test:**

```bash
grep -n "Change Summary" /home/rich/dev/settings/claude-global.md
grep -c "Full shape in" /home/rich/dev/settings/claude-global.md     # both standard sub-steps point at the same source of truth
./scripts/gate_fast.sh
```

---

### Change 3: Document the step in `skills/WORKFLOW_MANUAL.md`

**Problem:** `skills/WORKFLOW_MANUAL.md`'s "Step 7: Post-merge" subsection ([skills/WORKFLOW_MANUAL.md:184](../skills/WORKFLOW_MANUAL.md#L184)) documents the Roadmap-Phase-completion sub-step but not this one — a reader learning the workflow from the manual wouldn't know every merge now ends with a summary.

**File:** `/home/rich/dev/skills/WORKFLOW_MANUAL.md` (existing — the "Step 7: Post-merge" body, line ~184).

**Implementation:**

Append to the end of the existing Step 7 paragraph (after "...`/merge`'s final report tells you what post-merge did."):

```markdown
A second standard sub-step runs unconditionally, on every merge: post-merge ends its report with a short **Problem/Opportunity → What shipped** summary (chat only — no new file), preferring the `planning.md` diff `/code` already wrote, falling back to the spec's framing or the PR title.
```

**Acceptance Test:**

```bash
grep -n "Problem/Opportunity" /home/rich/dev/skills/WORKFLOW_MANUAL.md
./scripts/gate_fast.sh
```

---

### Change 4: Restructure `/merge` Step 7 to generate the summary unconditionally

**Problem:** `commands/merge.md`'s Step 7 ([commands/merge.md:145-162](../commands/merge.md#L145-L162)) currently stops immediately at sub-step 2 ("No spec touched → report 'no post-merge step' and stop here") for any chore/fix merge — exactly the class of merge with no other post-merge output today, and exactly the class Tier 3 (PR title fallback) exists to cover. The summary must be produced BEFORE that early exit, every time, regardless of what (if anything) runs after it.

**File:** `/home/rich/dev/commands/merge.md` (existing — Step 7, lines ~145-162, and the Rules section at line ~164-172).

**Implementation:**

Replace the existing Step 7 body (numbered sub-steps 1-6, lines 149-162) with the following renumbered sequence. The new sub-step 2 (Change Summary) is inserted between the existing sub-steps 1 (find the spec) and 2 (no-spec early exit); everything from the old sub-step 2 onward shifts down by one number, unchanged in behavior except that the early exit no longer means "nothing happened" — it now means "nothing further happens."

```markdown
1. **Find the spec.** Look at `tasks/*-spec.md` files added/modified in `git diff HEAD~1 --name-only` for the just-merged commit.
2. **Generate the Change Summary — runs every time, unconditionally, before anything else below.** Produce a short **Problem/Opportunity → What shipped** summary using this fallback order (stop at the first tier that yields content):
   - **Tier 1 (preferred):** `git diff HEAD~1 HEAD -- planning.md`. If this shows added lines under a "Recently shipped" (or equivalently-named changelog) section, use that prose directly — lightly trimmed if needed, not rewritten. This is the text `/code` already wrote pre-commit, already reviewed by `/review`.
   - **Tier 2:** If `planning.md` wasn't touched by this merge but Step 1 found a spec, use the spec's Problem statement / Design Philosophy opening + its Change titles from the Overview section.
   - **Tier 3:** If no spec was touched either, use `gh pr view "${PR_NUM}" --json title,body` — the PR title as "What shipped", and the first line of the body (or the title itself if the body is empty) as "Problem/Opportunity".
   - Print it in the final report (Step 6 below) as:

     ```text
     ## Change Summary
     **Problem/Opportunity:** <one to three sentences>
     **What shipped:** <one to three sentences or a short bullet list>
     ```

   - This sub-step never blocks or stops the rest of Step 7 — it only produces text for the final report.
3. **No spec touched** (e.g. a chore PR): report "no further post-merge step — this PR is fully shipped" (the Change Summary from sub-step 2 still appears in the report) and stop here.
4. **Spec has a "Post-merge step" section:** execute its actions now, exactly as written — the spec is the runbook. These are bespoke per project (branch-protection updates, release-tag cuts, Pages-enable, `sync-milestones --apply`, cross-project re-installs, etc.). If a listed action is unusually high-blast-radius for an ordinary post-merge step (e.g. a prod deploy, a credential rotation, anything touching a shared system beyond this repo) — flag it and confirm before running it, same as any other hard-to-reverse action; everything else in the spec's normal post-merge shape just runs.
5. **Detect Roadmap-Phase completion**, whether or not the spec had its own Post-merge section. Determine whether this merge shipped the *last Change of a Roadmap Phase*:
   - Read the just-merged spec. If its Overview lists Changes across Phases and this PR merged the final Phase's last Change, the phase is complete. A single-PR-per-spec change completing the spec also completes its Roadmap Phase.
   - A phase can also be complete by an explicit **scope decision** recorded in the spec or PR (a planned item dropped) — treat that the same as code-complete.
   - If complete, **execute the standard Roadmap-Phase-completion actions**: mark the phase complete in `ROADMAP.md` + `planning.md` (today's date + status), close the GitHub milestone (`gh api -X PATCH repos/:owner/:repo/milestones/<n> -f state=closed`, or `./scripts/sync-milestones.sh --apply` where the project ships it), and verify with `./scripts/check-phase-milestones.sh`.
   - If this merge did NOT complete a phase (a mid-phase Change), say so explicitly: "mid-phase merge — no phase-completion step." and continue to Step 6 (nothing further to commit from this sub-step).
6. **Land any file changes from steps 4-5.** If the project's rules forbid direct commits to `main` (check its CLAUDE.md), run the SAME mini-cycle this skill already knows how to do — reuse Steps 1-5 above on a fresh branch:
   - Cut a branch (`chore/<slug>` per this project's naming convention), commit the doc/config changes, push.
   - Run the project's local gate (`./scripts/gate_fast.sh` or equivalent) before committing — same rule as any other commit. A docs-only diff should be fast; if the project's gate doesn't already skip its expensive legs (test suite, lint, typecheck) for a diff touching only docs/roadmap files, that's worth a separate follow-on, not a reason to skip the gate here.
   - Open the PR (`gh pr create`), then run Steps 2-5 of THIS skill against it: poll CI, verify green, squash-merge, sync local main. This is the one case `/merge` calls its own logic recursively — it's still gated by the same non-overridable CI-green check as any other merge.
   - If the project instead permits a direct-to-`main` trivial-edit path for pure doc/roadmap changes, use that instead — it's faster and the outcome is identical.
7. **Report what post-merge did** — starting with the Change Summary block from sub-step 2, then the actions taken (files changed, milestone closed, doc-update PR's own merge commit SHA if sub-step 6 ran), or "nothing further to do" if sub-steps 4-5 found nothing.
```

Add a matching Rules bullet after the existing "**Post-merge is folded into `/merge`...**" bullet ([commands/merge.md:170](../commands/merge.md#L170)):

```markdown
- **The Change Summary always runs, even on a spec-less chore merge.** It is the one sub-step of post-merge that isn't gated on a spec being touched or a phase completing — every `/merge` report ends with it. It is chat-report-only: never write it to a file, never post it externally (no CHANGELOG, no GitHub Release, no PR comment) unless a future spec explicitly asks for that.
```

**Acceptance Test:**

```bash
grep -n "Generate the Change Summary" /home/rich/dev/commands/merge.md
grep -n "runs every time, unconditionally" /home/rich/dev/commands/merge.md
grep -n "even on a spec-less chore merge" /home/rich/dev/commands/merge.md
grep -n "no further post-merge step" /home/rich/dev/commands/merge.md   # old wording updated, not just appended-around
./scripts/gate_fast.sh   # frontmatter validator + taxonomy suites still pass (merge.md frontmatter untouched)
```

---

## Phase 1 (docs): Change 5 — v1.15 doc updates

### Change 5: v1.15 ROADMAP / planning / README updates

**Problem:** `/code` Step 7 mandates doc updates bundled into the implementing commit; this spec ships a new Roadmap Phase (v1.15) with no new script or test suite, but the docs must still record it.

**File:** `ROADMAP.md`, `planning.md`, `README.md` (all existing).

**Implementation:**

- `ROADMAP.md`: add a `v1.15: Post-Merge Change Summary` entry in the existing list-form bullet format, describing the second standard post-merge sub-step (unconditional Problem/Opportunity → What shipped, chat-report only, 3-tier fallback). Mark it complete with today's date when the work lands (per `/code`'s doc step, not now).
- `planning.md`: update "Active spec" / "Active Roadmap Phase" / "In flight" to reflect v1.15, following the exact prose pattern of the v1.14 entry it's replacing. Add the "Recently shipped" bullet for v1.15 — note this bullet is itself the Tier-1 source `/merge`'s new Change Summary sub-step will read back when THIS spec's own PR merges (a natural self-test, worth calling out live during `/code`'s or `/merge`'s dogfooding but not required as a separate acceptance test).
- `README.md`: only touch it if it lists specific post-merge sub-steps or the workflow chain description by name (grep first; do not add speculative content).

**Acceptance Test:**

```bash
grep -n "v1.15" /home/rich/dev/ROADMAP.md
grep -n "v1.15\|Change Summary" /home/rich/dev/planning.md
./scripts/check_spec_taxonomy.sh                  # ROADMAP/planning still taxonomy-clean
```

---

## What NOT to Do

- **Do NOT write the summary to any file, CHANGELOG, GitHub Release, or PR comment.** The user explicitly chose chat-report-only over three other options (new CHANGELOG.md, reusing planning.md silently, or posting externally via `gh`) when this was scoped. Revisit only if the user asks for a durable/external form in a future spec.
- **Do NOT regenerate the summary from a fresh read of the whole diff.** The design is deliberately "surface what already exists" — Tier 1 reads `planning.md`'s own diff verbatim (lightly trimmed at most), not a re-authored summary. Re-authoring from scratch defeats the "derived from context already available" requirement and risks drifting from what `/review` already approved in the `planning.md` bullet.
- **Do NOT touch `audit-project-drift.sh`, `migrate-workflow-chain.sh`, or the chain-string detection regex.** This spec adds behavior INSIDE the existing `post-merge` box; the chain string (`/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`) is unchanged. No consumer-project propagation is needed beyond the normal "sessions read `CLAUDE.md`" path.
- **Do NOT skip the Change Summary when no spec was touched.** That's precisely backwards — a spec-less chore/fix merge is the case that most needs Tier 3 (the PR title fallback), because today it gets zero post-merge output at all.
- **Do NOT make the Change Summary block CI, block the merge, or gate anything.** It's report-only text generation with no exit-code implications; a failure to produce a good summary (e.g. a nearly-empty PR body in Tier 3) degrades to a terse summary, never an error.
- **Do NOT write a bare review-less chain string** (`…/code → /gate fast…` as a chain example) into `dev/CLAUDE.md` — `audit-project-drift.sh` greps it and would self-flag the repo (recurring "detector self-matches documentation" hazard). Verify `audit --project dev-platform` reports CLEAN before commit.
- **Do NOT add a new script or test suite for this.** There's no runtime behavior to unit test — Tier 1-3 are agent-followed instructions in `commands/merge.md`, the same category as the rest of Step 7's existing bespoke-post-merge and phase-completion-detection prose, none of which has dedicated test coverage either.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `CLAUDE.md` | Modify | Add the second standard post-merge sub-step (Change Summary) to the post-merge bullet (Change 1) |
| `settings/claude-global.md` | Modify | Name the Change Summary sub-step, pointing at `dev/CLAUDE.md` (Change 2) |
| `skills/WORKFLOW_MANUAL.md` | Modify | Extend "Step 7: Post-merge" to document the unconditional summary (Change 3) |
| `commands/merge.md` | Modify | Step 7 restructured: summary generation runs before the no-spec early exit; renumbered sub-steps; new Rules bullet (Change 4) |
| `ROADMAP.md` | Modify | `v1.15: Post-Merge Change Summary` entry (Change 5) |
| `planning.md` | Modify | Record v1.15; update Active Roadmap Phase / In flight (Change 5) |
| `README.md` | Modify (if applicable) | Only if it names post-merge sub-steps explicitly (Change 5) |

## Implementation Order

1. **Change 1** (`dev/CLAUDE.md`) — source-of-truth doc for the new sub-step.
2. **Change 2** (`settings/claude-global.md`) — points at Change 1.
3. **Change 3** (`skills/WORKFLOW_MANUAL.md`) — points at Change 1.
4. **Change 4** (`commands/merge.md`) — implements the actual behavior; references the shape documented in Changes 1-3.
5. **Change 5** (docs) — `/code` Step 7; reflects everything above. Run `./scripts/gate_fast.sh` green before reporting.

Dependencies: Change 4 depends on Changes 1-3 being settled first (so the instructions it encodes match the documented shape exactly). Change 5 depends on all.

## Verification Checklist

- [ ] `dev/CLAUDE.md` post-merge bullet names the second standard sub-step (Change Summary) alongside the existing Roadmap-Phase-completion one, with the 3-tier fallback order stated (Change 1)
- [ ] `audit-project-drift.sh --project dev-platform` reports CLEAN — no self-flag from the edit (Change 1)
- [ ] `settings/claude-global.md` + `WORKFLOW_MANUAL.md` state the step concisely and point at `dev/CLAUDE.md` (Changes 2, 3)
- [ ] `/merge` Step 7's new sub-step 2 runs BEFORE the no-spec early exit (now sub-step 3), so a spec-less chore merge still produces a summary (Change 4)
- [ ] `/merge` Step 7's summary sub-step implements all 3 fallback tiers in the documented order (Change 4)
- [ ] New Rules bullet states the summary is chat-report-only, never written to a file or posted externally (Change 4)
- [ ] `ROADMAP.md` has the v1.15 entry; `planning.md` records v1.15 as current (Change 5)
- [ ] `./scripts/gate_fast.sh` PASSes; `./scripts/check_spec_taxonomy.sh` clean
- [ ] No new script or test suite added (none needed — instruction-file change only)
- [ ] Language architecture matrix followed (Markdown/prose only — no code component to evaluate)
