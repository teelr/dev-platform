# v1.46: Version Collision Rename Support

## Coding Specification for Implementation

## Design Philosophy

`scripts/check_version_collision.py` treats any Roadmap Phase version that is on `origin/main` under a different title as a collision (the "reused" branch, lines 124-127 and 137-141). That blocks a deliberate rename. Seen on `teelr/kermit-v3` PR #1325: milestone `v0.579` was renamed on GitHub from "Azure Second Deployment" to "Azure Deployment for Olsson", the PR updated the `ROADMAP.md` heading to match, and the job failed with `COLLISION: v0.579: this branch claims 'Azure Deployment for Olsson', but origin/main's ROADMAP.md already titles it 'Azure Second Deployment'`. Source: issue #147 (consumer: kermit-v3, pinned to `taxonomy-check.yml@v1.32`).

The fix follows the issue's ask. Renaming the GitHub milestone first is the deliberate act that marks the change as intentional. So for a reused version, the check looks up the milestone and does not report a collision when the milestone title equals this branch's title. It still fails when the milestone has the old or a different title, when the version has no milestone, and when the lookup cannot run. A reused version today fails with exit 1 with no network at all; that stays true when the lookup cannot run (exit 1, not 2, not 0), because passing a change through on a check that could not run is the failure to avoid. New versions keep the existing milestone cross-check unchanged.

Consumers get this only after they bump their pin to the tag cut for this phase (`taxonomy-check.yml@v1.46`). kermit-v3 is on `@v1.32` and does not pick it up until it bumps. This is stated in the PR and shipped file so nobody expects PR #1325 to turn green on merge.

Single Phase, single PR: one script edit, new test checks, one doc row. Well under the ~150-200 LOC threshold.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/check_version_collision.py` edit | Python | Editing an existing Python file in place; no new component. |
| `tests/version-collision/run.sh` edit | Bash | Extending the existing suite in its established language. |

## Overview

Phase 1: Rename-aware collision check

1. Change 1: Look up milestones for reused versions and accept a rename the milestone already carries
2. Change 2: Test the rename cases
3. Change 3: Docs (script docstring, `docs/CI-INTEGRATION.md` troubleshooting row)

---

## Phase 1: Rename-aware collision check

### Change 1: Accept a rename the milestone already carries

**Problem:** A reused version (on `origin/main` under a different title) is always reported as a collision, with no way to say "this is a rename".

**File:** `scripts/check_version_collision.py` (existing; `main()` lines 99-195)

**Implementation:**

1. Extract the Layer 2 milestone fetch (lines 148-176) into a helper, for example `_milestone_titles() -> tuple[dict[str, str] | None, str | None]`, returning the version-to-title map, or `None` plus a SKIP reason string for the three existing degraded cases: gh unavailable (line 175), slug undeterminable (line 172), `gh api` failed (line 169). Keep the three SKIP messages verbatim. The existing parse loop (lines 156-160) moves into the helper unchanged.
2. Fetch milestones when `new_versions` OR `reused_versions` is non-empty, once, not once per branch.
3. For each reused version:
   - If the map is available and `milestone_titles.get(version) == local_title`, it is an accepted rename. Do not add to `collisions`. Record it for an informational line: `OK: <version> renamed from '<main title>' to '<local title>' — GitHub milestone already carries the new title`.
   - Otherwise (map available but milestone missing or titled differently, OR map unavailable), add the existing collision string. When the map is unavailable, append ` (milestone lookup unavailable, so a rename cannot be confirmed)` to that string so the reader knows why a rename was not accepted. Do NOT set `degraded` for reused versions: a reused version with no confirming milestone is exit 1 exactly as today.
4. New-version handling is unchanged: a missing map still sets `degraded = True` and exits 2 when no collision was found. A SKIP message from the helper prints once even when both new and reused versions triggered the fetch.
5. Final result lines:
   - Collisions present: unchanged (exit 1, `COLLISION:` lines, renumber hint). Append one more hint line only when a reused collision exists: `If this is a deliberate rename, rename the GitHub milestone to the new title first, then re-run.`
   - Otherwise if `degraded`: unchanged (exit 2).
   - Otherwise exit 0. The existing `OK: N new version header(s), no collision detected` line prints as today; when the only change is accepted renames (`new_versions` empty), print `OK: N renamed version header(s) confirmed by GitHub milestone` instead, so the unchanged-count line does not say "0 new version header(s)".
6. Update the stale early-return at lines 128-130 only if needed: it already requires both dicts empty, so it needs no change.

Verify the assumption behind step 3 before relying on it: a milestone title is unique per repo, so one version maps to at most one title. Run `gh api --paginate repos/teelr/dev-platform/milestones?state=all --jq '.[].title' | sort | uniq -d` and confirm it prints nothing on a repo with many milestones. If duplicates of a version token appear, the map keeps the last one and the spec must say which wins.

**Acceptance Test:** The checks in Change 2 pass; `python3 scripts/check_version_collision.py .` on this branch exits 0 or reports only this branch's own new version.

---

### Change 2: Test the rename cases

**Problem:** The suite (`tests/version-collision/run.sh`) has no case where a reused version's milestone agrees with the branch.

**File:** `tests/version-collision/run.sh` (existing). Add after Check 4 (line 163). Reuse `run_check`, the `WORK` clone (origin/main has `- **v0.1: Foundation**`), the mock `gh` (`MOCK_MILESTONES_FILE`, `MOCK_FAIL`), and canned title files near line 95-104. Add title files `v01_renamed_title` (`v0.1: Something Else`) and `v01_old_title` (`v0.1: Foundation`).

Number the new checks continuing the file's numbering (read the last check number first; do not assume). Keep existing checks 2 (reused, no `VERSION_GUARD_REPO_SLUG`, no milestone file) passing unmodified: it must still exit 1 with no gh configured. Confirm it does before editing anything.

New checks, each a `record_pass`/`record_fail` pair in the file's style:

1. Reused v0.1 renamed to "Something Else", milestone `v0.1: Something Else` -> exit 0, output has `renamed` and no `COLLISION`.
2. Reused v0.1 renamed to "Something Else", milestone still `v0.1: Foundation` -> exit 1, `COLLISION`, hint about renaming the milestone first.
3. Reused v0.1 renamed to "Something Else", milestone `v0.1: Third Name` -> exit 1, `COLLISION`.
4. Reused v0.1 renamed, no v0.1 milestone in the list (`empty_titles`) -> exit 1, `COLLISION`.
5. Reused v0.1 renamed, `MOCK_FAIL=1` (gh api fails) -> exit 1 (NOT 2, NOT 0), `COLLISION`, output has `rename cannot be confirmed`.
6. Reused v0.1 renamed with an unresolvable slug (reuse Check 5's relative-origin setup) -> exit 1, not 0.
7. Mixed: v0.1 renamed with matching milestone plus a brand-new v0.2 with no milestone -> exit 0; same input with `MOCK_FAIL=1` -> exit 1 on the unconfirmed rename (collision beats degraded).
8. Mixed: a confirmed rename plus a new version whose milestone has a different title -> exit 1 naming only the new version.

**Mutation proof (mandatory):** for checks 1, 2, 5, run the suite against a copy of `check_version_collision.py` in the scratchpad with the change reverted or weakened (check 1: restore unconditional collision; check 5: make a failed lookup accept the rename) and show each fails. A test never seen failing is not evidence. Record the results in the shipped file.

**Acceptance Test:** `bash tests/version-collision/run.sh` all PASS; `./scripts/gate_fast.sh` PASS.

---

### Change 3: Docs

**Problem:** The script docstring and the consumer troubleshooting table say renames are fine "if `ROADMAP.md` and the milestone agree", which the code did not honor.

**Files:**

- `scripts/check_version_collision.py` docstring (lines 1-38): describe the rename rule under Layer 1 and the exit-code paragraph (reused with no confirming milestone is exit 1, including when the lookup cannot run).
- `docs/CI-INTEGRATION.md` line 199 (the `version-collision` fails row): replace "make sure `ROADMAP.md` and the milestone agree" with the concrete order: rename the GitHub milestone first, then update `ROADMAP.md`. Say it applies from the `@v1.46` tag onward and that older pins still fail.
- `docs/CI-INTEGRATION.md` line 8 mentions degrade behavior; add one clause that an unconfirmable rename fails rather than warns.
- `/code`'s doc step: new `tasks/shipped/` file, `ROADMAP.md` entry for v1.46 (list form, matching v1.45's shape), with a scope-honesty note below.

**Acceptance Test:** `grep -n "rename" docs/CI-INTEGRATION.md scripts/check_version_collision.py` shows the new text; markdown lint clean.

---

## What NOT to Do

- Do not let a failed or unavailable milestone lookup pass a reused version. The issue says this twice.
- Do not set `degraded` (exit 2) for reused versions. Today they exit 1, and exit 2 is "warn, not block" in consumers.
- Do not touch the new-version path's behavior or messages.
- Do not special-case a "rename" by guessing from title similarity. The milestone is the only signal.
- Do not edit kermit-v3 or comment its PR from this session (cross-project rule). Reply on issue #147 only, after merge and tag.
- Do not assume `claim_roadmap_version.py` needs a change; it does not read the reused-version branch. Confirm with `grep -n "reused" scripts/claim_roadmap_version.py` (expect no hits) before closing that out.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/check_version_collision.py` | Modify | Milestone helper; reused versions accepted when the milestone has the new title |
| `tests/version-collision/run.sh` | Modify | 8 new checks, all with failure shown on a mutated copy |
| `docs/CI-INTEGRATION.md` | Modify | Troubleshooting row and degrade note |
| `ROADMAP.md` | Modify | v1.46 entry |
| `tasks/shipped/<date>-v1.46-version-collision-rename-support.md` | New | Shipped record (written by `/code`) |

## Implementation Order

1. Change 1 (script).
2. Change 2 (tests, then mutation proof).
3. Change 3 (docs).

## Verification Checklist

- [ ] Renamed reused version with matching milestone: exit 0
- [ ] Milestone old title, different title, or missing: exit 1
- [ ] Lookup failure or unresolvable slug on a reused version: exit 1
- [ ] New-version behavior (exit 0 / 1 / 2) unchanged; existing checks 1-12 pass untouched
- [ ] Every new check shown failing against a mutated copy
- [ ] `./scripts/gate_fast.sh` PASS
- [ ] Not tested against the real GitHub API with a rename: the suite uses the mock `gh`. Do one live read-only run of the helper against `teelr/dev-platform` milestones and record the output.

## Scope honesty (for the shipped file)

- Consumers pinned to an older tag (kermit-v3 is on `@v1.32`) keep the old behavior until they bump to `@v1.46`. Verify the pin with `gh api repos/teelr/kermit-v3/contents/.github/workflows/dev-platform-gate.yml` rather than trusting the issue text if the shipped file repeats it.
- The tag is cut at post-merge (standard phase-completion sub-step), not by this change.
