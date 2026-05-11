---
description: Open a pull request against main for the current branch. Auto-derives title, milestone, and body shape from branch name + commit messages. Refuses if branch isn't pushed or already has a PR.
allowed-tools: Bash
---

# PR Open Agent

You are a PR-opening agent. Your job is to **open a pull request against `main`** for the current feature branch with a consistent title, milestone, and body shape — replacing the ad-hoc `gh pr create` calls that used to drift in tone and content from PR to PR.

The argument (if provided) is treated as an extra context/notes line that gets appended to the PR body's Summary section. Most invocations need no argument.

## Step 1: Verify branch state

Run these in parallel:

```bash
git branch --show-current     # current branch name
git status --porcelain        # uncommitted changes
git log --oneline -10         # recent commit messages on this branch
git log main..HEAD --stat     # diff vs main
```

If the current branch is `main`: STOP and error — PRs are opened from feature branches.

If there are uncommitted changes: STOP and ask the user to commit-or-stash first. (Per the workflow rule: the bundled feat commit lands before `push` and `pr`.)

If `git log main..HEAD --oneline` is empty: STOP — nothing to open a PR for (branch has no commits ahead of main).

If the branch is not pushed to origin: push it via `git push -u origin <branch>` BEFORE opening the PR. The PR needs the remote to exist.

## Step 2: Derive title

Branch name follows the per-Spec-Phase convention: `v<MAJOR>.<MINOR>/phase-<N>-<short-slug>` or `chore/<short-slug>` or `v<MAJOR>.<MINOR>b/...`.

Title patterns:

- `v0.7/phase-3-pages-glossary` → "v0.7 Phase 3 — Pages docs site + Glossary"
- `v0.8/phase-1-registry-fleet-gate` → "v0.8 Phase 1 — Registry + Fleet Gate"
- `chore/workflow-step-extension` → "chore: workflow doc extended to PR → CI → merge → post-merge"
- `chore/pr-merge-slash-commands` → "chore: /pr and /merge slash commands"

Derivation rules (best source first):

1. **Prefer the spec's Phase title.** If a spec file is in the diff (`git diff main..HEAD --name-only | grep tasks/.*-spec.md`), read it and look for the `## Phase <N>: <Phase Title>` heading matching the branch's `phase-<N>-` slug. Use the spec's Phase Title verbatim — it's hand-crafted and reads better than any auto-derivation. Example: spec says `## Phase 1: Registry + Fleet Gate` → branch `v0.8/phase-1-registry-fleet-gate` → title `"v0.8 Phase 1 — Registry + Fleet Gate"`.
2. **Fall back to slug-derived title.** If no spec exists OR the slug doesn't match any Phase heading: convert the slug to a title by replacing hyphens with spaces and Title-Casing each word. Example: `v0.8/phase-1-registry-fleet-gate` (without spec) → `"v0.8 Phase 1 — Registry Fleet Gate"` (no `+`; that's a spec-author choice, not a derivable one).
3. **chore branches**: `chore/<slug>` → `"chore: <slug-with-hyphens-as-spaces>"`. Example: `chore/pr-merge-slash-commands` → `"chore: pr merge slash commands"`.
4. **Anything else**: fall back to the most recent commit's subject line.

If the derived title is unsatisfying, ASK the user to confirm before opening — don't ship a confusing title.

## Step 3: Auto-detect milestone

Branches under `v<X.Y>/...` map to the milestone `v<X.Y>: <Title>`. Compute the prefix from the branch name (e.g. branch `v0.8/phase-1-...` → prefix `v0.8:`), then query the live milestones:

```bash
PREFIX="v0.8:"   # derived from branch name; substitute actual major.minor
gh api repos/teelr/dev-platform/milestones?state=open \
    --jq ".[] | select(.title | startswith(\"${PREFIX}\")) | .title"
```

Use whatever GitHub returns as the canonical title. Do NOT pass the literal `<X.Y>` placeholder to jq — substitute the actual major.minor from the branch first.

Branches under `chore/...` get whichever current-Roadmap-Phase milestone is open (the chore is part of the active body of work). For multiple open phases (rare), default to the most recent one and ASK before assigning.

If no matching milestone exists, open the PR without a milestone and warn the user. (The user can attach one in the GitHub UI.)

## Step 4: Compose body

Use this template:

```markdown
## Summary

{1-3 bullets derived from the commit messages on this branch — use `git log main..HEAD --format='%s'` and pick the most descriptive lines}

{optional argument from the user appended here as an extra line/paragraph}

## Test plan

- [x] `./scripts/gate_fast.sh` → {run it FRESH right now: `./scripts/gate_fast.sh 2>&1 | tail -3` and quote the result line, e.g. "90 PASS / 0 FAIL / 0 SKIP (21s)". Do NOT trust conversation memory — re-run.}
- [x] {any spec-specific test commands the agent ran during /test — derive from the diff if obvious}
- [ ] **CI: `gate-fast` workflow runs on this PR ref and goes green**
- [ ] **Post-merge: {derived from the spec's "Post-merge step" section if a spec file is in the diff; otherwise "no post-merge step"}**

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Keep the body terse — under 40 lines for typical Phase PRs. The Summary's bullets should be the diff's actual deliverables, not generic prose. The Test plan's items should be the actual commands the agent ran during /test (not speculative future tests).

## Step 5: Open the PR

Run:

```bash
gh pr create --title "<derived title>" --milestone "<derived milestone>" --body "$(cat <<'EOF'
{body from Step 4}
EOF
)"
```

Use a HEREDOC for the body to preserve markdown formatting.

If `gh pr create` errors (e.g., milestone doesn't exist, branch protection rejects), report the error verbatim and STOP. Don't retry blindly.

## Step 6: Report + STOP

Print the PR URL returned by `gh pr create`. Tell the user the next step is `CI` (wait for green) → `merge` (or invoke `/merge`).

**DO NOT** auto-trigger `/merge` or any CI monitoring. The user explicitly invokes the next step per the Workflow Step Discipline rule in `settings/claude-global.md`.

## Rules

- **One PR per feature branch.** If a PR already exists for this branch (`gh pr view` returns one), STOP and report — don't open a duplicate.
- **Don't push uncommitted changes.** The workflow chain is `commit → push → PR`; uncommitted state means the user skipped a step.
- **Don't auto-derive a milestone if the branch's `v<X.Y>` doesn't match any open milestone.** Warn and proceed without one, OR ask the user.
- **The Test plan checklist boxes that the agent KNOWS passed (e.g., `/gate fast` from the most recent run) get pre-checked.** Items still pending (CI run, post-merge) stay unchecked. Don't pre-check things you didn't verify.
- **NEVER amend an existing PR's body via this command.** That's a different workflow (`gh pr edit`). `/pr` only OPENS new PRs.
- **NEVER include `--label` or `--reviewer` arguments by default.** Per dev-platform's solo-merge convention, PRs don't require approvals or labels. If a future team-scale spec adds those, this command updates.
