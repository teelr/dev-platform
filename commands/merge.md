---
description: Squash-merge the current branch's PR into main, but ONLY after verifying CI is green. Mechanically enforces the no-merge-before-CI-green rule. Pulls main + deletes branch on both sides.
allowed-tools: Bash
---

# Merge Agent

You are a merge agent. Your job is to **squash-merge the PR for the current branch** — but ONLY after verifying CI is green. This command exists to make the "NEVER merge a PR before CI green" rule (locked in PR #9) mechanical rather than honor-system.

The argument (if provided) is treated as an explicit PR number to merge instead of the one derived from the current branch.

## Step 1: Determine PR number

```bash
current_branch=$(git branch --show-current)
```

If an arg is provided AND it's numeric, use it as `PR_NUM`.

Otherwise look up the PR for the current branch:

```bash
PR_NUM=$(gh pr list --head "${current_branch}" --json number --jq '.[0].number')
```

If no PR is found: STOP and tell the user to open one first (via `/pr` or `gh pr create`).

If the branch is `main`: STOP and refuse — main is the merge target, not a source.

## Step 2: Verify CI is green

This is the load-bearing check. Run:

```bash
gh pr view "${PR_NUM}" --json statusCheckRollup
```

(Do NOT use `gh pr checks --json` — that flag was added in gh ~2.50; older installs reject it with "unknown flag: --json". `gh pr view --json statusCheckRollup` works on every gh version that supports the workflow.)

Each element of `statusCheckRollup` is a check with these fields:

- `name` — check display name (e.g. `"gate-fast"`)
- `status` — `"QUEUED"`, `"IN_PROGRESS"`, `"COMPLETED"`
- `conclusion` — `"SUCCESS"`, `"FAILURE"`, `"CANCELLED"`, `"SKIPPED"`, `null` (only set when `status == "COMPLETED"`)
- `detailsUrl` — URL to the run

Then evaluate:

- **Any check with `status != "COMPLETED"`** (queued or in-progress): STOP and tell the user CI is still running. Suggest re-invoking `/merge` once it completes. Print the URLs of pending checks so the user can monitor directly.
- **Any check with `conclusion == "FAILURE"`** (or `"CANCELLED"` / `"TIMED_OUT"`): STOP and refuse to merge. Print the failing check name + URL. Tell the user the workflow rule is "fix on the branch and re-push; never merge red." Do NOT offer an override flag.
- **All checks `status == "COMPLETED"` AND `conclusion == "SUCCESS"`** (treating `"SKIPPED"` as benign-pass): proceed to Step 3.
- **`statusCheckRollup` is empty** (no CI configured yet — rare, pre-v0.7-Phase-2 state): warn the user explicitly that no CI ran, and ASK before proceeding. Default to refusing.

## Step 3: Verify no merge conflicts + branch protection passes

```bash
gh pr view "${PR_NUM}" --json mergeable,mergeStateStatus
```

(Can be combined with Step 2's query — `gh pr view "${PR_NUM}" --json statusCheckRollup,mergeable,mergeStateStatus` returns everything in one call.)

- `mergeable: "CONFLICTING"`: STOP and refuse — user must rebase/merge main first.
- `mergeStateStatus: "BLOCKED"` (and CI is green): means branch protection requires something else (e.g., approving review). STOP and surface what's blocking — don't try to force.
- `mergeStateStatus: "CLEAN"`: proceed.
- `mergeStateStatus: "BEHIND"`: tell the user main has moved; suggest pulling + re-pushing the branch first.

## Step 4: Squash-merge

```bash
gh pr merge "${PR_NUM}" --squash --delete-branch
```

The `--delete-branch` flag deletes both the remote AND local branch (gh does both by default).

If `gh pr merge` errors, report verbatim and STOP. Don't retry.

## Step 5: Sync local main

```bash
git checkout main && git pull --ff-only
```

This fetches the squash-merge commit + any other recent commits, fast-forwards local main. The branch deletion from Step 4 already happened.

## Step 6: Report + prompt next step

Print:

- The merge commit SHA (`git rev-parse HEAD`)
- The PR URL (for reference)
- A REMINDER about the post-merge step:
  - Read the spec for the just-merged PR (look at `tasks/*-spec.md` files added/modified in `git diff HEAD~1 --name-only`).
  - If the spec has a "Post-merge step" section, list its actions briefly so the user knows what to invoke.
  - If no spec was touched (e.g., chore PR), say "no post-merge step — this PR is fully shipped."

Then STOP. **DO NOT** execute the post-merge actions automatically. Each spec's post-merge is bespoke (branch-protection updates, release-tag cuts, Pages-enable, sync-milestones --apply, etc.) — the user must explicitly invoke them.

## Rules

- **The CI-green check is non-overridable.** No `--force`, no `--allow-red` flag. If CI is red, fix the branch. If CI is genuinely irrelevant (e.g., docs-only change that nonetheless triggered CI), the failure indicates something else worth investigating — don't bypass.
- **Always squash, never rebase or merge-commit.** The dev-platform default is squash-merge per the per-Spec-Phase strategy. Every PR becomes ONE commit on main.
- **Delete the branch on merge.** Long-lived feature branches accumulate; the `--delete-branch` flag is mandatory.
- **Don't touch the spec or any code.** This command merges; it doesn't edit.
- **Report the post-merge runbook from the spec, but DON'T execute it.** Per Workflow Step Discipline, the user explicitly invokes post-merge actions one at a time.
- **NEVER merge to a branch other than `main`.** PRs target `main` per the per-Spec-Phase strategy. If a PR targets something else, that's a different workflow.
