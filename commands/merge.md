---
description: Squash-merge the current branch's PR into main, but ONLY after verifying CI is green. Mechanically enforces the no-merge-before-CI-green rule. Pulls main + deletes branch on both sides.
allowed-tools: Bash, ExitWorktree
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

Before merging, detect whether this session is inside a worktree (the v1.4 worktree workflow — only opted-in projects). Record what you'll need for teardown in Step 5:

```bash
IN_WORKTREE=0
if [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" && "$(git rev-parse --show-toplevel)" == *"/.claude/worktrees/"* ]]; then
    IN_WORKTREE=1
    WT="$(git rev-parse --show-toplevel)"   # worktree dir to remove later
    BR="$(git branch --show-current)"        # branch the worktree holds
fi
```

Then squash-merge:

```bash
gh pr merge "${PR_NUM}" --squash --delete-branch
```

The `--delete-branch` flag deletes the remote branch (and the local branch in branch mode). In worktree mode gh may warn it can't delete the local branch while the worktree holds it — that's expected and handled in Step 5.

If `gh pr merge` errors, report verbatim and STOP. Don't retry.

## Step 5: Sync local main

**Branch mode** (`IN_WORKTREE=0` — the default): fast-forward local main in place.

```bash
git checkout main && git pull --ff-only
```

**Worktree mode** (`IN_WORKTREE=1`): the session is inside `.claude/worktrees/<branch>`, and git won't let you `checkout main` there (main is checked out in the main working tree). Return the session to the main checkout first, then sync and remove the now-merged worktree:

1. Call the **`ExitWorktree` tool** with `action: "keep"`. Use `keep`, not `remove` — after a squash-merge the branch's commits aren't present as commits, so `remove` would hit the unmerged-changes refusal. `keep` returns the session to the main checkout cleanly.
2. In the main checkout:

   ```bash
   git checkout main && git pull --ff-only
   # Before removing the worktree: stop any process whose cwd is INSIDE it. A
   # backend started from within .claude/worktrees/<branch>/ has its cwd deleted
   # when the worktree is removed, so every later `claude` subprocess fails with
   # "cwd was deleted" → ProcessError → red chat. Match by cwd (the actual
   # failure condition), NOT by a hardcoded port — this command is universal
   # across projects. The session itself is safe: ExitWorktree already moved it
   # back to the main checkout, so its cwd is no longer under ${WT}.
   for _cwd_link in /proc/[0-9]*/cwd; do
       [[ "$(readlink "${_cwd_link}" 2>/dev/null)" == "${WT}"* ]] || continue
       _pid="$(basename "$(dirname "${_cwd_link}")")"
       echo "Stopping PID ${_pid} — its cwd is inside the worktree being removed"
       kill "${_pid}" 2>/dev/null || true
   done
   sleep 1   # let any stopped process release the worktree before removal
   git worktree remove --force "${WT}"        # drop the now-merged worktree
   git branch -D "${BR}" 2>/dev/null || true  # drop the local branch gh couldn't
   git worktree prune
   ```

   If a backend was stopped, restart it from the main checkout with that
   project's own start script (e.g. `./scripts/start_dev.sh`) — `/merge` does
   not restart apps, it only frees the worktree.

Either way, this fetches the squash-merge commit and fast-forwards local main. The remote branch deletion from Step 4 already happened.

## Step 6: Report + prompt next step

Print:

- The merge commit SHA (`git rev-parse HEAD`)
- The PR URL (for reference)
- In worktree mode: that the worktree was removed and the session is back in the main checkout.
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
