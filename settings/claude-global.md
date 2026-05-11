# Claude Behavior

These are Claude's operating rules — how to act regardless of project. Development standards live at `/home/rich/dev/CLAUDE.md`.

## Response Style

- Concise, direct. Lead with the answer, not the reasoning.
- No emojis unless explicitly asked.
- When referencing code, include file_path:line_number.

**For development projects under `/home/rich/dev/`, the canonical Response Style rule lives in `/home/rich/dev/CLAUDE.md` — including the "GET TO THE POINT" anti-verbosity rule, the no-time-estimates rule, and the no-volunteered-tier-lists rule. That file is loaded automatically when working in any dev project, so the rule applies wherever it matters most.**

## Workflow Step Discipline

**The rule is "STOP and wait", NOT "say nothing about what's next".**

After `/plan`, `/code`, `/test`, `/review`, `/gate`, `/docs`, `commit`, `push`, `/pr`, `/merge`, or `post-merge`: report results, state which step is next, then STOP and wait for the user to invoke it explicitly. Do NOT auto-advance to the next step. (The post-`push` steps — `/pr`, CI wait, `/merge`, post-merge — were added 2026-05-11 when v0.7 Phase 2 introduced CI; `/pr` and `/merge` became slash commands in v0.8 Phase 1's follow-up chore so the workflow rules are mechanically enforced rather than honor-system.)

Required end-of-step format:

```text
{results}

Ready for `/{next-step}`.
```

The "Ready for X" line is REQUIRED — it tells the user where the workflow is. What's forbidden is **invoking the next step yourself** (running `/review` automatically after `/code`, running `/gate` after `/review`, committing without explicit invocation, etc.). Stating the next step is informative; running it is auto-advancement.

**Do NOT append "Stopping per `/{just-finished}` workflow rule"** as a closing line — Rich finds it repetitive. The "Ready for X" line alone communicates the same workflow position. Set cross-project 2026-05-06.

Shorthand affirmatives like "fix all", "do it", "go", "yes" authorize the IMMEDIATE action only — never workflow advancement (lesson L28). "Yes" to a /review fix is permission to fix the code, not to run /gate or commit.

The full chain: `/plan → /code → /test → /review → /gate fast → /docs → commit → push → /pr → CI → /merge → post-merge`.

**No merge before CI green.** Once `gate-fast` CI runs on a PR (every dev project under `/home/rich/dev/` has it from v0.7 Phase 2 onward), the workflow does not advance to `/merge` until CI reports green. `/merge` enforces this mechanically — it queries the PR's CI status (via `gh pr view <N> --json statusCheckRollup`) before invoking the merge and refuses on red, pending, or zero-check states. No override flag. Red CI means fix-on-branch-and-re-push, never merge-around. **post-merge** captures any deferred work the spec called out (branch-protection updates, release-tag cuts, cross-project re-installs, `sync-milestones.sh --apply`); if the spec named none, post-merge is a no-op but the workflow still passes through so the agent doesn't forget when deferred work DOES exist. post-merge is NOT a slash command because each spec's post-merge is bespoke — the spec is the runbook.

## Gate Before Commit — CRITICAL

**`/gate fast` MUST pass before any commit. No exceptions.**

Correct order: `/plan → /code → /test → /review → /gate fast → /docs → commit → push → /pr → CI → /merge → post-merge`

The gate runs constitutional checks + unit tests + smoke_fast. Committing before the gate passes pollutes git history and can block other work. If the gate fails, fix it — do not commit around it. The same gate then runs again on the PR ref via GitHub Actions (v0.7 Phase 2+) — if CI surfaces a failure local `/gate fast` missed, fix on the branch and re-push, never merge red.

## Docs Before Commit — CRITICAL

**`/docs` MUST run after `/gate fast` passes and BEFORE the commit. No exceptions.**

`/docs` updates planning.md, ROADMAP.md, README.md, and tasks/lessons.md to reflect the completed work. The commit then bundles feature code + doc updates together into a single atomic commit — not separate "feat" and "docs" commits. Pushing without running `/docs` leaves all project docs stale. If you find yourself about to commit without having run `/docs`, stop and run it first.

## Boris Cherny Feedback Loop

When corrected on a mistake, fix the SOURCE — not just the symptom.

- Specific bugs → project `tasks/lessons.md` (capped at ~30 entries)
- When 2-3 similar entries point to the same root cause → consolidate into a CLAUDE.md rule, delete the specifics
- After ANY correction: update the relevant instruction file IMMEDIATELY, before continuing work
- Never make the same mistake twice

## Self-Improvement Loop

- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for the relevant project

## Demand Elegance (Balanced)

- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: step back, implement the elegant solution
- Skip this for simple, obvious fixes — don't over-engineer
- Challenge your own work before presenting it

## No Workarounds Without Explicit Approval

**Default behavior when a blocked path is discovered: STOP, diagnose, report. Never patch around an upstream bug, missing primitive, type mismatch, schema gap, or third-party defect on my behalf without explicit user approval.**

What counts as a workaround (forbidden by default):

- Local code that compensates for a bug in an upstream library (e.g., wrapping a tuple-returning helper to coerce to list, masking a None where a dict is expected, special-casing a wrong-shape response)
- A `try/except` that silently catches a problem the upstream API shouldn't be raising
- A duplicate implementation of a primitive the harness/SDK already ships, because "the existing one doesn't quite work"
- A "temporary" shim, hack, or bypass without an explicit user-chosen `harness-blocking` / `temporary-shim` justification (per the PA Architectural Triage rule)
- Sleeping/retrying around a flaky behavior instead of finding why it's flaky
- Adding a fallback path that hides the bug from the next caller

What is NOT a workaround (allowed):

- A fix at the source (right scope)
- A communique / handoff queue entry / upstream patch
- An explicit user-approved `temporary-shim` with a documented removal target
- A configuration change the upstream tool already supports

The override mechanism is **explicit** — the user chooses `harness-blocking` or `temporary-shim` after seeing the diagnosis. The agent does not get to argue itself into the override. Same shape as the PA triage rule.

Set cross-project 2026-05-08 (harness v2.38.0 vision-adapter `/test` surfaced a tuple-vs-list mismatch in the runtime's `_has_non_text_content` dispatch; the right move was to file a communique, not patch around it on PA's side).

## Markdown Rules

- Blank line after headings (before content)
- Fenced code blocks must specify a language (bash, json, python, etc.)
- Tables must have proper spacing around pipes
- New projects: add `.markdownlint.json` with `{"default": false}`

## Skills & Standards

- Skills are defined in `~/.claude/commands/` (plan.md, code.md, test.md, review.md)
- Workflow manual: `~/.claude/skills/WORKFLOW_MANUAL.md`
- **Development standards (THE source of truth):** `/home/rich/dev/CLAUDE.md`
- Available skills: /plan, /code, /test, /review, /gate, /docs, /pr, /merge, /smoke_test
