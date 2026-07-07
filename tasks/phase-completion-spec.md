# Roadmap-Phase-Completion Step

## Coding Specification for Implementation

Closes GitHub issue [#50](https://github.com/teelr/dev-platform/issues/50) — the canonical chain has no step that operates at the Roadmap-Phase level, so phase status and GitHub milestones drift out of sync every phase.

## Design Philosophy

The canonical chain (`/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`) is entirely **Change-scoped**. `/code` updates `planning.md` for the one Change it implements; `/pr` *assigns* a milestone; `/merge` closes a *feature branch*. Nothing owns the two taxonomy levels above Change — **Spec completion** and **Roadmap Phase completion**. So when a merge ships the last Change of a Roadmap Phase, nothing marks the phase done in `ROADMAP.md`/`planning.md` or closes its GitHub milestone. Issue #50 documents this biting kermit-v3 (v0.1/v0.2/v0.3 all left `open` with 0 open issues, docs still "in progress" weeks after merge), and it bit dev-platform in this very session — my `/dev` report caught `planning.md` still calling the already-merged v1.9 "in flight."

The fix has two halves, matching the issue's own two-part proposal. **Phase 1 makes the step exist**: a standard-shaped "Roadmap Phase completion" sub-step of `post-merge`, documented in the three workflow-contract files every session reads (`dev/CLAUDE.md`, `settings/claude-global.md`, `skills/WORKFLOW_MANUAL.md`), and surfaced by `/merge`'s Step 6 post-merge reminder when it detects the merge completed a phase. This is the propagation path for consumers too — kermit-v3's session reads `dev/CLAUDE.md`, so documenting the step there IS how it reaches consumers (same as every other workflow-contract rule). **Phase 2 adds the mechanical backstop** this repo's identity demands — because "remember to close the milestone" is honor-system, and honor-system is exactly what failed. `scripts/check-phase-milestones.sh` flags any GitHub milestone left `open` whose attached issues/PRs are all closed (a completed-but-not-closed milestone), mirroring the established `check-comms-delivery.sh` pattern: a standalone gh-calling tool NOT in `gate_fast` (it makes network calls), with an offline mock-`gh` test suite that IS auto-discovered by the gate.

**Honesty about the backstop's reach (per the "Honesty About What Ships" rule):** the detector catches milestones whose attached PRs/issues are *all closed* (`open_issues == 0 && closed_issues >= 1`) — the dev-platform pattern, since `/pr` assigns each PR to its milestone. It **cannot** catch a phase whose PRs were never assigned to any milestone (there `closed_issues == 0`, indistinguishable via the API from a future phase not yet started). That never-attached case is a *behavioral* gap the Phase 1 step + `/pr`'s existing milestone assignment address, not something the detector can see. The spec states this limitation in the script header and does not overclaim.

**Single-branch strategy:** both Phases ship as ONE PR on branch `v1.10/phase-1-phase-completion`. Per the per-Spec-Phase branching rule's small-Phase carve-out, they are tightly coupled (Phase 1 documents "run the detector"; Phase 2 is that detector) and each half is small — splitting would make per-PR ceremony exceed content. This is called out here so `/code` creates one branch, not two.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `check-phase-milestones.sh` | Bash | Consistent with every other `scripts/*.sh` fleet/checker tool (`sync-milestones.sh`, `check-comms-delivery.sh`, `audit-project-drift.sh`); thin orchestration over `gh` + `jq`, no compute/network/AI/UI concern that the Language Matrix would route elsewhere. Bash is the established language for this repo's operational tooling. |
| Contract-file edits | Markdown | Documentation of the workflow step; not code. |

## Overview

**Phase 1 — Make the step exist (documentation + `/merge` surfacing)**

- Change 1: Add the standard Roadmap-Phase-completion post-merge sub-step to `dev/CLAUDE.md`.
- Change 2: Add the same standard shape to `settings/claude-global.md` (Workflow Step Discipline).
- Change 3: Document the step in `skills/WORKFLOW_MANUAL.md`.
- Change 4: Wire `/merge` Step 6 to detect phase completion and surface the standard actions.

**Phase 2 — Mechanical backstop (detector + tests)**

- Change 5: Add `scripts/check-phase-milestones.sh` (standalone gh-calling detector).
- Change 6: Add `tests/phase-milestones/` offline mock-`gh` suite + Consumer Audit (`.gitignore`, gate discovery, README).

**Docs (bundled into the implementing commits per `/code` Step 7)**

- Change 7: Roadmap/planning/README doc updates for v1.10.

---

## Phase 1: Make the step exist

### Change 1: Standard Roadmap-Phase-completion post-merge sub-step in `dev/CLAUDE.md`

**Problem:** `dev/CLAUDE.md`'s Development Workflow describes `post-merge` as "Bespoke deferred steps from the spec. No-op if the spec named none." ([CLAUDE.md:118](../CLAUDE.md#L118)) — it never names the recurring phase-completion case, so it's forgotten every phase.

**File:** `/home/rich/dev/CLAUDE.md` (existing — the `- **post-merge**` bullet at line ~118, inside the "Standard chain" block; and the matching one-liner at line ~44 area / Development Workflow prose).

**Implementation:**

Expand the `post-merge` bullet in the **Standard chain** list ([CLAUDE.md:118](../CLAUDE.md#L118)) to name the phase-completion sub-step as a standard shape, while keeping "bespoke per spec" for everything else. Replace:

```markdown
- **post-merge** — Bespoke deferred steps from the spec. No-op if the spec named none.
```

with:

```markdown
- **post-merge** — Bespoke deferred steps from the spec. No-op if the spec named none. **One sub-step is standard, not bespoke: Roadmap-Phase completion.** When a merge ships the **last Change of a Roadmap Phase** — whether the phase goal was satisfied by shipped code OR closed by an explicit scope decision (e.g. a planned item dropped as over-engineering) — always: (1) mark the phase complete in `ROADMAP.md` and `planning.md` with today's date and status, and (2) close its GitHub milestone (`gh api -X PATCH repos/:owner/:repo/milestones/<n> -f state=closed`, or `scripts/sync-milestones.sh --apply` where the project ships it — it reads the now-`complete` ROADMAP entry and closes the milestone). Verify afterward with `scripts/check-phase-milestones.sh` (flags a milestone left `open` with 0 open issues). A mid-phase merge that does NOT complete the phase skips this sub-step.
```

Do NOT introduce the literal review-less chain string `…/code → /gate fast…` anywhere in this edit (the `audit-project-drift.sh` DRIFT detector greps dev-platform's own `CLAUDE.md` for it — a bare occurrence would self-flag the repo; recurring hazard, lessons 2026-05-11 / 2026-06-07). The canonical chain string already present is fine; add no new chain examples.

**Acceptance Test:**

```bash
grep -n "Roadmap-Phase completion" /home/rich/dev/CLAUDE.md          # the new standard sub-step is present
grep -c "satisfied by\|scope decision" /home/rich/dev/CLAUDE.md      # the by-decision case is covered
./scripts/audit-project-drift.sh --project dev-platform | grep -E "dev-platform.*CLEAN"   # still CLEAN, no self-flag
./scripts/gate_fast.sh                                                # constitutional + taxonomy checks still PASS
```

---

### Change 2: Same standard shape in `settings/claude-global.md`

**Problem:** `settings/claude-global.md` (deployed as `~/.claude/CLAUDE.md`, the always-loaded behavior file) defines `post-merge` at [settings/claude-global.md:36](../settings/claude-global.md#L36) as capturing "any deferred work the spec called out … no-op if none" — same omission as Change 1, in the file that governs the "STOP and wait" step discipline.

**File:** `/home/rich/dev/settings/claude-global.md` (existing — the `**post-merge**` sentence at line ~36).

**Implementation:**

Extend the existing `post-merge` description sentence so the phase-completion sub-step is named as standard. After the existing sentence that ends "…the spec is the runbook.", append:

```markdown
The one **standard** (non-bespoke) post-merge sub-step is **Roadmap-Phase completion**: when a merge ships the last Change of a Roadmap Phase (goal met by code, or closed by an explicit scope decision), mark the phase complete in `ROADMAP.md` + `planning.md` (date + status) and close its GitHub milestone, then verify with `scripts/check-phase-milestones.sh`. Full shape in `/home/rich/dev/CLAUDE.md`.
```

Keep wording consistent with Change 1 (single source of truth is `dev/CLAUDE.md`; this file points at it). Add no new chain-string examples.

**Acceptance Test:**

```bash
grep -n "Roadmap-Phase completion" /home/rich/dev/settings/claude-global.md
# Confirm it references dev/CLAUDE.md as the full shape rather than duplicating the whole thing:
grep -n "Full shape in" /home/rich/dev/settings/claude-global.md
./scripts/gate_fast.sh
```

---

### Change 3: Document the step in `skills/WORKFLOW_MANUAL.md`

**Problem:** The workflow manual ([skills/WORKFLOW_MANUAL.md:132-140](../skills/WORKFLOW_MANUAL.md#L132-L140)) shows the canonical chain and `post-merge` at the end of it but never explains what `post-merge` does or the phase-completion sub-step — a reader learning the workflow from the manual would never know the phase-close step exists.

**File:** `/home/rich/dev/skills/WORKFLOW_MANUAL.md` (existing — after the "Step 6: Push" subsection at line ~178-180, inside "Workflow: Full Feature Development").

**Implementation:**

Add a new `###`-level subsection after the "### Step 6: Push" subsection (line ~178-180), titled **`Step 7: Post-merge (deferred, per spec)`** — matching the numbered-step convention of its siblings ("### Step 1: Plan" … "### Step 6: Push"). WORKFLOW_MANUAL.md is under `skills/` and is NOT scanned by `check_spec_taxonomy.sh`, and Step-headers are explicitly legitimate for workflow-runner documentation, so this heading is correct in the real file. (The heading line is described here in prose rather than shown at column 0 inside a fence so this SPEC file does not itself trip the taxonomy checker.) The subsection body:

> After `/merge`, run any deferred steps the spec's "Post-merge" section named (branch-protection updates, release-tag cuts, cross-project re-installs). These are bespoke — the spec is the runbook — with **one standard sub-step**: **Roadmap-Phase completion.** When the merge shipped the last Change of a Roadmap Phase (goal met by code, or the phase closed by an explicit scope decision), mark the phase complete in `ROADMAP.md` + `planning.md` (date + status) and close its GitHub milestone (`gh api -X PATCH repos/:owner/:repo/milestones/<n> -f state=closed`, or `scripts/sync-milestones.sh --apply` where present). Verify with `scripts/check-phase-milestones.sh` — it flags any milestone left `open` with 0 open issues. `/merge`'s final report tells you whether the just-merged PR completed a phase.

**Acceptance Test:**

```bash
grep -n "Step 7: Post-merge" /home/rich/dev/skills/WORKFLOW_MANUAL.md
grep -n "check-phase-milestones.sh" /home/rich/dev/skills/WORKFLOW_MANUAL.md
./scripts/gate_fast.sh   # command-frontmatter + taxonomy suites unaffected but confirm green
```

---

### Change 4: Wire `/merge` Step 6 to detect and surface phase completion

**Problem:** `/merge`'s Step 6 ([commands/merge.md:130-142](../commands/merge.md#L130-L142)) reports the post-merge runbook from the spec but has no notion of "did this PR complete a Roadmap Phase?" — so even with Changes 1-3 documenting the step, nothing at merge time reminds the user it applies *now*.

**File:** `/home/rich/dev/commands/merge.md` (existing — Step 6 "Report + prompt next step", lines ~130-142, and the matching Rules bullet at line ~150).

**Implementation:**

In Step 6, after the existing bullet block that reports the spec's post-merge section, add a phase-completion detection + surface instruction. Insert before the final "Then STOP" paragraph:

```markdown
- **Detect Roadmap-Phase completion.** Determine whether this merge shipped the *last Change of a Roadmap Phase*:
  - Read the just-merged spec (from `git diff HEAD~1 --name-only` → `tasks/*-spec.md`). If its Overview lists Changes across Phases and this PR merged the final Phase's last Change, the phase is complete. A single-PR-per-spec change completing the spec also completes its Roadmap Phase.
  - A phase can also be complete by an explicit **scope decision** recorded in the spec or PR (a planned item dropped) — treat that the same as code-complete.
  - If complete, surface the **standard Roadmap-Phase-completion actions** (do NOT execute them — the user invokes post-merge):
    1. Mark the phase complete in `ROADMAP.md` + `planning.md` (today's date + status).
    2. Close the GitHub milestone: `gh api -X PATCH repos/:owner/:repo/milestones/<n> -f state=closed` (or `./scripts/sync-milestones.sh --apply` where the project ships it).
    3. Verify: `./scripts/check-phase-milestones.sh` should report no open-but-completed milestones.
  - If this merge did NOT complete a phase (a mid-phase Change), say so explicitly: "mid-phase merge — no phase-completion step."
```

Add a matching Rules bullet near [commands/merge.md:150](../commands/merge.md#L150):

```markdown
- **Surface phase-completion, don't perform it.** When the merge completes a Roadmap Phase, `/merge` names the standard close-out actions (mark ROADMAP/planning complete, close the milestone) in its report — but per Workflow Step Discipline the user invokes post-merge explicitly. `/merge` never edits docs or closes milestones itself.
```

`/merge`'s `allowed-tools` stays `Bash, ExitWorktree` — detection is read-only `git`/`gh` reads via Bash, no new tool needed.

**Acceptance Test:**

```bash
grep -n "Detect Roadmap-Phase completion" /home/rich/dev/commands/merge.md
grep -n "mid-phase merge" /home/rich/dev/commands/merge.md
# Frontmatter validator suite must still pass (merge.md has valid frontmatter):
./scripts/gate_fast.sh
```

---

## Phase 2: Mechanical backstop

### Change 5: `scripts/check-phase-milestones.sh` — completed-but-open milestone detector

**Problem:** Every step in Phase 1 is honor-system. The recurring failure (issue #50) is a human/agent forgetting to close a milestone at phase completion. This repo's identity is mechanical enforcement over honor-system — so ship a detector, mirroring `check-comms-delivery.sh`.

**File:** `/home/rich/dev/scripts/check-phase-milestones.sh` (new, executable).

**Implementation:**

A standalone Bash script over `gh` + `jq`. Model its shape, header comment, arg parsing, and exit conventions on `scripts/check-comms-delivery.sh` and `scripts/sync-milestones.sh` (both read here).

Header comment MUST state, honestly: this detects milestones whose attached issues/PRs are ALL closed (`open_issues == 0 && closed_issues >= 1`) — a completed-but-not-closed milestone. It does NOT (cannot) detect a phase whose PRs were never assigned to a milestone (`closed_issues == 0`, indistinguishable via the API from a not-yet-started future phase); that behavioral gap is covered by the Phase 1 step + `/pr`'s milestone assignment, not by this script. Also state it is NOT wired into `gate_fast.sh` (makes `gh` network calls), same rationale as `check-comms-delivery.sh`.

Behavior:

```bash
set -uo pipefail
```

- Resolve target repo: `--repo <owner/repo>` if given; else derive from the current repo's origin (`git remote get-url origin` → parse `owner/repo`, handling both `git@github.com:owner/repo.git` and `https://github.com/owner/repo.git` forms — reuse the parsing idiom from `scripts/verify-remotes.sh` if it has one; otherwise a small `sed`). Default when no override and not in a git repo → error exit 2.
- Preconditions: `command -v gh` and `command -v jq` or error exit 2 (matches `sync-milestones.sh:67-68`).
- Fetch open milestones: `gh api "repos/${REPO}/milestones?state=open&per_page=100"` (returns a JSON array; each element has `number`, `title`, `state`, `open_issues`, `closed_issues`, `html_url`). If the `gh` call fails (auth/network), print the error and exit 2 — a fetch failure is NOT "clean."
- Flag rule: `select(.open_issues == 0 and .closed_issues >= 1)`. These are completed-but-open milestones.
- Output:
  - Default (human-readable): print each flagged milestone as `⚠ OPEN-BUT-COMPLETE: <title> (#<number>) — <closed_issues> closed, 0 open — close it: gh api -X PATCH repos/${REPO}/milestones/<number> -f state=closed` and its `html_url`. If none, print `No open-but-complete milestones in ${REPO}.`
  - `--json`: emit the filtered JSON array (`[]` when clean).
  - `--help`/`-h`: usage text, exit 0 (offline, no gh needed).
- Exit code: `1` if one or more flagged milestones found (action needed — mirrors `check-comms-delivery.sh` FAIL semantics), `0` if clean, `2` on error (bad args, missing gh/jq, fetch failure, no repo resolvable).

Argument parsing loop follows the `sync-milestones.sh` `while [[ $# -gt 0 ]]; case` pattern; unknown arg → error exit 2.

**Acceptance Test:**

```bash
bash -n /home/rich/dev/scripts/check-phase-milestones.sh          # syntax OK (also covered by gate's scripts/ sweep)
./scripts/check-phase-milestones.sh --help; echo "exit=$?"        # exit 0, prints usage, no gh call
./scripts/check-phase-milestones.sh --nonsense; echo "exit=$?"    # exit 2 on bad arg
# Live smoke against dev-platform's own repo (requires gh auth) — expect it to
# FLAG the historically-left-open v0.x milestones if any remain, else report clean:
./scripts/check-phase-milestones.sh --repo teelr/dev-platform; echo "exit=$?"
```

---

### Change 6: `tests/phase-milestones/` offline mock-`gh` suite + Consumer Audit

**Problem:** The detector needs deterministic offline coverage of its flag rule and exit codes without hitting GitHub, and a new `tests/<suite>/` dir + a new extension-less mock binary triggers the Consumer Audit checklist (`.gitignore` allow-list, gate auto-discovery exclusion, README).

**File:** `/home/rich/dev/tests/phase-milestones/run.sh` (new) + `/home/rich/dev/tests/phase-milestones/fixtures/mock-bin/gh` (new, executable) + `.gitignore` / README updates.

**Implementation:**

Follow the mock-binary pattern from `tests/vscode/` (read `tests/vscode/run.sh` + `tests/vscode/fixtures/mock-bin/code` for the exact idiom): a mock `gh` at `tests/phase-milestones/fixtures/mock-bin/gh` that, for `gh api repos/<repo>/milestones?...`, echoes a canned JSON array chosen by a `MOCK_MILESTONES_FILE` (or a `MOCK_CASE`) env var the runner sets per case. `run.sh` prepends the mock-bin dir to `PATH` so the mock shadows real `gh`, and sources `tests/assert.sh` (the shared assertion sink — read an existing suite to confirm the exact source path + `assert`/`assert_eq` function names; use them so counts flow to `_GATE_COUNTS_FILE`).

The script under test resolves the repo via `git remote get-url origin`; to avoid depending on the test's own repo, invoke it with `--repo owner/repo` in every assertion so the mock's canned response is keyed predictably and no real git remote is read.

Cover the cross product of {flagged case, clean case, empty case} × {default output, --json, exit code}, plus the arg/help paths — enumerate as a table (per the mode×precondition cross-product lesson, 2026-05-11):

1. One milestone `open_issues:0, closed_issues:3` → default output contains `OPEN-BUT-COMPLETE` and the title; exit `1`.
2. Same case, `--json` → output is a non-empty JSON array with that milestone's number; exit `1`.
3. All milestones have `open_issues >= 1` → default output `No open-but-complete milestones`; exit `0`.
4. **False-positive guard:** a milestone `open_issues:0, closed_issues:0` (empty/not-started) → NOT flagged; exit `0`. (This is the honest limitation made a test.)
5. `--help` → exit `0`, usage printed (mock `gh` NOT invoked — assert no network).
6. Unknown arg → exit `2`.
7. (If cheaply mockable) `gh api` failure (mock exits nonzero) → script exits `2`, not `0` — a fetch failure is not "clean."

**Consumer Audit (new file types in glob-managed `tests/`):**

1. `.gitignore` allow-list: run `git check-ignore -v tests/phase-milestones/run.sh` and `... fixtures/mock-bin/gh`. The existing `!tests/**/*.sh` covers `run.sh`; the extension-less mock `gh` is covered by the existing `!tests/**/mock-bin/*` (added in v0.6 for `mock-bin/code`). Confirm with `git check-ignore -q` exit code (exit 1 = tracked); if either is ignored, add the missing negation. Read the `!` prefix, not `-v`'s printed rule (lesson 2026-06-23).
2. Gate auto-discovery: `scripts/gate_fast.sh` finds `tests/<suite>/*.sh` and `tests/<suite>/<test>/*.sh` but excludes `*/fixtures/*` — so `tests/phase-milestones/run.sh` is picked up as a runner and `fixtures/mock-bin/gh` is NOT executed as one. Verify by running `./scripts/gate_fast.sh` and confirming the new suite's assertions appear in the total and the mock is not run as a test. Do NOT widen the gate's `find`.
3. Bash-syntax coverage: the gate's `bash -n` sweep covers `scripts/` and `tests/`; `run.sh` and the new script are both covered. No `shell/` involvement.
4. README: add a one-line row for the `phase-milestones` suite to `tests/README.md` (read it first to match its table format).

**Acceptance Test:**

```bash
git check-ignore -q tests/phase-milestones/run.sh; echo "run.sh ignored? $?"        # want 1 (tracked)
git check-ignore -q tests/phase-milestones/fixtures/mock-bin/gh; echo "gh ignored? $?"  # want 1 (tracked)
bash tests/phase-milestones/run.sh                                                   # suite passes standalone
./scripts/gate_fast.sh                                                               # new suite counted in the aggregate PASS; mock not run as a runner
```

---

## Phase 1+2 shared: Change 7 — Docs

### Change 7: v1.10 ROADMAP / planning / README updates

**Problem:** `/code` Step 7 mandates doc updates bundled into the implementing commits; this spec ships a new Roadmap Phase (v1.10) and a new script + test suite that the docs must reflect.

**File:** `ROADMAP.md`, `planning.md`, `README.md` (all existing).

**Implementation:**

- `ROADMAP.md`: add a `v1.10: Roadmap-Phase Completion` entry in the existing bullet format, describing the standard post-merge sub-step + `check-phase-milestones.sh`. Mark it complete with today's date when the work lands (per `/code`'s doc step, not now).
- `planning.md`: fix the stale in-flight block (it still calls v1.9 "in flight" though v1.9 merged as #46) AND record v1.10. Update "Active spec" / "Active Roadmap Phase" / "In flight" to reflect this spec. Update the gate PASS count if the new suite changes it.
- `README.md`: add `check-phase-milestones.sh` to any scripts listing / count, and the `phase-milestones` test suite to any suite count, if such tables exist (grep first; only touch counts that exist).

**Acceptance Test:**

```bash
grep -n "v1.10" /home/rich/dev/ROADMAP.md
grep -n "v1.10\|phase-completion" /home/rich/dev/planning.md
grep -c "in flight" /home/rich/dev/planning.md   # the stale v1.9 in-flight text is corrected
./scripts/check_spec_taxonomy.sh                  # ROADMAP/planning still taxonomy-clean
```

---

## What NOT to Do

- **Do NOT make the detector fleet-wide in this spec.** A sweep over every registry project (resolving each project's `owner/repo` from `monitoring/remotes.json`) is a real enhancement but needs multi-repo mock-`gh` coverage and owner/repo resolution per entry. Ship the single-repo detector (`--repo` override, default = current repo's origin); note fleet-wide sweep as a future item in the ROADMAP entry — do NOT silently drop it.
- **Do NOT build the offline "planning.md Active Phase vs. milestone state" cross-check** the issue floats as a third option. It couples to `planning.md`'s prose format and still needs `gh` for milestone state. Out of scope; the `open_issues==0 && closed_issues>=1` detector is the honest MVP. Mention it as a possible future item only.
- **Do NOT overclaim the detector's reach.** It cannot see milestones that never had PRs assigned. State the limitation in the script header and ROADMAP entry; do not write "catches every unclosed phase milestone."
- **Do NOT wire `check-phase-milestones.sh` into `gate_fast.sh`.** It makes `gh` network calls — same reason `check-comms-delivery.sh` is standalone. Only its offline mock-`gh` test suite is gate-discovered.
- **Do NOT write a bare review-less chain string** (`…/code → /gate fast…` as a chain example) into `dev/CLAUDE.md` — `audit-project-drift.sh` greps it and would self-flag the repo (recurring "detector self-matches documentation" hazard). Verify `audit --project dev-platform` reports CLEAN before commit.
- **Do NOT have `/merge` execute the phase-completion actions.** It surfaces them; the user invokes post-merge explicitly (Workflow Step Discipline). `/merge` never edits docs or closes milestones.
- **Do NOT duplicate the full step text across all three contract files.** `dev/CLAUDE.md` is the source of truth; `settings/claude-global.md` and `WORKFLOW_MANUAL.md` state it concisely and point at `dev/CLAUDE.md` — consistent with the repo's "project files ADD, don't repeat" rule.
- **Do NOT put the mock `gh` anywhere the gate would run it as a test.** It lives under `tests/phase-milestones/fixtures/mock-bin/gh`; the gate's `! -path "*/fixtures/*"` exclusion keeps it out of runner discovery.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `CLAUDE.md` | Modify | Expand the `post-merge` bullet with the standard Roadmap-Phase-completion sub-step (Change 1) |
| `settings/claude-global.md` | Modify | Name the phase-completion sub-step in Workflow Step Discipline, pointing at `dev/CLAUDE.md` (Change 2) |
| `skills/WORKFLOW_MANUAL.md` | Modify | New "Step 7: Post-merge" subsection documenting the step (Change 3) |
| `commands/merge.md` | Modify | Step 6 detects phase completion + surfaces the standard actions; matching Rules bullet (Change 4) |
| `scripts/check-phase-milestones.sh` | New | Standalone gh detector for open-but-complete milestones (Change 5) |
| `tests/phase-milestones/run.sh` | New | Offline mock-`gh` assertion suite (Change 6) |
| `tests/phase-milestones/fixtures/mock-bin/gh` | New | Mock `gh` binary for the suite (Change 6) |
| `tests/README.md` | Modify | One-line row for the new suite (Change 6) |
| `.gitignore` | Modify (if needed) | Confirm/allow the new test files (Change 6 Consumer Audit) |
| `ROADMAP.md` | Modify | `v1.10: Roadmap-Phase Completion` entry (Change 7) |
| `planning.md` | Modify | Correct stale v1.9 in-flight text; record v1.10 (Change 7) |
| `README.md` | Modify | Add script + suite to any listings/counts that exist (Change 7) |

## Implementation Order

1. **Change 5** (`check-phase-milestones.sh`) — build the detector first so Changes 1-4 can reference it accurately and the live smoke works.
2. **Change 6** (test suite + Consumer Audit) — lock the detector's contract before documenting it.
3. **Change 1** (`dev/CLAUDE.md`) — source-of-truth doc for the step.
4. **Change 2** (`settings/claude-global.md`) — points at Change 1.
5. **Change 3** (`skills/WORKFLOW_MANUAL.md`) — points at Change 1.
6. **Change 4** (`commands/merge.md`) — surfaces the step; references the detector from Change 5.
7. **Change 7** (docs) — `/code` Step 7; reflects everything above. Run `./scripts/gate_fast.sh` green before reporting.

Dependencies: Change 4 and Changes 1-3 reference `check-phase-milestones.sh`, so Change 5 lands first. Change 6 depends on Change 5. Change 7 depends on all.

## Verification Checklist

- [ ] `dev/CLAUDE.md` post-merge bullet names the standard Roadmap-Phase-completion sub-step, incl. the "satisfied by scope decision" case (Change 1)
- [ ] `audit-project-drift.sh --project dev-platform` reports CLEAN — no self-flag from the edit (Change 1)
- [ ] `settings/claude-global.md` + `WORKFLOW_MANUAL.md` state the step concisely and point at `dev/CLAUDE.md` (Changes 2, 3)
- [ ] `/merge` Step 6 detects phase completion, surfaces the standard actions, and says "mid-phase merge" otherwise — without executing them (Change 4)
- [ ] `check-phase-milestones.sh` flags `open_issues==0 && closed_issues>=1`, exit 1 on findings / 0 clean / 2 on error; `--repo`, `--json`, `--help` all work (Change 5)
- [ ] Script header honestly states the never-assigned-milestone limitation; not wired into `gate_fast.sh` (Change 5)
- [ ] `tests/phase-milestones/` covers flagged / clean / empty-guard / --json / --help / bad-arg / fetch-failure; passes standalone AND is counted in `gate_fast.sh` (Change 6)
- [ ] `git check-ignore -q` confirms both new test files are tracked; mock `gh` is not run as a gate runner (Change 6)
- [ ] `tests/README.md` lists the new suite (Change 6)
- [ ] `ROADMAP.md` has the v1.10 entry; `planning.md` stale-v1.9 text corrected + v1.10 recorded; README counts updated where they exist (Change 7)
- [ ] `./scripts/gate_fast.sh` PASSes; `./scripts/check_spec_taxonomy.sh` clean
- [ ] No hardcoded owner/repo in the detector (default resolves from origin; `--repo` overrides)
- [ ] Language architecture matrix followed (Bash for operational tooling — consistent with all `scripts/*.sh`)
