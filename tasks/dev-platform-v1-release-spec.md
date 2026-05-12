# v1.0: Feature-Complete Release

## Coding Specification for Implementation

## Design Philosophy

v1.0 is not a feature release — it is a capstone. v0.1–v0.9 collectively deliver everything dev-platform set out to build: environment gateway, hooks, scaffolding, testing, monitoring, VSCode coverage, team enablement (CI, Pages, Milestones), fleet orchestration, and migration tooling. v1.0's job is to make that true on paper as well as in code: fix every stale reference in the docs and ship the stable release tag.

The scope is intentionally narrow. No new scripts, no new tooling, no structural changes. Every Change is a documentation accuracy fix surfaced by a systematic audit of `docs/index.md`, `README.md`, `ROADMAP.md`, and `planning.md` against the current codebase state. The guiding rule from `CLAUDE.md`: "NEVER overstate what a project actually has" — and its complement: don't understate either. Docs that say "v0.8 all shipped" when v0.9 also shipped violate that rule just as surely as claiming a feature that doesn't exist.

Single-Phase, single-PR strategy. Four Changes, all documentation. No code changes means no Language Architecture Matrix evaluation. The release ceremony (tag cut, milestone close, consumer-template pin bump) happens post-merge using the existing `scripts/sync-milestones.sh` and `gh release create`, following the pattern established in v0.7–v0.9.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| All Changes | Markdown | Documentation-only. No new code components. |

## Overview

1. Change 1 — Fix `docs/index.md`: stale "Latest release" + old workflow chain
2. Change 2 — Fix `README.md`: scaffolding row, `install.sh` categories, v0.9 mention, gate count, v0.9 scripts
3. Change 3 — Expand `ROADMAP.md` v1.0 entry from stub to full description
4. Change 4 — Update `planning.md`: retire v0.9 in-flight block, open v1.0

---

## Phase 1: Documentation Accuracy

### Change 1: Fix `docs/index.md`

**Problem:** Two stale items:

1. Line 17-18: "Latest release: … v0.6 (VSCode Coverage Server-Side) is the most recent tag; v0.7 cuts at Phase 4 completion." — massively stale; latest released tag is `v0.9`.
2. Line 21: Workflow chain reads `/plan → /code → /test → /review → /gate fast → /docs → commit → push → PR → CI → merge → post-merge` — the old chain. The canonical chain (since v0.8 chore PRs #20–#21) is `/plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge`.

**File:** `docs/index.md` (existing, line ~17–22)

**Implementation:**

Replace the "Latest release" section (lines 16–18):

```markdown
## Latest release

See [Releases](https://github.com/teelr/dev-platform/releases). `v0.9` (Migration tooling) is the current tag. `v1.0` (Feature-complete) is in progress.
```

Replace the workflow chain line (line 21):

```markdown
`/plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge`
```

**Acceptance Test:**

```bash
grep -n "v0.6\|v0.7 cuts" docs/index.md && echo FAIL || echo PASS
grep -n "gate fast → commit → push → /pr" docs/index.md && echo PASS || echo FAIL
grep -n "/test → /review" docs/index.md && echo FAIL || echo PASS
```

---

### Change 2: Fix `README.md`

**Problem:** Three stale items:

1. Line 25: `scaffolding/` row says "New-project starter templates — populated by future spec" — v0.3 shipped three templates (`go-service`, `python-agent`, `next-frontend`) + `scripts/new-project.sh` on 2026-05-10.
2. Line 38: `install.sh` accepts list is missing the `vscode` category added in v0.6.
3. Line 58: The Roadmap paragraph says "v0.1 – v0.8 all shipped" (v0.9 missing), references gate as "131 checks" (now 143), and lists fleet scripts but omits v0.9's `migrate-workflow-chain.sh` and `audit-project-drift.sh`.

**File:** `README.md` (existing, lines 25, 38, 58)

**Implementation:**

Line 25 — replace `scaffolding/` row:

```markdown
| `scaffolding/` | New-project starter templates (`go-service`, `python-agent`, `next-frontend`). `scripts/new-project.sh` scaffolds from a template via conversational Q&A; see `docs/NEW-PROJECT.md`. |
```

Line 38 — update install.sh categories:

```markdown
`./scripts/install.sh` accepts: `commands`, `skills`, `settings`, `hooks`, `vscode`, or `all` (default).
```

Line 58 — update the Roadmap paragraph. Replace from "v0.1 – v0.8 all shipped" to the end of that sentence with:

```
**v0.1 – v0.9 all shipped 2026-05-08 – 2026-05-12** (v0.7 Team Enablement closes with the `v0.7` release tag, the live Pages docs site at [teelr.github.io/dev-platform](https://teelr.github.io/dev-platform/), and GitHub Actions CI required on every PR; v0.8 Cross-project orchestration closes with the `v0.8` release tag and ships the full fleet-operations toolchain; v0.9 Migration tooling closes with the `v0.9` release tag and ships `scripts/migrate-workflow-chain.sh` + `scripts/audit-project-drift.sh` for cross-project drift detection and repair).
```

Also update the gate check count in that paragraph: `131 checks` → `143 checks`.

Add v0.9 scripts to the command list at end of line 58, after the `/merge` sentence:

```
`./scripts/audit-project-drift.sh` for a read-only cross-project chain + taxonomy drift report; `./scripts/migrate-workflow-chain.sh --project <name> [--apply]` (v0.9) to rewrite old workflow chain references in a project's CLAUDE.md (dry-run default).
```

**Acceptance Test:**

```bash
grep -n "populated by future spec" README.md && echo FAIL || echo PASS
grep -n "vscode" README.md | grep "install.sh accepts" && echo PASS || echo FAIL
grep -n "v0.9" README.md | grep -q "shipped" && echo PASS || echo FAIL
grep -n "143 checks" README.md && echo PASS || echo FAIL
grep -n "audit-project-drift" README.md && echo PASS || echo FAIL
```

---

### Change 3: Expand `ROADMAP.md` v1.0 entry

**Problem:** The v1.0 entry (line 16) is a stub: `*(planned)* — cuts the first stable release tag once v0.1–v0.9 ship.` Now that v1.0 is actively shipping, it needs the same detail level as every other completed entry.

**File:** `ROADMAP.md` (existing, line 16)

**Implementation:**

Replace the v1.0 entry with a full description. Leave `*(planned)*` as the status — `/docs` updates it to `*(complete — <date>)*` at ship time, same pattern as every prior entry:

```markdown
- **v1.0: Feature-complete for solo + team** *(planned)* — capstone release; no new features, documentation accuracy pass only. Fixes stale references accumulated since v0.6: `docs/index.md` "Latest release" section + workflow chain; `README.md` scaffolding row + `install.sh` categories + v0.9 ship mention + gate count; `ROADMAP.md` v1.0 stub → full description; `planning.md` in-flight block. Post-merge: `scripts/sync-milestones.sh --apply` verifies Milestone state; `gh release create v1.0` cuts the stable tag; v1.0 GitHub Milestone closed; consumer-template default-pin bumped `@v0.8` → `@v1.0` (chore PR after tag exists). Subsequent enhancements become `v1.1`, `v1.2`, …; breaking workflow changes become `v2.0`.
```

**Acceptance Test:**

```bash
grep -n "documentation accuracy" ROADMAP.md && echo PASS || echo FAIL
grep -n "consumer-template.*v1.0" ROADMAP.md && echo PASS || echo FAIL
# taxonomy check must still pass
./scripts/gate_fast.sh 2>&1 | grep "spec taxonomy" | grep PASS
```

---

### Change 4: Update `planning.md`

**Problem:** The "In flight" section (line 39) still describes v0.9 Phase 2 as in-progress with branch details. v0.9 shipped as PR #22. Planning.md needs to reflect v1.0 as active and v0.9 as complete.

**File:** `planning.md` (existing, line ~39–46)

**Implementation:**

Replace the entire "In flight" block (from "- **v0.9 Phase 2 (Migration Tools)** — implemented" through "- Next after v0.9: **v1.0 Feature-complete**.") with:

```markdown
## In flight

- **v1.0 (Feature-Complete Release) — in progress** on branch `v1.0/phase-1-docs-accuracy`:
  - Change 1: `docs/index.md` — stale "Latest release" + old workflow chain fixed.
  - Change 2: `README.md` — scaffolding row, install.sh categories, v0.9 mention, gate count, v0.9 scripts.
  - Change 3: `ROADMAP.md` v1.0 entry expanded from stub.
  - Change 4: `planning.md` in-flight block updated (this entry).
  - Post-merge: sync-milestones, cut `v1.0` tag, close v1.0 Milestone, chore PR pin bump @v0.8 → @v1.0.
```

Also add v0.9 to the "Recently shipped" section with a one-line summary (after the existing last entry, before "In flight"):

```markdown
- v0.9 Migration Tooling — **closed** (2026-05-11, PRs #19 + #22 + fix `44d002e`): `scripts/migrate-workflow-chain.sh` (6 sed patterns + perl multi-line variant, dry-run/apply/idempotent) + `scripts/audit-project-drift.sh` (read-only cross-project chain + taxonomy report) + 12-assertion `tests/migration/run.sh`. Gate at 143 PASS. Post-merge chain migrations ran clean (all 5 registry projects CLEAN per audit).
```

**Acceptance Test:**

```bash
grep -n "v0.9 Phase 2.*in-progress\|In flight.*v0.9" planning.md && echo FAIL || echo PASS
grep -n "v1.0.*in progress" planning.md && echo PASS || echo FAIL
grep -n "v0.9 Migration Tooling.*closed" planning.md && echo PASS || echo FAIL
```

---

## What NOT to Do

- **Do not cut the v1.0 release tag as a Change.** The tag must be cut from the merge commit SHA, which doesn't exist until the PR lands. The release cut is a post-merge step, same as every prior release. Cutting it early breaks the pattern and the tag would point at the wrong commit.
- **Do not bump the consumer template pin (@v0.8 → @v1.0) in this spec.** The v1.0 tag must exist before `fleet-pins.sh --latest v1.0` can verify the bump works. Ship the chore PR after the tag is cut (same as v0.8's chore PR #18).
- **Do not add a workflow chain line to keystone's CLAUDE.md from this session.** Keystone is missing the chain line entirely, but adding it is a project-side write, not a dev-platform doc fix. Handle from a keystone session.
- **Do not change the `*(planned)*` annotation in ROADMAP.md to `*(complete)*` in Change 3.** That transition is `/docs`'s job at ship time, matching the pattern of every prior entry. The Change only expands the stub description.
- **Do not over-expand the README line 58 paragraph further.** It's already long. Add only what's missing (v0.9 mention, count, two new scripts) — don't restructure the whole paragraph.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `docs/index.md` | Modify | Fix stale "Latest release" section + old workflow chain |
| `README.md` | Modify | Fix scaffolding row, install.sh categories, v0.9 mention, gate count, v0.9 scripts |
| `ROADMAP.md` | Modify | Expand v1.0 entry from stub to full description |
| `planning.md` | Modify | Retire v0.9 in-flight block; open v1.0 in-flight block; add v0.9 to Recently shipped |

## Implementation Order

1. Change 1 (`docs/index.md`) — no dependencies; isolated file
2. Change 2 (`README.md`) — no dependencies; isolated file
3. Change 3 (`ROADMAP.md`) — no dependencies; must pass taxonomy check after edit
4. Change 4 (`planning.md`) — depends on Changes 1–3 being ready to describe accurately

All four Changes ship in a single commit on a single branch (`v1.0/phase-1-docs-accuracy`). Single-PR strategy: 4 Changes, all docs, < 50 LOC diff total.

## Post-merge Runbook

After the PR merges:

1. Record the merge commit SHA:
   ```bash
   git log --oneline -1
   ```

2. Sync milestones to verify all prior phases are closed:
   ```bash
   ./scripts/sync-milestones.sh --apply
   ```

3. Cut the v1.0 release tag:
   ```bash
   gh release create v1.0 --target <merge_sha> \
     --title "v1.0: Feature-complete for solo + team" \
     --notes "Capstone release. v0.1–v0.9 all shipped. Documentation accuracy pass. See ROADMAP.md for the full history."
   ```

4. Close the v1.0 GitHub Milestone:
   ```bash
   MILESTONE_ID=$(gh api repos/teelr/dev-platform/milestones?state=open \
     --jq '.[] | select(.title | startswith("v1.0:")) | .number')
   gh api -X PATCH "repos/teelr/dev-platform/milestones/${MILESTONE_ID}" -f state=closed
   ```

5. Open a chore PR to bump the consumer template pin `@v0.8` → `@v1.0`:
   - Edit `extensions/github-actions/dev-platform-gate.yml` line: `uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@v0.8` → `@v1.0`
   - Standard chore PR flow: branch → gate → commit → push → `/pr` → CI → `/merge`

6. Add the workflow chain line to keystone's CLAUDE.md from a keystone session:
   ```
   - **Dev workflow** — `/plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge`
   ```

## Verification Checklist

- [ ] `docs/index.md`: no mention of v0.6 as "most recent tag"; no old workflow chain
- [ ] `README.md`: `scaffolding/` row describes actual templates; `vscode` in install.sh categories; v0.9 shipped; gate count 143; v0.9 scripts listed
- [ ] `ROADMAP.md`: v1.0 entry describes deliverables; taxonomy check still passes
- [ ] `planning.md`: v0.9 in-flight block gone; v1.0 in-flight block present; v0.9 in Recently shipped
- [ ] `./scripts/gate_fast.sh` → 143 PASS, 0 FAIL
- [ ] Language architecture matrix followed — N/A (docs only)
- [ ] No `./scripts/gate_fast.sh` regressions from doc edits (taxonomy scan touches ROADMAP.md + planning.md)
