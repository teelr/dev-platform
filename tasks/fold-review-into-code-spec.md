# Fold Review Into Code

## Coding Specification for Implementation

## Design Philosophy

`/review` has been a mandatory chain step since v1.3 (2026-06-07) — every single `/code` turn is followed by an explicit `/review` invocation, with zero exceptions in this repo's own history. The separate invocation has never once been skipped or redirected; it is pure ceremony at this point. This mirrors exactly the situation v1.10/v1.13 solved for `/merge` → `post-merge`: a step that "has followed every single [predecessor] in practice," where the extra invocation "was pure friction" (the precise words `CLAUDE.md`'s existing exception already uses for that fold).

This spec applies the identical fold to `/code` → `/review`: `/code` now runs `/review`'s full procedure itself, as its own step, in the same turn — no separate invocation required. Everything about `/review`'s own contract is unchanged (SECURITY/BUG/COMPLIANCE/QUALITY auto-fixed, ARCHITECTURE surfaced for the user, its own report format) — only the *invocation* boundary moves. `/review` remains a real, independent, standalone-invokable command for the recovery case (re-reviewing after manual edits post-`/code`, or resuming an interrupted `/code` session that never got to its review step) — it is not deleted or merged away, exactly as `commands/merge.md` still exists standalone even though `post-merge` normally never needs a separate invocation either.

**The one hard constraint, stated explicitly by the user:** the STOP-and-wait boundary must NOT move to after `/gate fast`. It stays exactly where it already sits today — immediately after `/review` finishes, before `/gate fast` runs. Folding `/code` → `/review` together does not fold `/review` → `/gate fast` together; those remain two separate turns. This is the same shape as the `/merge`/`post-merge` fold: `/merge` and `post-merge` combine into one turn, but that combined turn still ends and nothing after it (the next `/plan`) auto-starts.

**Precedent to mirror, not invent:** `commands/merge.md`'s Step 7 ("Run post-merge automatically") is the exact template for this fold — same framing ("owns X — it runs immediately, in the same turn, no separate invocation. Do NOT stop and wait for the user to ask for it"), same "Exception:" paragraph shape in `settings/claude-global.md`, same before/after bullet restructuring in `CLAUDE.md`'s chain description, same "(automatic, part of `/X`)" heading suffix in `skills/WORKFLOW_MANUAL.md`. Read `commands/merge.md` Step 7 and the three contract files' existing post-merge language before writing this spec's Changes — this spec's job is to apply the same shape to a different pair of steps, not design something new.

**Chain string does NOT change.** `/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge` stays byte-identical everywhere it appears. Only the *step-discipline prose* (which arrows are stop-and-wait boundaries vs. auto-chained) changes. This matters because `scripts/migrate-workflow-chain.sh` and `scripts/audit-project-drift.sh` both grep for the literal substring `/code → /review` (a CLEAN/fixed indicator) and `/code → /gate fast` (a DRIFT/review-less indicator) inside `CLAUDE.md` — since this spec never removes or alters that substring, both detectors continue working with zero changes, and every consumer project inherits the new step-discipline prose automatically the next time its session reads `CLAUDE.md` (no separate per-project migration, same as v1.15).

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| Contract-file edits (`CLAUDE.md`, `settings/claude-global.md`, `skills/WORKFLOW_MANUAL.md`) | Markdown | Documentation of the workflow step; not code. |
| `commands/code.md` / `commands/review.md` edits | Markdown (agent instructions) | Same category as every other slash-command file in this repo — not source code, no language-matrix component. |

No new script, no new test suite — instruction-file change only, same class as v1.15 and v1.7.

## Overview

- Change 1: `commands/code.md` — insert a new step that auto-runs `/review`'s full procedure, renumber the final report step, and update its "Ready for X" line.
- Change 2: `commands/review.md` — note the dual invocation mode (auto-run by `/code`, or standalone for recovery) in the frontmatter description and opening paragraph; no change to its actual review contract (Steps 1-5 unchanged).
- Change 3: `CLAUDE.md` — update the Development Workflow exception sentence (two exceptions now, not one) and the `/code`/`/review` chain bullets.
- Change 4: `settings/claude-global.md` — update the Workflow Step Discipline stop-list and add the matching exception paragraph; update the full-chain summary sentence.
- Change 5: `skills/WORKFLOW_MANUAL.md` — update the `/code` and `/review` skill descriptions, the "one arrow isn't a separate invocation" sentence (now two arrows), and the Step 2/Step 4 numbered walkthrough.
- Change 6: Roadmap/planning doc updates for v1.16.

---

## Phase 1: Fold the step + update the three contract files

### Change 1: `commands/code.md` — auto-run `/review`, renumber the report step

**Problem:** `commands/code.md`'s Step 9 ([commands/code.md:187-193](../commands/code.md#L187-L193)) ends the turn and tells the user `/review` is next, mandatory, requiring their own separate invocation. That invocation has never once been skipped in this repo's history — the user wants it auto-run, same turn, exactly like `commands/merge.md`'s Step 7 already auto-runs post-merge.

**File:** `/home/rich/dev/commands/code.md` (existing — insert a new step between the current Step 8 "Security Reminder" ([commands/code.md:173-185](../commands/code.md#L173-L185)) and the current Step 9 "Report" ([commands/code.md:187-193](../commands/code.md#L187-L193)); renumber Step 9 to Step 10).

**Implementation:**

Insert a new step, after Step 8's body and before the current `## Step 9: Report — Next Step Is Mandatory \`/review\`` heading:

```markdown
## Step 9: Run `/review` Automatically

`/code` owns the independent review pass — it runs immediately, in the same turn, with no separate invocation. Do NOT stop and wait for the user to ask for it.

Run the review procedure exactly as documented in `commands/review.md` Steps 1-5, unchanged:

1. Gather the staged diff (`git diff --cached`); if nothing is staged, fall back to the unstaged diff — `commands/review.md` Step 1 already handles both cases, and `/code` does not need to pre-stage anything beyond what Step 7 already staged (the doc updates).
2. Load `./CLAUDE.md` and `~/.claude/CLAUDE.md`.
3. Review every changed file across SECURITY, BUG, COMPLIANCE, QUALITY, and ARCHITECTURE (Language Architecture Decision Matrix compliance).
4. Fix SECURITY, BUG, COMPLIANCE, and QUALITY issues immediately — do not wait for approval. Re-read each fixed file to confirm the fix is correct. Surface ARCHITECTURE issues for the user's decision; do NOT fix them.
5. Produce the `# Code Review` report exactly as `commands/review.md` Step 5 defines it (Files reviewed, Verdict, Fixes Applied by category, Needs Your Decision / ARCHITECTURE, Summary).

This review pass is independent of Step 6's Adversarial Self-Review — it is the fresh-eyes backstop `/code` structurally cannot be by re-reading its own diff, run here as `/code`'s own final action rather than a separately invoked command. If any ARCHITECTURE issues surface, they are still unresolved when this step ends — carry them into Step 10's report exactly as `commands/review.md` would.
```

Then replace the old Step 9 heading and body ([commands/code.md:187-193](../commands/code.md#L187-L193)):

```markdown
## Step 9: Report — Next Step Is Mandatory `/review`

`/review` is a mandatory gate in the canonical chain (`/plan → /code → /review → /gate fast → …`), not an optional extra. Your Step 6 adversarial self-review does NOT satisfy it — `/review` is the independent fresh-eyes pass you structurally cannot be.

End your report with:

> Ready for `/review` (mandatory) → then `/gate fast`.
```

with (renumbered to Step 10):

```markdown
## Step 10: Report — Next Step Is `/gate fast`

Combine this turn's report: the implementation summary (Changes completed, Step 7's doc updates, Step 8's security reminder if applicable) followed by Step 9's `# Code Review` report block.

If Step 9 found ARCHITECTURE issues, they are unresolved — surface them clearly; the user must decide before proceeding.

End your report with:

> Ready for `/gate fast`.
```

**Acceptance Test:**

```bash
grep -n "Run \`/review\` Automatically" /home/rich/dev/commands/code.md
grep -n "Report — Next Step Is \`/gate fast\`" /home/rich/dev/commands/code.md
grep -n "Report — Next Step Is Mandatory" /home/rich/dev/commands/code.md   # should NOT match anymore (old heading replaced)
grep -n "Ready for \`/gate fast\`" /home/rich/dev/commands/code.md
```

---

### Change 2: `commands/review.md` — document the dual invocation mode

**Problem:** `commands/review.md`'s frontmatter description and opening paragraph ([commands/review.md:1-10](../commands/review.md#L1-L10)) describe `/review` as if it is always separately invoked ("running between `/code` and `/gate fast` on every change"). After Change 1, that's only true for the standalone-recovery case — the normal case is `/code` invoking this same procedure inline. The review CONTRACT (what it checks, what it fixes, its report format) does not change at all.

**File:** `/home/rich/dev/commands/review.md` (existing — frontmatter `description` at line 2, opening paragraph at lines 6-10).

**Implementation:**

Update the frontmatter `description` (line 2):

```yaml
description: Independent review gate on staged (or unstaged) git changes. Normally auto-run by /code as its own final step — no separate invocation needed. Also invokable standalone for a fresh pass, e.g. after manual edits post-/code, or to resume an interrupted /code session. The fresh-eyes pass /code cannot be.
```

Update the opening paragraph (lines 8-10) — after the existing sentence ending "...you are the fresh-eyes backstop `/code` structurally cannot be.", append:

```markdown
`/code` normally runs this exact procedure itself, automatically, as its own final step — see `commands/code.md` Step 9. You are being invoked standalone here for one of two reasons: a fresh re-review after manual edits made after `/code` finished, or resuming a `/code` session that was interrupted before its own review step ran. Either way, the procedure below is identical — nothing about what gets checked or fixed changes based on who invoked it.
```

Do not change anything else in the file — Steps 1-5 and the Rules section are the single source of truth `commands/code.md` Step 9 points at; duplicating them there would create two copies to keep in sync.

**Acceptance Test:**

```bash
grep -n "Normally auto-run by /code" /home/rich/dev/commands/review.md
grep -n "commands/code.md Step 9" /home/rich/dev/commands/review.md
diff <(sed -n '12,152p' /home/rich/dev/commands/review.md) <(git show HEAD:commands/review.md | sed -n '12,152p')   # Steps 1-5 + Rules body untouched by this Change (line numbers may shift by the paragraph insertion; confirm by eye that Step 1 through the Rules section still reads identically)
```

---

### Change 3: `CLAUDE.md` — two exceptions, not one; updated `/code`/`/review` bullets

**Problem:** `CLAUDE.md`'s Development Workflow section ([CLAUDE.md:99-111](../CLAUDE.md#L99-L111)) states "**The one exception is `/merge` → post-merge**" and describes `/code` and `/review` as two separately-invoked bullets. Both need updating for the new fold.

**File:** `/home/rich/dev/CLAUDE.md` (existing — line ~101 exception sentence, lines ~109-111 chain bullets).

**Implementation:**

Replace line 101:

```markdown
Each step requires the user to invoke it. Completing one step does NOT mean start the next. Stop and wait. End-of-step "Ready for X" format is defined in `settings/claude-global.md`. **The one exception is `/merge` → post-merge** — `/merge` runs post-merge itself, no separate invocation (see below).
```

with:

```markdown
Each step requires the user to invoke it. Completing one step does NOT mean start the next. Stop and wait. End-of-step "Ready for X" format is defined in `settings/claude-global.md`. **Two exceptions:** `/code` → `/review` does NOT stop — `/code` runs `/review` itself as its own final step, no separate invocation (see below); and `/merge` → post-merge does NOT stop — `/merge` runs post-merge itself, no separate invocation (see below). Every other step boundary in the chain still stops and waits — critically, the boundary immediately AFTER `/review` (before `/gate fast`) is unaffected by the first exception: `/code` and `/review` combine into one turn, but that combined turn still stops before `/gate fast` runs.
```

Replace the `/code` and `/review` bullets (lines 110-111):

```markdown
- **`/code`** — Implements Change by Change with auto-fix. Updates project docs (planning.md, ROADMAP.md, README.md, lessons.md) as its final step. Feature code + doc updates commit together.
- **`/review`** — Independent fresh-eyes pass on the staged diff. Catches logic errors that still compile, edge cases, and security issues a green build won't surface. Auto-fixes SECURITY / BUG / COMPLIANCE / QUALITY; surfaces ARCHITECTURE for user decision. **Mandatory on every change.**
```

with:

```markdown
- **`/code`** — Implements Change by Change with auto-fix. Updates project docs (planning.md, ROADMAP.md, README.md, lessons.md) as its final step, **then runs `/review` itself in the same turn** — no separate invocation needed. Feature code + doc updates commit together.
- **`/review`** — Independent fresh-eyes pass on the staged (or unstaged, if nothing's staged) diff. Catches logic errors that still compile, edge cases, and security issues a green build won't surface. Auto-fixes SECURITY / BUG / COMPLIANCE / QUALITY; surfaces ARCHITECTURE for user decision. **Mandatory on every `/code` turn** — normally auto-run by `/code`, same turn (see the exception above); also invokable standalone for a fresh pass.
```

Leave the "Quick fixes" line ([CLAUDE.md:128](../CLAUDE.md#L128)) unchanged — quick fixes never invoke `/code`, so `/review` stays a separately-invoked step there. Leave the compact chain-summary bullet under Patterns ([CLAUDE.md:363](../CLAUDE.md#L363)) unchanged — it lists chain ORDER, which does not change.

Do NOT introduce the literal review-less chain string `…/code → /gate fast…` anywhere in this edit — `audit-project-drift.sh`'s DRIFT detector greps dev-platform's own `CLAUDE.md` for it (recurring hazard, lessons 2026-05-11 / 2026-06-07 / 2026-08-20). The canonical chain string at [CLAUDE.md:106](../CLAUDE.md#L106) is unchanged by this spec — do not touch it.

**Acceptance Test:**

```bash
grep -n "Two exceptions" /home/rich/dev/CLAUDE.md
grep -n "then runs \`/review\` itself in the same turn" /home/rich/dev/CLAUDE.md
grep -n "normally auto-run by \`/code\`" /home/rich/dev/CLAUDE.md
./scripts/audit-project-drift.sh --project dev-platform | grep -E "dev-platform.*CLEAN"   # still CLEAN, no self-flag
./scripts/gate_fast.sh
```

---

### Change 4: `settings/claude-global.md` — stop-list + exception paragraph + chain summary

**Problem:** `settings/claude-global.md`'s Workflow Step Discipline section ([settings/claude-global.md:16-38](../settings/claude-global.md#L16-L38)) is the file every session actually loads at startup (deployed as `~/.claude/CLAUDE.md`) — it lists `/code` in the stop-trigger list and describes only the `/merge`→post-merge exception. Same gap as Change 3, in the file that governs live session behavior.

**File:** `/home/rich/dev/settings/claude-global.md` (existing — lines 16-38).

**Implementation:**

Replace the stop-trigger sentence:

```markdown
After `/plan`, `/code`, `/review`, `/gate`, `commit`, `push`, `/pr`, or `post-merge`: report results, state which step is next, then STOP and wait for the user to invoke it explicitly. Do NOT auto-advance.
```

with (drop `/code` — mirrors how `/merge` itself is already absent from this list since it always chains into post-merge before the turn ends):

```markdown
After `/plan`, `/review`, `/gate`, `commit`, `push`, `/pr`, or `post-merge`: report results, state which step is next, then STOP and wait for the user to invoke it explicitly. Do NOT auto-advance.
```

Replace the existing single-exception sentence:

```markdown
**Exception: `/merge` → `post-merge` does NOT stop.** `/merge` runs post-merge itself as its own final step (see the `merge` skill) — the user has pre-authorized this because post-merge has followed every single merge in practice, so the separate invocation was pure friction. Every other step boundary in the chain still stops and waits.
```

with:

```markdown
**Exception: `/code` → `/review` does NOT stop.** `/code` runs `/review` itself as its own final step (see the `code` skill) — the user has pre-authorized this because `/review` has followed every single `/code` turn in practice, so the separate invocation was pure friction. This fold does NOT move where the workflow stops: it still stops immediately after `/review` finishes, before `/gate fast` — only the `/code`→`/review` boundary is gone, not the `/review`→`/gate fast` boundary.

**Exception: `/merge` → `post-merge` does NOT stop.** `/merge` runs post-merge itself as its own final step (see the `merge` skill) — the user has pre-authorized this because post-merge has followed every single merge in practice, so the separate invocation was pure friction. Every other step boundary in the chain still stops and waits.
```

Update the full-chain summary sentence:

```markdown
The full chain: `/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`. `/review` is a mandatory independent review gate on every change. `/security-review` is optional for changes touching auth, credentials, external input, or new endpoints. `/test` and `/docs` are standalone — `/code` handles verification, auto-fix, and doc updates internally.
```

to:

```markdown
The full chain: `/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`. `/review` is a mandatory independent review gate on every change, normally auto-run by `/code` as its own final step (no separate invocation needed — see the exception above) and also invokable standalone for a fresh pass. `/security-review` is optional for changes touching auth, credentials, external input, or new endpoints. `/test` and `/docs` are standalone — `/code` handles verification, auto-fix, and doc updates internally.
```

**Acceptance Test:**

```bash
grep -n "After \`/plan\`, \`/review\`, \`/gate\`" /home/rich/dev/settings/claude-global.md   # /code dropped from the stop-list
grep -c "Exception:" /home/rich/dev/settings/claude-global.md   # now 2
grep -n "normally auto-run by \`/code\`" /home/rich/dev/settings/claude-global.md
./scripts/gate_fast.sh
```

---

### Change 5: `skills/WORKFLOW_MANUAL.md` — skill descriptions + chain narrative + walkthrough

**Problem:** `skills/WORKFLOW_MANUAL.md` documents `/code` and `/review` as separately-invoked skills ([skills/WORKFLOW_MANUAL.md:49-73](../skills/WORKFLOW_MANUAL.md#L49-L73), [skills/WORKFLOW_MANUAL.md:106-130](../skills/WORKFLOW_MANUAL.md#L106-L130)), states "`/merge → post-merge` is the ONE arrow in this chain that isn't a separate invocation" ([skills/WORKFLOW_MANUAL.md:140](../skills/WORKFLOW_MANUAL.md#L140) — now false, there are two), and walks through `/code` (Step 2) and `/review` (Step 4) as distinct numbered steps in the feature-development walkthrough ([skills/WORKFLOW_MANUAL.md:150-172](../skills/WORKFLOW_MANUAL.md#L150-L172)).

**File:** `/home/rich/dev/skills/WORKFLOW_MANUAL.md` (existing).

**Implementation:**

In the `/code` skill's "What it does" list (around [skills/WORKFLOW_MANUAL.md:60-66](../skills/WORKFLOW_MANUAL.md#L60-L66)), the 5-item list currently ends with "5. Flags any deviations from the spec". Add a 6th item:

```markdown
6. Runs `/review`'s full procedure itself as its own final step — auto-fixing SECURITY/BUG/COMPLIANCE/QUALITY issues, surfacing ARCHITECTURE issues — no separate invocation needed.
```

In the `/review` section's opening ([skills/WORKFLOW_MANUAL.md:106-116](../skills/WORKFLOW_MANUAL.md#L106-L116)), after the existing "Reviews staged git changes before committing." sentence, add:

```markdown
Normally auto-run by `/code` as its own final step — no separate invocation needed. Also invokable standalone for a fresh re-review after manual edits, or to resume a `/code` session interrupted before its review step ran.
```

Replace the chain-narrative sentence ([skills/WORKFLOW_MANUAL.md:140](../skills/WORKFLOW_MANUAL.md#L140)):

```markdown
`/review` is **mandatory** on every change — it runs after `/code` and before `/gate fast`. `/test` and `/docs` are standalone helpers, not gates in the chain. `/merge → post-merge` is the one arrow in this chain that isn't a separate invocation: `/merge` runs post-merge itself as its final step (see Step 7). Every other arrow is still a stop-and-wait boundary.
```

with:

```markdown
`/review` is **mandatory** on every change — it runs after `/code` and before `/gate fast`. `/test` and `/docs` are standalone helpers, not gates in the chain. Two arrows in this chain aren't separate invocations: `/code → /review` (see Step 4) and `/merge → post-merge` (see Step 7) — each runs its second half itself, same turn. Every other arrow is still a stop-and-wait boundary, including the arrow right after the folded `/review` half: the workflow still stops before `/gate fast` runs.
```

Replace Step 4's heading and body ([skills/WORKFLOW_MANUAL.md:166-172](../skills/WORKFLOW_MANUAL.md#L166-L172)):

```markdown
### Step 4: Review (mandatory)

```
/review
```

Stage your changes (`git add`), then run review. **Mandatory on every change** — it runs after `/code` and before `/gate fast`. Auto-fixes SECURITY / BUG / COMPLIANCE / QUALITY; surfaces ARCHITECTURE for your decision.
```

with:

```markdown
### Step 4: Review (automatic, part of `/code`)

`/code` runs this itself, immediately after updating project docs — it's the last thing `/code` does, not a step you invoke afterward. **Mandatory on every `/code` turn** — auto-fixes SECURITY / BUG / COMPLIANCE / QUALITY; surfaces ARCHITECTURE for your decision. The workflow stops right after this finishes, before `/gate fast` — review the `# Code Review` report block in `/code`'s final output before moving on.
```

Leave Step 2 ("Code") and Step 3 ("Test — standalone, optional") and Step 5 ("Commit") headings/numbering unchanged — Step 4 keeps its existing number in the walkthrough (it still describes a real, distinct phase of work, just now folded into Step 2's turn rather than separately invoked).

Leave the "Workflow: Quick Fix (No Spec Needed)" section ([skills/WORKFLOW_MANUAL.md:186-192](../skills/WORKFLOW_MANUAL.md#L186-L192)) unchanged — quick fixes skip `/code` entirely, so `/review` remains a separately-invoked step there.

**Acceptance Test:**

```bash
grep -n "no separate invocation needed" /home/rich/dev/skills/WORKFLOW_MANUAL.md   # appears at least twice (/code list item + /review section)
grep -n "Two arrows in this chain" /home/rich/dev/skills/WORKFLOW_MANUAL.md
grep -n "Step 4: Review (automatic, part of" /home/rich/dev/skills/WORKFLOW_MANUAL.md
grep -n "Step 4: Review (mandatory)" /home/rich/dev/skills/WORKFLOW_MANUAL.md   # should NOT match anymore
./scripts/gate_fast.sh
```

---

## Phase 1 (docs): Change 6 — v1.16 doc updates

### Change 6: v1.16 ROADMAP / planning updates

**Problem:** `/code` Step 7 mandates doc updates bundled into the implementing commit; this spec ships a new Roadmap Phase (v1.16) with no new script or test suite, but the docs must still record it.

**File:** `ROADMAP.md`, `planning.md` (both existing).

**Implementation:**

- `ROADMAP.md`: add a `v1.16: Fold Review Into Code` entry in the existing list-form bullet format, describing the fold (mirrors v1.15's own entry shape). Mark it complete with today's date when the work lands (per `/code`'s doc step, not now).
- `planning.md`: update "Active spec" / "Active Roadmap Phase" / "In flight" to reflect v1.16, following the exact prose pattern of the v1.15 entry it's replacing (per the convention already established across v1.10-v1.15). Add the "Recently shipped" bullet for v1.16.
- `README.md`: only touch it if it names the `/code`/`/review` invocation relationship explicitly (grep first; do not add speculative content — same guardrail as v1.15's Change 5).

**Acceptance Test:**

```bash
grep -n "v1.16" /home/rich/dev/ROADMAP.md
grep -n "v1.16" /home/rich/dev/planning.md
./scripts/check_spec_taxonomy.sh                  # ROADMAP/planning still taxonomy-clean
```

---

## What NOT to Do

- **Do NOT move the STOP boundary to after `/gate fast`.** This is the user's explicit, non-negotiable constraint. `/code` and `/review` combine into one turn; that combined turn still ends with "Ready for `/gate fast`" and the workflow stops there, exactly as it does today.
- **Do NOT delete or gut `commands/review.md`.** It remains the single source of truth for the review procedure and stays fully invokable standalone (recovery / re-review case). `commands/code.md` Step 9 points at it rather than duplicating its ~150 lines inline — duplicating would create two copies of the same procedure to keep in sync, the exact class of drift this repo's "single source of truth, other files point at it" convention (already used for the `CLAUDE.md`/`settings/claude-global.md`/`WORKFLOW_MANUAL.md` triad) exists to prevent.
- **Do NOT touch the chain string** (`/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`) anywhere it appears. Only step-discipline prose (which arrows stop, which don't) changes.
- **Do NOT touch `scripts/migrate-workflow-chain.sh` or `scripts/audit-project-drift.sh`.** Both grep for the literal chain-string substrings `/code → /review` (CLEAN indicator) and `/code → /gate fast` (DRIFT indicator) — since the chain string is unchanged, both detectors keep working with zero code changes. Verify with `audit-project-drift.sh --project dev-platform` reporting CLEAN, not by editing the detectors.
- **Do NOT change `/review`'s actual review contract** (what it checks, what it auto-fixes vs. surfaces, its report format). This spec only changes who/what invokes it and when — Steps 1-5 of `commands/review.md` are untouched.
- **Do NOT change the Quick Fix workflow** (`skills/WORKFLOW_MANUAL.md`'s "Workflow: Quick Fix" section, `CLAUDE.md`'s "Quick fixes" line). Quick fixes never invoke `/code`, so `/review` stays a separately-invoked step there — this spec's fold is specifically the `/code`→`/review` boundary.
- **Do NOT add a new script or test suite.** There's no runtime behavior to unit test — this is an instruction-file change across 5 files, same class as v1.15 and v1.7.
- **Do NOT write a bare review-less chain string** (`…/code → /gate fast…` as a chain example, outside the one pre-existing occurrence already documented) into `CLAUDE.md` — `audit-project-drift.sh` greps it and would self-flag the repo. Verify `audit --project dev-platform` reports CLEAN before commit.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `commands/code.md` | Modify | New Step 9 auto-runs `/review`; old Step 9 renumbered to Step 10 with updated "Ready for" line (Change 1) |
| `commands/review.md` | Modify | Frontmatter description + opening paragraph note the dual invocation mode; Steps 1-5 + Rules untouched (Change 2) |
| `CLAUDE.md` | Modify | Two-exception sentence; updated `/code`/`/review` chain bullets (Change 3) |
| `settings/claude-global.md` | Modify | Stop-list drops `/code`; second Exception paragraph; updated full-chain sentence (Change 4) |
| `skills/WORKFLOW_MANUAL.md` | Modify | `/code`/`/review` skill descriptions; "two arrows" narrative; Step 4 heading + body (Change 5) |
| `ROADMAP.md` | Modify | `v1.16: Fold Review Into Code` entry (Change 6) |
| `planning.md` | Modify | Record v1.16; update Active Roadmap Phase / In flight (Change 6) |
| `README.md` | Modify (if applicable) | Only if it names the `/code`/`/review` invocation relationship (Change 6) |

## Implementation Order

1. **Change 1** (`commands/code.md`) — the actual behavior change; everything else documents it.
2. **Change 2** (`commands/review.md`) — notes the new dual-invocation reality in the file `/code` now points at.
3. **Change 3** (`CLAUDE.md`) — source-of-truth workflow contract.
4. **Change 4** (`settings/claude-global.md`) — points at Change 3's shape; governs live session behavior.
5. **Change 5** (`skills/WORKFLOW_MANUAL.md`) — points at the same shape for the reference manual.
6. **Change 6** (docs) — `/code` Step 7; reflects everything above. Run `./scripts/gate_fast.sh` green before reporting.

Dependencies: Changes 3-5 describe the same fold from three angles and should read consistently with each other and with Change 1's actual `commands/code.md` behavior — write Change 1 first so the documentation Changes describe what was actually built, not the reverse. Change 6 depends on all.

## Verification Checklist

- [ ] `commands/code.md` Step 9 auto-runs `/review`'s procedure in the same turn; old Step 9 renumbered to Step 10 ending with "Ready for `/gate fast`" (Change 1)
- [ ] `commands/review.md` documents the dual invocation mode without altering its actual review contract (Change 2)
- [ ] `CLAUDE.md`'s Development Workflow states two exceptions, both named, both explaining what does and doesn't move (Change 3)
- [ ] `audit-project-drift.sh --project dev-platform` reports CLEAN — no self-flag from the `CLAUDE.md` edit (Change 3)
- [ ] `settings/claude-global.md`'s stop-list drops `/code`; two `Exception:` paragraphs present (Change 4)
- [ ] `skills/WORKFLOW_MANUAL.md` describes "two arrows" (not "the one arrow"); Step 4 heading reads "(automatic, part of `/code`)" (Change 5)
- [ ] The STOP boundary is still immediately after `/review`/Step 4, before `/gate fast` — verified by reading Change 1's new Step 10 and Change 5's new Step 4 body, not just grepping for a string (Changes 1, 5)
- [ ] `ROADMAP.md` has the v1.16 entry; `planning.md` records v1.16 as current (Change 6)
- [ ] `./scripts/gate_fast.sh` PASSes; `./scripts/check_spec_taxonomy.sh` clean
- [ ] No new script or test suite added (none needed — instruction-file change only)
- [ ] Language architecture matrix followed (Markdown/prose only — no code component to evaluate)
