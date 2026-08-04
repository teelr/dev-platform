# Fix /merge's --delete-branch failure in worktree mode

## Coding Specification for Implementation

## Design Philosophy

`commands/merge.md` Step 4 runs `gh pr merge "${PR_NUM}" --squash --delete-branch` while the
session may still be inside a git worktree (worktree-mode teardown doesn't happen until Step 5's
`ExitWorktree` call). `gh`'s `--delete-branch` flag deletes the branch on **both** the remote and
the local checkout — the local half requires `gh` to check something else out first, and that
fails from inside a worktree because `main` is already checked out in the primary checkout:

```text
fatal: 'main' is already used by worktree at '/home/rich/dev/projects/kermit-v3'
```

This is a **hard failure of the whole `gh pr merge` command**, not a warning — confirmed live on
kermit-v3 PR #236 (2026-08-04). The remote squash-merge itself succeeds (GitHub shows
`state: MERGED`), but the command's non-zero exit trips Step 4's existing "If `gh pr merge`
errors, report verbatim and STOP. Don't retry" rule — so the agent stops right after the remote
merge succeeded but before Step 5 ever runs, leaving the remote branch undeleted and the worktree
untorn-down. The current code comment at `commands/merge.md:86` claims this is an expected,
benign warning; that claim is wrong and needs correcting alongside the fix.

The fix splits `--delete-branch`'s two responsibilities apart, but **only in worktree mode**:

- **Branch mode** (`IN_WORKTREE=0`): unchanged. `gh pr merge --squash --delete-branch` already
  works correctly here — there's no competing worktree holding `main` or the feature branch.
- **Worktree mode** (`IN_WORKTREE=1`): drop `--delete-branch` from the `gh pr merge` call (avoids
  the local-checkout conflict entirely) and delete the remote branch explicitly via the GitHub
  API instead, which touches no local checkout state. Local deletion is already handled by Step
  5's existing `git branch -D "${BR}"` (which runs after `ExitWorktree` has returned the session
  to the main checkout) — that line needs no change, but its purpose shifts from "cleaning up
  after gh's failed local delete" to "the sole local delete path," so its context comment should
  reflect that.

This is a single-file, single-command fix — no new component, no architecture decision, no
Roadmap Phase. Per the dev-platform "Per-Spec-Phase branching decision rule"
(`/home/rich/dev/CLAUDE.md`), a Phase this small (~10 line diff) uses a single `fix/` branch
rather than a `v<X.Y>/phase-1-*` Roadmap-Phase branch — matching the precedent set by PR #53
(`feat/claude-code-auth-pin`) and PR #54 (`chore/dev-milvus-compaction-timer`), neither of which
opened a new Roadmap Phase for a scoped, conversational-sized fix.

## Language Decisions

N/A — this change edits Bash embedded in an existing Markdown slash-command file
(`commands/merge.md`). No new component is introduced; nothing to evaluate against the Language
Architecture Decision Matrix.

## Overview

1. Change 1 — Split `--delete-branch` in `commands/merge.md` Step 4: branch-mode unchanged,
   worktree-mode does an explicit remote-only delete via `gh api`; fix the stale comment; update
   the Rules section's blanket "`--delete-branch` flag is mandatory" claim to reflect the
   mode-conditional behavior.

---

## Phase 1: Worktree-mode delete-branch fix

### Change 1: Make Step 4's merge command conditional on `IN_WORKTREE`

**Problem:** `gh pr merge --squash --delete-branch` fails outright when run from inside a
worktree, because `main` is already checked out in the primary checkout and `gh` can't check it
out again to complete the local branch deletion. This aborts the whole command before Step 5
(worktree teardown, which already exists and works) ever runs, leaving both the remote branch and
the worktree undeleted.

**File:** `commands/merge.md` (existing file, Step 4, currently lines 67–88)

**Implementation:**

The `IN_WORKTREE` / `WT` / `BR` variables are already computed earlier in Step 4
(`commands/merge.md:72-78`) — do not duplicate or move that block, just branch on
`IN_WORKTREE` for the merge call that follows it.

Replace the current single unconditional merge call:

```bash
gh pr merge "${PR_NUM}" --squash --delete-branch
```

(currently at `commands/merge.md:83`, with its explanatory prose at lines 80, 85-86) with a
conditional block:

```bash
if [[ "${IN_WORKTREE}" == "1" ]]; then
    gh pr merge "${PR_NUM}" --squash
    REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
    gh api -X DELETE "repos/${REPO}/git/refs/heads/${BR}"
else
    gh pr merge "${PR_NUM}" --squash --delete-branch
fi
```

Update the surrounding prose (currently lines 80 and 85-86) to explain the split. Replace:

> The `--delete-branch` flag deletes the remote branch (and the local branch in branch mode). In
> worktree mode gh may warn it can't delete the local branch while the worktree holds it — that's
> expected and handled in Step 5.

with prose along these lines (adjust wording to fit house style, keep the technical content):

> In branch mode, `--delete-branch` deletes the branch both remotely and locally in one call. In
> worktree mode, `--delete-branch` fails the entire `gh pr merge` command — not just a warning —
> because `gh` can't check out anything else locally while the worktree holds the branch and
> `main` is already checked out in the primary checkout. So in worktree mode the merge runs
> without `--delete-branch`, and the remote branch is deleted explicitly via the GitHub API
> instead, which touches no local checkout state. Local deletion in worktree mode is unaffected —
> it's still handled by Step 5's `git branch -D "${BR}"`, which runs after `ExitWorktree` has
> returned the session to the main checkout.

Leave the "If `gh pr merge` errors, report verbatim and STOP. Don't retry." line (currently line
88) as-is — it still applies to both branches of the conditional.

**Do not touch Step 5.** Its worktree-teardown logic (process-kill-by-cwd, `git worktree remove`,
`git branch -D "${BR}"`, `git worktree prune`) already works correctly today and needs no code
change. Only its explanatory comment at `commands/merge.md:120` needs a small wording update: it
currently reads `# drop the local branch gh couldn't` (implying it's cleaning up after a failed
`gh` attempt) — since worktree mode no longer asks `gh` to do local deletion at all, reword to
something like `# drop the local branch (worktree mode never asks gh to do this)`.

Also update the Rules section (currently `commands/merge.md:156`):

> **Delete the branch on merge.** Long-lived feature branches accumulate; the `--delete-branch`
> flag is mandatory.

The claim that `--delete-branch` is unconditionally used is no longer accurate. Reword to state
the outcome (both remote and local branch are always deleted on merge) rather than naming a
single flag, e.g.:

> **Delete the branch on merge, in both modes.** Long-lived feature branches accumulate. Branch
> mode uses `gh pr merge --delete-branch` for both remote+local in one call; worktree mode deletes
> the remote branch via `gh api` and the local branch via Step 5's `git branch -D` (see Step 4 for
> why the two modes diverge).

**Acceptance Test:**

Static verification (no live PR needed to confirm the file is well-formed):

```bash
# The conditional exists and references both delete paths
grep -n 'if \[\[ "\${IN_WORKTREE}" == "1" \]\]' commands/merge.md
grep -n 'gh api -X DELETE "repos/\${REPO}/git/refs/heads/\${BR}"' commands/merge.md
grep -n 'gh pr merge "\${PR_NUM}" --squash --delete-branch' commands/merge.md   # still present, branch-mode arm only
grep -c 'gh pr merge "\${PR_NUM}" --squash' commands/merge.md                  # 2: one bare (worktree), one with --delete-branch (branch mode)

# The stale "expected and handled" warning claim is gone
! grep -q "that's expected and handled in Step 5" commands/merge.md

# Bash syntax check on the embedded fenced blocks (extract + shellcheck-lint informally)
# gate_fast.sh's constitutional checks + tests/frontmatter suite will validate the file's
# frontmatter and structure; there is no dedicated commands/ bash-syntax extractor today, so
# manually re-read the rendered Step 4 block after editing to confirm it's valid bash.
```

Live verification (per the original bug report, run once this ships and is installed):

```bash
./scripts/install.sh commands   # deploy the updated commands/merge.md to ~/.claude/
```

Then, from any worktree-mode project with an actual merged-but-not-yet-cleaned-up scenario (PA,
Keystone, SQRL, kermit-v3), run `/merge` on a real PR and confirm:

1. No `fatal: 'main' is already used by worktree` error appears.
2. `git ls-remote --heads origin <branch>` returns nothing after the merge (remote branch is
   actually gone).
3. The local branch is gone too (`git branch --list <branch>` in the main checkout returns
   nothing) via Step 5's unchanged `git branch -D "${BR}"`.

This live check happens in the consuming project's own session, not dev-platform's — dev-platform
itself runs in branch mode (`test -f .claude/worktree-deps` is false here), so this bug's
worktree-mode path can't be exercised live from within this repo.

---

## What NOT to Do

- Don't touch Step 5's teardown logic (process-kill-by-cwd loop, `git worktree remove --force`,
  `git worktree prune`) — it already works correctly and is orthogonal to this bug.
- Don't change branch-mode behavior — `gh pr merge --squash --delete-branch` works fine there
  today; only worktree mode needs the split.
- Don't reorder Step 4 and Step 5 (the "reorder" alternative considered and rejected during triage
  — dropping `--delete-branch` in worktree mode is simpler and doesn't change step ordering or
  touch the `ExitWorktree` call site).
- Don't add a retry loop or `--allow-red`-style override around the `gh api -X DELETE` call — if
  the remote delete fails, let it fail visibly per the existing "report verbatim and STOP" rule;
  don't silently swallow it.
- Don't invent a new Roadmap Phase / milestone for this — it's a scoped bug fix on an existing
  command, same class as PR #53/#54.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `commands/merge.md` | Modify | Step 4: conditional `gh pr merge` call (branch mode unchanged, worktree mode drops `--delete-branch` + explicit `gh api -X DELETE` remote-branch call) + corrected prose; Step 5: reworded comment on the existing `git branch -D "${BR}"` line; Rules section: reworded "Delete the branch on merge" bullet. |

## Implementation Order

1. Change 1 (only change) — edit `commands/merge.md` per the Implementation section above.

## Verification Checklist

- [ ] Step 4's `gh pr merge` call is conditional on `IN_WORKTREE`; branch-mode arm still passes
      `--squash --delete-branch` unchanged.
- [ ] Worktree-mode arm runs `gh pr merge --squash` (no `--delete-branch`) followed by
      `gh api -X DELETE "repos/${REPO}/git/refs/heads/${BR}"`.
- [ ] `${REPO}` is derived via `gh repo view --json nameWithOwner --jq .nameWithOwner` (not
      hardcoded, not reusing an undefined `:owner/:repo` placeholder — `gh api` doesn't expand
      that syntax outside specific documented endpoints).
- [ ] The stale "that's expected and handled in Step 5" comment is replaced with prose describing
      the actual hard-failure mode and the new remote/local split.
- [ ] Step 5's `git branch -D "${BR}"` line is unchanged in behavior; only its comment is reworded.
- [ ] Rules section no longer claims `--delete-branch` is unconditionally mandatory.
- [ ] `./scripts/gate_fast.sh` passes (constitutional checks + command-frontmatter validator +
      existing suites — no new test suite needed for a single-command-file prose/bash edit).
- [ ] Manual re-read of the full edited Step 4/5/Rules sections for internal consistency (variable
      names `${BR}`, `${WT}`, `${REPO}`, `${IN_WORKTREE}` all match their definitions earlier in
      the file).
