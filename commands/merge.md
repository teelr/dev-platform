---
description: Squash-merge the current branch's PR into main, but ONLY after verifying CI is green. Mechanically enforces the no-merge-before-CI-green rule. Pulls main + deletes branch on both sides.
allowed-tools: Bash, EnterWorktree, ExitWorktree
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
if [[ "${IN_WORKTREE}" == "1" ]]; then
    gh pr merge "${PR_NUM}" --squash
    REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
    MERGED_BRANCH="$(gh pr view "${PR_NUM}" --json headRefName --jq .headRefName)"
    gh api -X DELETE "repos/${REPO}/git/refs/heads/${MERGED_BRANCH}"
else
    gh pr merge "${PR_NUM}" --squash --delete-branch
fi
```

In branch mode, `--delete-branch` deletes the branch both remotely and locally in one call. In worktree mode, `--delete-branch` fails the entire `gh pr merge` command — not just a warning — because `gh` can't check out anything else locally while the worktree holds the branch and `main` is already checked out in the primary checkout. So in worktree mode the merge runs without `--delete-branch`, and the remote branch is deleted explicitly via the GitHub API instead, which touches no local checkout state. The branch to delete is looked up from the PR itself (`MERGED_BRANCH`, via `gh pr view`) rather than assumed to be `${BR}` — Step 1 allows an explicit PR-number argument that can target a different PR than the one the current worktree's branch is for, so the two aren't always the same branch. Local deletion in worktree mode is unaffected — it's still handled by Step 5's `git branch -D "${BR}"` (always the worktree's own branch, regardless of which PR was merged), which runs after `ExitWorktree` has returned the session to the main checkout.

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
   git branch -D "${BR}" 2>/dev/null || true  # drop the local branch (worktree mode never asks gh to do this)
   git worktree prune
   ```

   If a backend was stopped, restart it from the main checkout with that
   project's own start script (e.g. `./scripts/start_dev.sh`) — `/merge` does
   not restart apps, it only frees the worktree.

Either way, this fetches the squash-merge commit and fast-forwards local main. The remote branch deletion from Step 4 already happened.

## Step 6: Report the merge

Print:

- The merge commit SHA (`git rev-parse HEAD`)
- The PR URL (for reference)
- In worktree mode: that the worktree was removed and the session is back in the main checkout.

## Step 7: Run post-merge automatically

`/merge` owns post-merge — it runs immediately, in the same turn, with no separate invocation. Do NOT stop and wait for the user to ask for it.

1. **Find the spec.** Look at `tasks/*-spec.md` files added/modified in `git diff HEAD~1 --name-only` for the just-merged commit.
2. **Generate the Change Summary — runs every time, unconditionally, before anything else below.** Produce a short **Problem/Opportunity → What shipped** summary using this fallback order (stop at the first tier that yields content):
   - **Tier 1 (preferred):** the shipped file this merge added. Run `git diff HEAD~1 --name-only -- tasks/shipped/`; if the merge added a file there, use its content directly — lightly trimmed if needed, not rewritten. This is the narrative `/code` already wrote pre-commit, already reviewed by `/review`. **Legacy fallback** (projects without `tasks/shipped/`): `git diff HEAD~1 HEAD -- planning.md` — if it shows added lines under a "Recently shipped" (or equivalently-named changelog) section, use that prose the same way.
   - **Tier 2:** If Tier 1 yielded nothing (no shipped file added, and no legacy `planning.md` changelog lines) but Step 1 found a spec, use the spec's Problem statement / Design Philosophy opening + its Change titles from the Overview section.
   - **Tier 3:** If no spec was touched either, use `gh pr view "${PR_NUM}" --json title,body` — the PR title as "What shipped", and the first line of the body (or the title itself if the body is empty) as "Problem/Opportunity".
   - Print it in the final report (sub-step 7 below) as:

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
   - If complete, **execute the standard Roadmap-Phase-completion actions**: mark the phase complete in `ROADMAP.md` + `planning.md` (today's date + status), close the GitHub milestone (`gh api -X PATCH repos/:owner/:repo/milestones/<n> -f state=closed`, or `./scripts/sync-milestones.sh --apply` where the project ships it), and **cut the release tag** at this merge's squash commit, named exactly as the phase version:

     ```bash
     gh release create "v<X.Y>" --target "$(git rev-parse HEAD)" --title "v<X.Y>: <Title>" --notes "See tasks/shipped/ for the phase record."
     ```

     The tag is the only identifier a consumer can pin (`taxonomy-check.yml@v<X.Y>`), so skipping it leaves the phase unreachable to every consumer — that is how tagging stopped at v1.13 and left twelve phases unpinnable. Then verify with `./scripts/check-phase-milestones.sh` and `./scripts/check-phase-tags.sh`.
   - If this merge did NOT complete a phase (a mid-phase Change), say so explicitly: "mid-phase merge — no phase-completion step." and continue to sub-step 6 (nothing further to commit from this sub-step).
6. **Land any file changes from steps 4-5.** If the project's rules forbid direct commits to `main` (check its CLAUDE.md), run the SAME mini-cycle this skill already knows how to do — reuse Steps 1-5 above on a fresh branch:
   - **Cut the branch worktree-aware, same as feature work.** Check `test -f .claude/worktree-deps` from the current directory (by this point in Step 7 the session is always back in the project's main checkout — Step 5 already returned it there, whether the feature branch itself used branch mode or worktree mode):
     - **Worktree-opted-in** (`.claude/worktree-deps` present): don't `git checkout -b` in the shared main checkout — that's the exact contamination this Change exists to prevent. Instead, mirror `/code`'s worktree-mode branch creation: capture `MAIN=$(git rev-parse --show-toplevel)`, call the **`EnterWorktree`** tool with `name` set to `chore/<slug>`, then link the project's heavy git-ignored deps into it: `bash ~/.claude/worktree/link-deps.sh "${MAIN}" "$(pwd)"`. The session is now re-rooted into `.claude/worktrees/chore/<slug>`.
     - **Branch mode** (no marker — dev-platform's own default, and every non-opted-in project): unchanged — `git checkout -b chore/<slug>`.
   - Commit the doc/config changes, push.
   - Run the project's local gate (`./scripts/gate_fast.sh` or equivalent) before committing — same rule as any other commit. A docs-only diff should be fast; if the project's gate doesn't already skip its expensive legs (test suite, lint, typecheck) for a diff touching only docs/roadmap files, that's worth a separate follow-on, not a reason to skip the gate here.
   - Open the PR (`gh pr create`), then run Steps 2-5 of THIS skill against it: poll CI, verify green, squash-merge, sync local main. This is the one case `/merge` calls its own logic recursively — it's still gated by the same non-overridable CI-green check as any other merge. **No further change is needed here**: Step 4 already re-derives `IN_WORKTREE` from the CURRENT session's toplevel path (not from any state carried over from the feature branch's own merge earlier in this same invocation), so it correctly detects the chore branch's worktree and takes the worktree-mode merge path (squash without `--delete-branch`, explicit `gh api -X DELETE` for the remote branch); Step 5 likewise already handles worktree-mode teardown generically (`ExitWorktree action: "keep"`, sync main, kill-by-cwd, `git worktree remove`, `git branch -D`, `git worktree prune`) for whatever worktree the session currently holds.
   - If the project instead permits a direct-to-`main` trivial-edit path for pure doc/roadmap changes, use that instead — it's faster and the outcome is identical. (This path never creates a branch at all, so the worktree-vs-branch-mode question doesn't apply to it.)
7. **Report what post-merge did** — starting with the Change Summary block from sub-step 2, then the actions taken (files changed, milestone closed, doc-update PR's own merge commit SHA if sub-step 6 ran), or "nothing further to do" if sub-steps 4-5 found nothing.

## Rules

- **The CI-green check is non-overridable.** No `--force`, no `--allow-red` flag. If CI is red, fix the branch. If CI is genuinely irrelevant (e.g., docs-only change that nonetheless triggered CI), the failure indicates something else worth investigating — don't bypass.
- **Always squash, never rebase or merge-commit.** The dev-platform default is squash-merge per the per-Spec-Phase strategy. Every PR becomes ONE commit on main.
- **Delete the branch on merge, in both modes.** Long-lived feature branches accumulate. Branch mode uses `gh pr merge --delete-branch` for both remote+local in one call; worktree mode deletes the remote branch via `gh api` and the local branch via Step 5's `git branch -D` (see Step 4 for why the two modes diverge).
- **Don't touch the spec or any code as part of the merge itself (Steps 1-6).** This command merges; it doesn't edit — until Step 7, which is scoped exclusively to the spec's own declared post-merge runbook plus the standard Roadmap-Phase-completion sub-step. Never improvise beyond what the spec's Post-merge section says or what the standard sub-step covers.
- **Post-merge is folded into `/merge`, not a separate manually-invoked step.** This is a deliberate exception to Workflow Step Discipline's general "stop between steps" rule — the user has pre-authorized it (durable instruction, `settings/claude-global.md` "Workflow Step Discipline") because post-merge has been run after every single merge in practice. Every OTHER step boundary in the chain still stops and waits for explicit invocation.
- **Still confirm before an unusually risky bespoke action.** Folding post-merge in covers the ordinary shape of post-merge work (doc updates, milestone closes, tag cuts, config syncs). A spec that asks for something well outside that shape — a prod deploy, a credential rotation, anything touching shared infrastructure beyond this repo — still gets a heads-up and a pause, per the general rule on hard-to-reverse actions.
- **The Change Summary always runs, even on a spec-less chore merge.** It is the one sub-step of post-merge that isn't gated on a spec being touched or a phase completing — every `/merge` report ends with it. It is chat-report-only: never write it to a file, never post it externally (no CHANGELOG, no GitHub Release, no PR comment) unless a future spec explicitly asks for that.
- **NEVER merge to a branch other than `main`.** PRs target `main` per the per-Spec-Phase strategy. If a PR targets something else, that's a different workflow.
