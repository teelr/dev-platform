# v1.33: Auto-Fix Circuit Breaker

## Coding Specification for Implementation

## Design Philosophy

[issue #118](https://github.com/teelr/dev-platform/issues/118) (verified via `gh issue view 118 --repo teelr/dev-platform`) flags that `/code`'s auto-fix loop — implement → verify → fix → re-verify, `commands/code.md:82-91` — has no documented bounded-retry or repeated-failure circuit breaker. Nothing stops a fix attempt from cycling against the same failure: no attempt cap, no "this is the same error as last time, stop and surface it" check. The issue is explicit that this is "not a spec, not a commitment to build it as described — just flagging," so the scoping call (which loops, what bound, what happens on trip) is made here.

**This is a prose fix, not a code fix.** `/code` is an agent following written instructions, not a script with a call stack — there is no `for` loop to add a `MAX_ATTEMPTS` guard to. The circuit breaker is a rule `/code` follows: count attempts, recognize when a fix reproduced the prior failure, and stop rather than continuing to guess. Same shape as the workflow's existing STOP-and-wait discipline (`settings/claude-global.md`), just applied one level down — inside a single `/code` turn's own retry loop instead of between workflow steps.

**Scope, found by sweeping for the same shape rather than fixing only the instance the issue named (per `CLAUDE.md`'s Derivation Sweep rule):** the verify → fix → re-verify shape appears three times in the two command files that make up `/code`:

- `commands/code.md` Step 3 (`commands/code.md:82-91`) — per-Change verify/fix, the loop the issue names directly.
- `commands/code.md` Step 5 (`commands/code.md:111-114`) — the same shape at the end-to-end pass instead of a single Change.
- `commands/review.md` Step 4 (`commands/review.md:97-104`), which `/code` Step 9 runs as its own final step — fix each already-identified SECURITY/BUG/COMPLIANCE/QUALITY issue, then re-verify.

The first two retry the *same* failure across repeated fix attempts and are exactly what the issue describes. The third is structurally different: it fixes each already-identified issue exactly once and re-runs a build/lint check once to confirm — it does not retry a fix against a failure that persists, so it carries none of the unbounded-cycling risk. This spec bounds the first two and deliberately leaves the third alone (see "What NOT to Do").

**The bound:** two independent conditions trip the breaker for a given Change (Step 3) or the end-to-end pass (Step 5) — an **attempt cap** (stop on the 3rd consecutive verification failure, i.e. after 2 fix attempts have both failed) and a **no-progress check** that fires earlier (stop immediately if a fix attempt is followed by a re-verification failure with the same signature — same command, same file/line, same error/assertion — as the failure before it). Both conditions escalate the same way: stop the whole `/code` run, leave the broken state as evidence rather than reverting it, and report to the user what's blocked, the exact failure, and every fix attempted — replacing Step 10's normal "Ready for `/gate fast`" ending for that turn.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `commands/code.md` edits | Markdown | Agent instructions, not executable code — there is no runtime loop to instrument. |
| `skills/WORKFLOW_MANUAL.md` edit | Markdown | Mirrors the behavior for a reader learning the workflow from the manual. |

No new script, no new test suite — this is an instruction-file change to an existing agent command, same shape as v1.15 (Post-Merge Change Summary), v1.16 (Fold Review Into Code), and v1.29 (Identifier Descriptors), all of which shipped with zero new `tests/` coverage because there is no runtime behavior to unit-test, only agent-followed prose. The Language Architecture Decision Matrix governs new services/components; this spec adds neither.

## Overview

**Phase 1: The circuit breaker**

1. Change 1: Add the Auto-Fix Circuit Breaker to `commands/code.md` — bounded retry and no-progress stop wired into Steps 3 and 5, a new "Auto-Fix Circuit Breaker" Rules subsection defining the mechanism and escalation format, and a Step 10 note so a tripped breaker skips the normal "Ready for `/gate fast`" ending.
2. Change 2: Mirror the bounded-retry behavior into `skills/WORKFLOW_MANUAL.md`'s `/code` Key Behavior list.

---

## Phase 1: The circuit breaker

### Change 1: `commands/code.md` — bounded retry, no-progress stop, escalation

**Problem:** Steps 3 and 5's verify → fix → re-verify loops (`commands/code.md:82-91`, `commands/code.md:111-114`) have no stated bound. A fix attempt that doesn't resolve the failure has nothing telling `/code` to stop rather than try again — indefinitely, per issue #118.

**File:** `/home/rich/dev/commands/code.md` (existing).

**Implementation:**

**3a. Step 3 — add a bullet after the existing ARCHITECTURE bullet, before "5. Mark the todo as completed" (currently `commands/code.md:91-92`):**

```markdown
   - **This loop is bounded — see "Auto-Fix Circuit Breaker" under Rules.** Count fix attempts for THIS Change; on the 3rd consecutive verification failure, or immediately if a fix attempt reproduces the same failure signature as the attempt before it, stop and escalate instead of trying again.
```

**3b. Step 5 — rewrite item 4 (currently `commands/code.md:114`, "Fix any remaining issues before proceeding to Step 6") to:**

```markdown
4. **Fix any remaining issues before proceeding to Step 6 — bounded the same way as Step 3.** See "Auto-Fix Circuit Breaker" under Rules; the same attempt cap and no-progress check apply here, scoped to this end-to-end pass rather than a single Change.
```

**3c. Step 10 — insert a new paragraph immediately after the `## Step 10: Report — Next Step Is `/gate fast`` header (currently `commands/code.md:214`), before the existing "Combine this turn's report..." sentence:**

```markdown
If Step 3 or Step 5 tripped the Auto-Fix Circuit Breaker (see Rules), skip the rest of this Step — you already stopped and reported at the point of failure, in that section's escalation format. Do not run Step 9's review pass and do not end with "Ready for `/gate fast`" — the spec is not finished.
```

**3d. Rules — append a new subsection at the end of the file, after the existing `### Verification is Mandatory` subsection (currently ending at `commands/code.md:266`):**

```markdown

### Auto-Fix Circuit Breaker

The verify → fix → re-verify loop in Steps 3 and 5 is bounded, not open-ended — [issue #118](https://github.com/teelr/dev-platform/issues/118) flagged that nothing stopped a stuck fix from cycling silently. Track attempts per Change (Step 3) or per the end-to-end pass (Step 5), counting from the first verification failure:

- **Attempt cap:** stop on the 3rd consecutive verification failure for the same Change/pass — i.e. after 2 fix attempts have both failed to produce a clean verification. Do not attempt a 3rd fix.
- **No-progress cap — fires earlier:** stop immediately, even under the cap, if a fix attempt is followed by a re-verification failure with the same signature as the failure before it (same command, same file/line, same error message or assertion). An unchanged failure after a fix means the fix changed nothing about the problem; a second attempt made with the same understanding of it is unlikely to either.
- **On tripping either cap:** STOP the whole `/code` run — do not continue to any later Step for this invocation. Do not silently skip the failing Change or check, and do not revert the broken state — it's evidence for whoever picks this up next, not something to clean up. Report to the user, in place of Step 10's normal ending:
  - which Change (or which end-to-end check, for Step 5) is blocked
  - the exact failing output from the last verification
  - each fix attempted, in order, and why it didn't resolve the failure
  - that you stopped rather than continuing to retry, and you're waiting for direction

This is the same STOP-and-wait discipline `settings/claude-global.md` already applies between workflow steps, now applied inside a single `/code` turn's own retry loop: hand a stuck problem back to the user rather than guessing further.

**Does not apply to `commands/review.md` Step 4** (the SECURITY/BUG/COMPLIANCE/QUALITY fix pass `/code` Step 9 runs). That loop fixes each already-identified issue once and re-verifies once — it doesn't retry a fix against a failure that persists, so it carries none of the unbounded-cycling risk this section bounds.
```

**Acceptance Test:**

```bash
grep -n "Auto-Fix Circuit Breaker" commands/code.md              # new Rules subsection present, referenced from Steps 3/5/10
sed -n '75,95p' commands/code.md                                 # Step 3's new bullet reads correctly in context
sed -n '107,117p' commands/code.md                                # Step 5's rewritten item 4 reads correctly in context
sed -n '212,225p' commands/code.md                                # Step 10's new paragraph precedes the existing report instructions
bash tests/commands/frontmatter.sh                                # frontmatter/description still valid (unchanged, but this file is covered live by that suite)
./scripts/gate_fast.sh                                            # full gate still PASS
```

---

### Change 2: `skills/WORKFLOW_MANUAL.md` — mirror the bounded retry in `/code`'s Key Behavior list

**Problem:** `skills/WORKFLOW_MANUAL.md`'s `/code` section (`skills/WORKFLOW_MANUAL.md:69-74`) documents "Verifies every change before moving on" with no mention that the verify/fix loop is now bounded — a reader learning the workflow from the manual wouldn't know `/code` stops and escalates instead of retrying indefinitely.

**File:** `/home/rich/dev/skills/WORKFLOW_MANUAL.md` (existing — the `**Key behavior:**` bullet list, `skills/WORKFLOW_MANUAL.md:69-74`).

**Implementation:**

Replace the existing bullet (currently `skills/WORKFLOW_MANUAL.md:73`, "- Verifies every change before moving on") with:

```markdown
- Verifies every change before moving on, with a bounded retry — stops and reports to you after 2 failed fix attempts on the same failure, or sooner if a fix doesn't change the failure, instead of retrying indefinitely
```

Leave the other three bullets in the list untouched.

**Acceptance Test:**

```bash
grep -n "bounded retry" skills/WORKFLOW_MANUAL.md         # the mirrored behavior is documented
sed -n '69,75p' skills/WORKFLOW_MANUAL.md                  # list reads correctly, other bullets unchanged
./scripts/gate_fast.sh                                     # full gate still PASS
```

---

## What NOT to Do

- **Do NOT touch `commands/review.md` Step 4.** It fixes each already-identified issue once and re-verifies once — it does not retry the same fix against a persisting failure, so it has no analogous unbounded-loop risk. Bounding it anyway would be scope creep against a loop that was never the problem.
- **Do NOT change the workflow chain string** (`/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`). This spec adds a rule inside `/code`'s own internal Step 3/5 loop; it adds no step, renames nothing, and reorders nothing at the chain level. `audit-project-drift.sh`'s chain-detection regex keys on the literal chain string, which this spec never touches.
- **Do NOT pick a different attempt cap per project or per file type.** The cap (2 fix attempts, 3rd failure stops) is uniform across every Change and every stack `/code` might touch — Go, Python, TypeScript, Rust, or a curl-tested endpoint. Inventing a per-language exception here is exactly the kind of unrequested feature `CLAUDE.md`'s "no over-engineering" rule forbids.
- **Do NOT auto-revert the broken state when the breaker trips.** The spec's escalation explicitly says to leave it — reverting destroys the evidence (the failing command's exact output, the diff of what each fix attempt tried) the user needs to decide what to do next.
- **Do NOT add a mechanical test/detector for this.** There's no code artifact to grep for compliance against — `/code`'s adherence to a bounded retry is a matter of it following its own instructions correctly on a live run, the same class of thing as Step 6's Adversarial Self-Review, which also ships with no test suite.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `commands/code.md` | Modify | Add the bounded-retry bullet to Step 3, rewrite Step 5 item 4, add a Step 10 escalation-skip note, append the "Auto-Fix Circuit Breaker" Rules subsection. |
| `skills/WORKFLOW_MANUAL.md` | Modify | Replace the `/code` Key Behavior bullet describing verification to mention the bounded retry. |

## Implementation Order

1. Change 1 (`commands/code.md`) — the mechanism itself.
2. Change 2 (`skills/WORKFLOW_MANUAL.md`) — mirrors Change 1's wording, so it should land after Change 1 is final.

## Verification Checklist

- [ ] Step 3 of `commands/code.md` references the Auto-Fix Circuit Breaker and states the per-Change attempt count.
- [ ] Step 5 of `commands/code.md` states the same bound applies to the end-to-end pass.
- [ ] Step 10 of `commands/code.md` skips its normal ending when the breaker trips in an earlier step.
- [ ] The new "Auto-Fix Circuit Breaker" Rules subsection defines both the attempt cap and the no-progress cap, and the escalation report format.
- [ ] The subsection explicitly scopes out `commands/review.md` Step 4, with the reason stated.
- [ ] `skills/WORKFLOW_MANUAL.md`'s `/code` Key Behavior list mentions the bounded retry.
- [ ] The workflow chain string is unchanged anywhere in the repo (`grep -rn "plan → /code → /review" commands/ CLAUDE.md settings/ skills/` still matches only pre-existing occurrences).
- [ ] `./scripts/gate_fast.sh` passes.
- [ ] Language Architecture Decision Matrix: N/A — no new components.
