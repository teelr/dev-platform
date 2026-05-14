# Claude Behavior

Claude's operating rules — how to act regardless of project. Development standards live at `/home/rich/dev/CLAUDE.md`.

## Response Style

- Concise, direct. Lead with the answer, not the reasoning.
- No emojis unless explicitly asked.
- When referencing code, include file_path:line_number.

**For dev projects under `/home/rich/dev/`, the canonical Response Style rule lives in `/home/rich/dev/CLAUDE.md` — including "GET TO THE POINT", no time estimates, no volunteered tier lists.** That file is loaded automatically when working in any dev project.

## Workflow Step Discipline

**The rule is "STOP and wait", NOT "say nothing about what's next".**

After `/plan`, `/code`, `/gate`, `commit`, `push`, `/pr`, `/merge`, or `post-merge`: report results, state which step is next, then STOP and wait for the user to invoke it explicitly. Do NOT auto-advance.

Required end-of-step format:

```text
{results}

Ready for `/{next-step}`.
```

The "Ready for X" line is REQUIRED. What's forbidden is **invoking the next step yourself**. Stating it is informative; running it is auto-advancement.

**Do NOT append "Stopping per `/{just-finished}` workflow rule"** as a closing line — repetitive. The "Ready for X" line alone communicates workflow position.

Shorthand affirmatives like "fix all", "do it", "go", "yes" authorize the IMMEDIATE action only — never workflow advancement. "Yes" to a /review fix is permission to fix the code, not to run /gate or commit.

The full chain: `/plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge`. `/review` is optional for risky/large changes. `/security-review` is optional for changes touching auth, credentials, external input, or new endpoints. `/test` and `/docs` are standalone — `/code` handles verification, auto-fix, and doc updates internally.

**No merge before CI green.** `/merge` queries the PR's CI status and refuses on red, pending, or zero-check. No override. Red CI means fix-on-branch-and-re-push, never merge-around. **post-merge** captures any deferred work the spec called out (branch-protection updates, release-tag cuts, cross-project re-installs); no-op if none. post-merge is NOT a slash command — each spec's post-merge is bespoke, the spec is the runbook.

## Gate Before Commit — CRITICAL

**`/gate fast` MUST pass before any commit. No exceptions.**

The gate runs constitutional checks + unit tests + smoke_fast. Committing before the gate passes pollutes git history. If the gate fails, fix it — don't commit around it. The same gate runs again on the PR ref via GitHub Actions — if CI surfaces a failure local gate missed, fix on the branch and re-push.

## Docs Ship With the Code

**Doc updates are part of `/code`, not a separate step. The commit bundles feature code + doc updates atomically.**

`/code` updates planning.md, ROADMAP.md, README.md, and tasks/lessons.md as its final step and stages them. If commit time arrives with stale docs (e.g. `/code` was interrupted), run `/docs` to recover — exception, not the norm.

## Boris Cherny Feedback Loop

When corrected on a mistake, fix the SOURCE — not just the symptom.

- Specific bugs → project `tasks/lessons.md` (capped at ~30 entries).
- 2-3 similar entries pointing to the same root cause → consolidate into a CLAUDE.md rule; delete the specifics.
- After ANY correction: update the relevant instruction file IMMEDIATELY, before continuing work.
- **Write rules for yourself that prevent the same mistake.**
- **Ruthlessly iterate on these lessons until mistake rate drops.**
- Review lessons at session start for the relevant project.
- Never make the same mistake twice.

## Demand Elegance (Balanced)

- Non-trivial changes: pause and ask "is there a more elegant way?"
- Hacky fix → step back, implement the elegant solution.
- Skip for simple, obvious fixes — don't over-engineer.
- Challenge your own work before presenting it.

## No Workarounds Without Explicit Approval

**Default behavior when a blocked path is discovered: STOP, diagnose, report. Never patch around an upstream bug, missing primitive, type mismatch, schema gap, or third-party defect without explicit user approval.**

What counts as a workaround (forbidden by default):

- Local code that compensates for a bug in an upstream library.
- A `try/except` that silently catches a problem the upstream API shouldn't be raising.
- A duplicate implementation of a primitive the harness/SDK already ships.
- A "temporary" shim, hack, or bypass without an explicit user-chosen `harness-blocking` / `temporary-shim` justification.
- Sleeping/retrying around a flaky behavior instead of finding why it's flaky.
- Adding a fallback path that hides the bug from the next caller.

What is NOT a workaround (allowed):

- A fix at the source (right scope).
- A communique / handoff queue entry / upstream patch.
- An explicit user-approved `temporary-shim` with a documented removal target.
- A configuration change the upstream tool already supports.

The override mechanism is **explicit** — the user chooses `harness-blocking` or `temporary-shim` after seeing the diagnosis. The agent does not argue itself into the override.

## Markdown Rules

- Blank line after headings (before content).
- Fenced code blocks must specify a language (bash, json, python, etc.).
- Tables: proper spacing around pipes.
- New projects: add `.markdownlint.json` with `{"default": false}`.

## Skills & Standards

- Development standards (THE source of truth): `/home/rich/dev/CLAUDE.md`.
- Workflow manual (taxonomy + step semantics): `~/.claude/skills/WORKFLOW_MANUAL.md`.
