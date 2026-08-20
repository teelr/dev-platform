# Isolate /merge's post-merge chore branch in its own worktree

## Coding Specification for Implementation

## Design Philosophy

`commands/merge.md` Step 7 sub-step 6 ("Land any file changes from steps 4-5") cuts a
`chore/<slug>` branch to commit doc/config updates (Roadmap-Phase completion, Change Summary
artifacts, etc.) when a project's rules forbid direct commits to `main`. By the time sub-step 6
runs, Step 5 has already returned the session to the project's **shared main checkout** — in
branch mode because it never left it, and in worktree mode because Step 5's `ExitWorktree
action: "keep"` explicitly moved it back there. Sub-step 6 then does `git checkout -b chore/<slug>`
**in that same shared checkout**, regardless of whether the project is worktree-opted-in for its
own feature work.

This defeats the exact isolation guarantee worktree-opted-in projects exist for. Feature work
already gets a private `.claude/worktrees/<branch>` copy via `EnterWorktree` (wired into `/plan`
Step 2 and `/code`'s fallback) specifically so two concurrent chats never share a working tree.
Post-merge chore work — running in the SAME `/merge` invocation, often seconds after the feature
worktree was torn down — currently skips that isolation and commits straight into the shared
checkout, which may have another session's uncommitted edits sitting in it at that exact moment.

**Live incident (issue #73, kermit-v3, 2026-08-20):** running `/merge` for PR #459, the post-merge
`chore/close-v0.109` branch was cut in the shared main checkout while a second, concurrent Claude
session was actively editing three files in that same checkout. `git status` on the chore branch
showed 4 unexpected dirty files; `./scripts/gate_fast.sh` spuriously FAILed (`pytest`) because it
ran against the whole contaminated tree instead of the intended 2-file diff; the docs-only-diff
skip (v1.14) also got confused by the same contamination and didn't take its fast path. No harm
landed — the agent staged only the 2 intended files by explicit path (never `git add -A`) and
trusted CI's clean checkout as the authoritative gate — but an agent that ran `git add -A` or
trusted the local gate's FAIL at face value could have swept another session's in-progress work
into an unrelated PR, or blocked entirely on a false failure.

The fix mirrors the existing feature-work pattern exactly, reusing sub-step 6's own existing
recursive-invocation design rather than inventing new plumbing: **when the project is
worktree-opted-in (`.claude/worktree-deps` present), sub-step 6 calls `EnterWorktree` for the
`chore/<slug>` branch instead of `git checkout -b` in place — same as `/code`'s worktree-mode
branch creation.** Sub-step 6 already ends by "running Steps 2-5 of THIS skill" against the
chore PR once it's opened. Step 4 already re-derives `IN_WORKTREE` fresh at its own start by
checking whether the CURRENT session's toplevel is under `.claude/worktrees/` — it has no memory
of what mode the FEATURE branch used earlier in the same `/merge` invocation. So once sub-step 6
enters a worktree for the chore branch, Step 4's existing conditional (already shipped in the
`merge-delete-branch-worktree-fix-spec`) and Step 5's existing worktree teardown (`ExitWorktree
keep`, sync main, kill-by-cwd, `git worktree remove`, `git branch -D`, `git worktree prune`)
handle the chore branch's squash-merge and cleanup **with zero additional code** — they were
written generically against "whatever worktree the session is currently in," not specifically
against the feature branch. This Change only needs to change how sub-step 6 **creates** the
branch; the merge and teardown paths it hands off to already do the right thing.

Branch-mode projects (including dev-platform itself) are entirely unaffected: `test -f
.claude/worktree-deps` is false, so sub-step 6 falls through to its existing `git checkout -b
chore/<slug>` behavior, unchanged.

This is a single-file, single-command-file fix — no new component, no architecture decision, no
Roadmap Phase. Per the dev-platform "Per-Spec-Phase branching decision rule"
(`/home/rich/dev/CLAUDE.md`), a fix this small uses a single `fix/` branch rather than a
`v<X.Y>/phase-1-*` Roadmap-Phase branch — same precedent as the `merge-delete-branch-worktree-fix`
spec this Change builds directly on top of.

## Language Decisions

N/A — this change edits Bash embedded in an existing Markdown slash-command file
(`commands/merge.md`). No new component is introduced; nothing to evaluate against the Language
Architecture Decision Matrix.

## Overview

1. Change 1 — Make Step 7 sub-step 6's chore-branch creation worktree-aware: worktree-opted-in
   projects get their own `.claude/worktrees/chore/<slug>` via `EnterWorktree` (mirroring
   `/code`'s pattern); branch-mode projects keep `git checkout -b` unchanged. Add `EnterWorktree`
   to `commands/merge.md`'s frontmatter `allowed-tools` (it currently lists only `Bash,
   ExitWorktree` — `ExitWorktree` was added for feature-branch teardown; `EnterWorktree` was never
   needed until now because sub-step 6 never created a worktree before).

---

## Phase 1: Post-merge chore branch worktree isolation

### Change 1: Make sub-step 6's branch creation worktree-aware

**Problem:** Sub-step 6 always cuts the `chore/<slug>` branch in the shared main checkout, even on
projects that isolate feature work into private worktrees specifically to prevent concurrent
sessions from contaminating each other's working tree — reopening the exact race worktree
isolation exists to close, for the one kind of commit `/merge` itself makes.

**File:** `commands/merge.md` (existing file, Step 7 sub-step 6, currently lines 170-174) + its
frontmatter (line 3).

**Implementation:**

First, add `EnterWorktree` to the frontmatter `allowed-tools` line (currently line 3):

```yaml
allowed-tools: Bash, ExitWorktree
```

becomes:

```yaml
allowed-tools: Bash, EnterWorktree, ExitWorktree
```

(Match `/code`'s and `/plan`'s existing ordering convention — `EnterWorktree` before
`ExitWorktree` — both list `EnterWorktree` and neither currently pairs it with `ExitWorktree`
since neither of them tears a worktree back down within the same command; `/merge` is the first
command file that legitimately needs both tools listed together.)

Second, replace sub-step 6's current bullet list (currently `commands/merge.md:170-174`):

```markdown
6. **Land any file changes from steps 4-5.** If the project's rules forbid direct commits to `main` (check its CLAUDE.md), run the SAME mini-cycle this skill already knows how to do — reuse Steps 1-5 above on a fresh branch:
   - Cut a branch (`chore/<slug>` per this project's naming convention), commit the doc/config changes, push.
   - Run the project's local gate (`./scripts/gate_fast.sh` or equivalent) before committing — same rule as any other commit. A docs-only diff should be fast; if the project's gate doesn't already skip its expensive legs (test suite, lint, typecheck) for a diff touching only docs/roadmap files, that's worth a separate follow-on, not a reason to skip the gate here.
   - Open the PR (`gh pr create`), then run Steps 2-5 of THIS skill against it: poll CI, verify green, squash-merge, sync local main. This is the one case `/merge` calls its own logic recursively — it's still gated by the same non-overridable CI-green check as any other merge.
   - If the project instead permits a direct-to-`main` trivial-edit path for pure doc/roadmap changes, use that instead — it's faster and the outcome is identical.
```

with:

```markdown
6. **Land any file changes from steps 4-5.** If the project's rules forbid direct commits to `main` (check its CLAUDE.md), run the SAME mini-cycle this skill already knows how to do — reuse Steps 1-5 above on a fresh branch:
   - **Cut the branch worktree-aware, same as feature work.** Check `test -f .claude/worktree-deps` from the current directory (by this point in Step 7 the session is always back in the project's main checkout — Step 5 already returned it there, whether the feature branch itself used branch mode or worktree mode):
     - **Worktree-opted-in** (`.claude/worktree-deps` present): don't `git checkout -b` in the shared main checkout — that's the exact contamination this Change exists to prevent. Instead, mirror `/code`'s worktree-mode branch creation: capture `MAIN=$(git rev-parse --show-toplevel)`, call the **`EnterWorktree`** tool with `name` set to `chore/<slug>`, then link the project's heavy git-ignored deps into it: `bash "${HOME}/.claude/worktree/link-deps.sh" "${MAIN}" "$(pwd)"`. The session is now re-rooted into `.claude/worktrees/chore/<slug>`.
     - **Branch mode** (no marker — dev-platform's own default, and every non-opted-in project): unchanged — `git checkout -b chore/<slug>`.
   - Commit the doc/config changes, push.
   - Run the project's local gate (`./scripts/gate_fast.sh` or equivalent) before committing — same rule as any other commit. A docs-only diff should be fast; if the project's gate doesn't already skip its expensive legs (test suite, lint, typecheck) for a diff touching only docs/roadmap files, that's worth a separate follow-on, not a reason to skip the gate here.
   - Open the PR (`gh pr create`), then run Steps 2-5 of THIS skill against it: poll CI, verify green, squash-merge, sync local main. This is the one case `/merge` calls its own logic recursively — it's still gated by the same non-overridable CI-green check as any other merge. **No further change is needed here**: Step 4 already re-derives `IN_WORKTREE` from the CURRENT session's toplevel path (not from any state carried over from the feature branch's own merge earlier in this same invocation), so it correctly detects the chore branch's worktree and takes the worktree-mode merge path (squash without `--delete-branch`, explicit `gh api -X DELETE` for the remote branch); Step 5 likewise already handles worktree-mode teardown generically (`ExitWorktree action: "keep"`, sync main, kill-by-cwd, `git worktree remove`, `git branch -D`, `git worktree prune`) for whatever worktree the session currently holds.
   - If the project instead permits a direct-to-`main` trivial-edit path for pure doc/roadmap changes, use that instead — it's faster and the outcome is identical. (This path never creates a branch at all, so the worktree-vs-branch-mode question doesn't apply to it.)
```

**Acceptance Test:**

Static verification (no live worktree-opted-in project needed to confirm the file is well-formed):

```bash
# Frontmatter lists EnterWorktree alongside the pre-existing ExitWorktree
grep -n '^allowed-tools: Bash, EnterWorktree, ExitWorktree$' commands/merge.md

# Sub-step 6 now branches on the worktree-deps marker before creating the chore branch
grep -n "test -f .claude/worktree-deps" commands/merge.md
grep -c "test -f .claude/worktree-deps" commands/merge.md   # 1 — only sub-step 6 needed this check

# The EnterWorktree call for the chore branch is present, with the chore/<slug> name
grep -n 'EnterWorktree.*chore/<slug>' commands/merge.md

# link-deps.sh is invoked for the chore worktree, matching /code's existing invocation shape
grep -n 'worktree/link-deps.sh' commands/merge.md
grep -c 'worktree/link-deps.sh' commands/merge.md   # 1 (only sub-step 6 needed it; /merge never created a worktree before this Change)

# Branch-mode fallback (dev-platform's own path) is still present and unchanged
grep -n 'git checkout -b chore/<slug>' commands/merge.md

# gate_fast.sh's frontmatter validator still passes (no new required field, just an
# allowed-tools value change — tests/commands/frontmatter.sh doesn't check tool-name content,
# only that the field is non-empty and the description under 200 chars)
bash tests/commands/frontmatter.sh
```

Live verification (per the original bug report — run once this ships and is installed):

```bash
./scripts/install.sh commands   # deploy the updated commands/merge.md to ~/.claude/
```

Then, from a worktree-opted-in project (PA, Keystone, SQRL, kermit-v3) with a real merge that
triggers sub-step 6 (a spec whose `planning.md`/`ROADMAP.md` updates need a `chore/` branch),
confirm:

1. The chore branch is created under `.claude/worktrees/chore/<slug>` in that project, NOT as a
   plain checked-out branch in the shared main checkout — `git worktree list` shows it as a
   worktree entry during the chore PR's lifetime.
2. No file that another concurrent session was mid-edit-on appears as unexpectedly dirty in `git
   status` run inside the chore worktree.
3. After the chore PR merges, the worktree and its branch are both gone (`git worktree list` no
   longer shows it; `git branch --list chore/<slug>` in the main checkout returns nothing) — the
   SAME teardown Step 5 already performs for feature branches, now exercised for a chore branch
   for the first time.

This live check happens in a consuming project's own session, not dev-platform's — dev-platform
itself runs in branch mode (`test -f .claude/worktree-deps` is false here), so this fix's
worktree-mode path can't be exercised live from within this repo. This mirrors the exact same
scoping note the prior `merge-delete-branch-worktree-fix-spec` Change carried for the identical
reason.

---

## What NOT to Do

- Don't change Step 4 or Step 5's existing worktree-mode logic (the `IN_WORKTREE` conditional
  merge call, `ExitWorktree action: "keep"`, kill-by-cwd loop, `git worktree remove`, `git branch
  -D`, `git worktree prune`) — it's already generic against "whatever worktree the session
  currently holds" and needs zero changes to correctly handle the chore branch once sub-step 6
  creates it via `EnterWorktree`. Re-deriving or duplicating that logic inside sub-step 6 would be
  the exact kind of drift-prone duplication `commands/merge.md`'s existing "reuse Steps 1-5" design
  already avoids.
- Don't change branch-mode behavior — `git checkout -b chore/<slug>` in the shared checkout is
  correct and safe for non-worktree-opted-in projects (including dev-platform itself); only
  worktree-opted-in projects need the isolation.
- Don't add a NEW opt-in marker or config knob for "isolate chore branches too" — reuse the
  existing `.claude/worktree-deps` marker exactly as `/code` and `/plan` do. A project that's
  opted into worktree isolation for feature work wants it for chore work too; a separate on/off
  switch would just be another way for the two to drift out of sync.
- Don't skip linking `.claude/worktree-deps` paths into the chore worktree "because it's just a
  docs/config change and doesn't need the app running" — `./scripts/gate_fast.sh` (run before
  committing, per sub-step 6's existing rule) may need those linked deps (e.g. `node_modules` for
  a lint step) to pass; skipping the link risks a false gate FAILURE in the chore worktree that
  wouldn't happen in the main checkout.
- Don't try to detect worktree-vs-branch mode from state carried over from the feature branch's
  own Step 4/5 run earlier in the same `/merge` invocation (e.g. reusing an old `IN_WORKTREE`
  variable) — Step 4 already re-derives it fresh from the CURRENT session's toplevel path each
  time it runs, which is exactly what makes the "run Steps 2-5 recursively" reuse trick work
  correctly for the chore branch without any Step 4/5 code change. Introducing a second detection
  mechanism would risk the two disagreeing.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `commands/merge.md` | Modify | Frontmatter: add `EnterWorktree` to `allowed-tools`. Step 7 sub-step 6: branch chore-branch creation on `.claude/worktree-deps` — worktree-opted-in projects use `EnterWorktree` + `link-deps.sh` (mirroring `/code`'s pattern), branch-mode projects keep `git checkout -b` unchanged. No change to Step 4/5's existing worktree-mode merge/teardown logic — it already handles the chore branch generically once sub-step 6 creates it as a worktree. |

## Implementation Order

1. Change 1 (only change) — edit `commands/merge.md` per the Implementation section above.

## Verification Checklist

- [ ] Frontmatter `allowed-tools` includes `EnterWorktree` alongside the pre-existing `Bash,
      ExitWorktree`.
- [ ] Sub-step 6 checks `test -f .claude/worktree-deps` before creating the chore branch.
- [ ] Worktree-opted-in arm: captures `MAIN`, calls `EnterWorktree` with `name: chore/<slug>`, then
      runs `link-deps.sh` — same three-step shape as `/code`'s existing worktree-mode branch
      creation (`commands/code.md`'s Step 2 worktree section).
- [ ] Branch-mode arm: `git checkout -b chore/<slug>` unchanged.
- [ ] No changes to Step 4's `IN_WORKTREE` detection block, its conditional merge call, or Step 5's
      teardown logic — confirmed by diffing only sub-step 6's bullet list and the frontmatter line.
- [ ] `bash tests/commands/frontmatter.sh` passes (frontmatter still well-formed after the
      `allowed-tools` edit).
- [ ] `./scripts/gate_fast.sh` passes (constitutional checks + command-frontmatter validator +
      existing suites — no new test suite needed for a single-command-file prose/bash edit, same
      class as the `merge-delete-branch-worktree-fix` Change this builds on).
- [ ] Manual re-read of the full edited sub-step 6 + frontmatter line for internal consistency
      (variable names `${MAIN}`, references to `chore/<slug>` match the surrounding prose's
      existing naming convention).
