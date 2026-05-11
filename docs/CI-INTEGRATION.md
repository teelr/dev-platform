# CI Integration Guide

How to plug your repo into dev-platform's taxonomy enforcement gate via GitHub Actions. Once integrated, every PR targeting `main` runs the dev-platform taxonomy check and the merge is blocked when the check fails.

## What this gives you

- **Taxonomy enforcement on every PR.** Roadmap Phase headers in your `ROADMAP.md` / `planning.md` must match `v<MAJOR>.<MINOR>: <Title>`; spec headers under `tasks/*-spec.md` can't use killed terms (`Sprint`, `Stage`, `Step`, `Task`, etc.). Violations fail the check.
- **A green status check** that demonstrates your repo conforms to the dev-platform standard. Useful when teammates skim PR lists.
- **Zero vendored code.** The reusable workflow lives in `teelr/dev-platform`; your repo pins to a release tag. Upgrades are a one-line tag bump.

## Prerequisites

- A GitHub repository (public, or paid private — Actions minutes apply to private repos on free plans).
- A `tasks/` directory with `*-spec.md` files, OR a `ROADMAP.md`, OR a `planning.md` (the check scans whatever it finds; absent files are silently skipped).

## Adoption — 3 steps

### 1. Copy the consumer template

From `dev-platform/extensions/github-actions/dev-platform-gate.yml`, copy the file into your project at `.github/workflows/dev-platform-gate.yml`. You can do this with a single `curl`:

```bash
mkdir -p .github/workflows
curl -fsSL \
  https://raw.githubusercontent.com/teelr/dev-platform/v0.7/extensions/github-actions/dev-platform-gate.yml \
  -o .github/workflows/dev-platform-gate.yml
```

### 2. Pin to a dev-platform release tag

Open the file you just copied. The `uses:` line points at `@v0.7` — the dev-platform release the template was authored against. Bump to the latest dev-platform release tag at adoption time:

```yaml
jobs:
  taxonomy:
    uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@v0.7   # bump as needed
```

Available tags: see [dev-platform releases](https://github.com/teelr/dev-platform/releases). **Do not use `@main`** — floating tags break reproducibility (a future dev-platform change could break your gate without you ever editing your repo).

### 3. (Optional) Make the check required for merge

In your repo's GitHub settings:

1. **Settings → Branches → Branch protection rules → Edit `main`** (or "Add rule" if you don't have one).
2. Enable **"Require status checks to pass before merging"**.
3. Add `dev-platform-gate / taxonomy` to the required checks list.
4. Save.

Now PRs with taxonomy violations can't merge until the violations are fixed.

If you can't access settings (e.g., not a repo admin), Step 3 is optional — the check still runs and reports its result on PRs even without being required. Admins can flip the "required" toggle later.

## Rollout

Commit the workflow file, push, and open a test PR (a typo fix is fine). Within ~30 seconds you should see:

- A check named `dev-platform-gate / taxonomy` appear under the PR's "Checks" tab.
- Either a green check (your taxonomy is clean) or a red X with the specific violating line in the workflow logs.

If red on adoption: read the failure output. The script prints the offending header line and links to the canonical taxonomy rule. Fix the headers per `v<MAJOR>.<MINOR>: <Title>` (Roadmap level) or `## Phase N: <Title>` / `### Change N: <Title>` (spec level). Push again; the check re-runs.

## Upgrading

When dev-platform cuts a new release (e.g., `v0.8`):

1. Edit `.github/workflows/dev-platform-gate.yml` in your repo.
2. Bump `@v0.7` → `@v0.8`.
3. Commit and push.

The release notes in dev-platform call out any changes to the taxonomy or check behavior — read them before bumping.

## Local pre-flight

To run the same check locally before pushing, clone dev-platform and point its script at your repo:

```bash
git clone https://github.com/teelr/dev-platform.git ~/dev-platform   # one-time
bash ~/dev-platform/scripts/check_spec_taxonomy.sh /path/to/your-repo
```

Exit 0 = clean. Exit 1 = at least one violation; the offending lines print to stderr.

## Disabling

Temporarily: comment out the `on:` triggers in `.github/workflows/dev-platform-gate.yml`, or change `branches: [main]` to a branch that doesn't exist. The workflow file stays in the repo but never runs.

Permanently: delete the file. If the check was a required status check in branch protection, also remove it from the required list (otherwise PRs can never merge — the required check expects a workflow that no longer exists).

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| Workflow doesn't appear on PRs | `on.pull_request.branches` doesn't include your default branch | Edit the workflow's `on:` block to match your default branch name |
| `taxonomy-check.yml` not found error | The pinned tag doesn't exist in dev-platform | Check [available tags](https://github.com/teelr/dev-platform/tags) and bump your `@vX.Y` to one that exists |
| Check fails on a header that looks correct | The check requires exact format — leading hyphen + double-asterisks for list-form, two `#` for heading-form | Compare to a passing dev-platform `ROADMAP.md` entry |
| Required check stuck in "Expected" state | Workflow ran on a prior commit but not the latest PR commit | Push an empty commit (`git commit --allow-empty -m "trigger CI"`) to re-trigger |

## See also

- [Glossary](GLOSSARY.md) — definitions for "taxonomy", "Roadmap Phase", "Spec Phase", etc. (lands in v0.7 Phase 3).
- [dev-platform CLAUDE.md > Development Terminology](../CLAUDE.md) — the canonical rule the check enforces.
- [check_spec_taxonomy.sh](../scripts/check_spec_taxonomy.sh) — the script that does the work.
