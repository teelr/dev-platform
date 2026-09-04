# CI Integration Guide

How to plug your repo into dev-platform's taxonomy enforcement gate via GitHub Actions. Once integrated, every PR targeting `main` runs the dev-platform taxonomy check and the merge is blocked when the check fails.

## What this gives you

- **Taxonomy enforcement on every PR.** Roadmap Phase headers in your `ROADMAP.md` / `planning.md` must match `v<MAJOR>.<MINOR>: <Title>`; spec headers under `tasks/*-spec.md` can't use killed terms (`Sprint`, `Stage`, `Step`, `Task`, etc.). Violations fail the check.
- **Roadmap-version collision detection on every PR.** If two branches independently claim the same `v<MAJOR>.<MINOR>` Roadmap Phase number — the exact race that happens when two sessions run `/plan` around the same time in separate worktrees — the PR that would introduce the collision fails with the specific colliding version and both titles named. Degrades to a non-blocking warning (never a silent false pass, never a hard fail) if `gh`/network access isn't available to the runner.
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
  https://raw.githubusercontent.com/teelr/dev-platform/main/extensions/github-actions/dev-platform-gate.yml \
  -o .github/workflows/dev-platform-gate.yml
```

Fetching the *template* from `main` is deliberate — it hands you the file with dev-platform's current default pin already in it. (That is separate from the `uses:` pin inside the file, which must be a release tag; see the next step.) This example used to name a fixed tag, went stale at `v0.7`, and became the source of a wrong claim that every consumer was pinned there.

### 2. Pin to a dev-platform release tag

Open the file you just copied. The `uses:` line points at the release the template currently defaults to. Bump to the latest dev-platform release tag at adoption time:

```yaml
jobs:
  taxonomy:
    uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@v1.26   # bump as needed
```

**Staying on an old pin costs you checks, silently.** `check_version_collision.py` was added to the reusable workflow in v1.11 (fixed in v1.12 and v1.13). Any pin older than `@v1.11` runs `check_spec_taxonomy.sh` alone, so that repo has never had version-collision detection on a single PR, however long the guard has existed upstream. Verify yours rather than assuming — `git show <your-pin>:.github/workflows/taxonomy-check.yml` in a dev-platform checkout shows exactly which checks your tag runs.

Available tags: see [dev-platform releases](https://github.com/teelr/dev-platform/releases). **Do not use `@main`** — floating tags break reproducibility (a future dev-platform change could break your gate without you ever editing your repo).

### 3. (Optional) Make the check required for merge

In your repo's GitHub settings:

1. **Settings → Branches → Branch protection rules → Edit `main`** (or "Add rule" if you don't have one).
2. Enable **"Require status checks to pass before merging"**.
3. Add `dev-platform-gate / taxonomy` to the required checks list.
4. Save.

Now PRs with taxonomy violations can't merge until the violations are fixed.

If you can't access settings (e.g., not a repo admin), Step 3 is optional — the check still runs and reports its result on PRs even without being required. Admins can flip the "required" toggle later.

## Automated install (Rich's own projects)

If your project is in dev-platform's [project registry](../monitoring/projects.json), use the v0.8 fleet helper instead of the manual `curl`:

```bash
# From the dev-platform repo root
./scripts/fleet-install-template.sh --project <name>           # dry-run (default)
./scripts/fleet-install-template.sh --project <name> --apply   # write
./scripts/fleet-install-template.sh --project <name> --apply --pin v1.26
```

Functionally identical to the manual `curl` flow — same file, same target path. The helper just walks the registry so you don't repeat the project path each time. Per the v0.8 Scope-rule carve-out (see [CLAUDE.md](../CLAUDE.md) → "Exception — v0.8 fleet orchestration"), this is the ONLY write the fleet helper performs against your project; everything else in this guide stays manual.

If your project is NOT in dev-platform's registry, use the manual `curl` flow above. Adding a project to the registry is a one-line edit to [`monitoring/projects.json`](../monitoring/projects.json).

## Rollout

Commit the workflow file, push, and open a test PR (a typo fix is fine). Within ~30 seconds you should see:

- A check named `dev-platform-gate / taxonomy` appear under the PR's "Checks" tab.
- Either a green check (your taxonomy is clean) or a red X with the specific violating line in the workflow logs.

If red on adoption: read the failure output. The script prints the offending header line and links to the canonical taxonomy rule. Fix the headers per `v<MAJOR>.<MINOR>: <Title>` (Roadmap level) or `## Phase N: <Title>` / `### Change N: <Title>` (spec level). Push again; the check re-runs.

## Upgrading

When dev-platform cuts a new release (e.g., `v1.27`):

1. Edit `.github/workflows/dev-platform-gate.yml` in your repo.
2. Bump the tag in the `uses:` line to the new release.
3. Commit and push.

dev-platform cuts a tag at every Roadmap Phase completion as a standard post-merge step (v1.26), so there is a pinnable release per phase.

The release notes in dev-platform call out any changes to the taxonomy or check behavior — read them before bumping.

## Keeping the pin current

Doing the upgrade by hand every time is how pins go stale. Set it up once instead.

**Let Dependabot open the PR.** Copy the `github-actions` block from [`extensions/github-actions/dependabot-consumer-template.yml`](../extensions/github-actions/dependabot-consumer-template.yml) into your repo's `.github/dependabot.yml`. That one block is what bumps the `uses:` pin; the pip / npm / gomod blocks in the template are independent and optional. Dependabot then opens a bump PR whenever dev-platform publishes a release.

Of Rich's consumers, `kermit-pa`, `keystone` and `kermit-v3` have it. `kermit-harness`, `OPIE`, `SQRL` and `keystone_prototype` do not, and bump by hand (as of 2026-09-03).

**A Dependabot PR still needs merging.** It opens the PR; nothing merges it. A repo can sit stale with the bump already waiting.

**Dependabot can only move you to a tag that exists.** This is why every consumer stalled at `@v1.12`/`@v1.13` for twelve phases — tagging had stopped at v1.13, so there was nothing newer to bump to. Fixed in v1.26 by making the tag cut a mechanical post-merge step with `scripts/check-phase-tags.sh` as the backstop.

**Bumping by hand** is the one-line `uses:` edit above, committed on a branch with a PR — see `kermit-harness` PR #380 for the shape.

**Checking where you stand:** from a dev-platform checkout, `./scripts/fleet-pins.sh` reports every registered consumer's live pin, read from your repo's default branch, against the latest release. A row marked `⚠ local ≠ live` means the copy on that machine's disk is not the copy CI runs — almost always an uncommitted local edit to the workflow file. Trust the live column; that is the file GitHub Actions executes.

**Do not bump a pin with `fleet-install-template.sh --force`.** It rewrites the whole template file, and consumer copies have diverged from it. That helper is for first-time adoption. Bumping is a one-line edit in your own repo.

## Local pre-flight

To run the same check locally before pushing, clone dev-platform and point its script at your repo:

```bash
git clone https://github.com/teelr/dev-platform.git ~/dev-platform   # one-time
bash ~/dev-platform/scripts/check_spec_taxonomy.sh /path/to/your-repo
```

Exit 0 = clean. Exit 1 = at least one violation; the offending lines print to stderr.

## Non-default roadmap location

If your project's Roadmap Phase entries don't live at the repo-root
`ROADMAP.md` (e.g. Keystone's live at `docs/roadmap.md`), tell the checks where
the real file is. **The mechanism differs between CI and local runs**, and
conflating the two is what made earlier versions of this section unfollowable.

### In CI — the `roadmap_path` input

Pass it to the reusable workflow. **Requires `@v1.31` or newer.**

```yaml
jobs:
  taxonomy:
    uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@v1.31
    with:
      roadmap_path: docs/roadmap.md
```

Both jobs receive it — `check_spec_taxonomy.sh` and `check_version_collision.py`
are pointed at the same file, so they cannot disagree about which document is
your roadmap.

Two failure modes worth recognising, both probed against live GitHub:

- **`with: roadmap_path:` on a pin older than `@v1.31`** — the input doesn't
  exist there, so the call is rejected as a `startup_failure` before any check
  runs. Bump the pin and the input together.
- **`env: ROADMAP_PATH:` on the calling job** — *this does not work, and earlier
  versions of this page wrongly recommended it.* A job that calls a reusable
  workflow accepts only a restricted key set (`uses`, `with`, `secrets`,
  `permissions`, `needs`, `if`, `name`, `strategy`, `concurrency`); `env` is not
  among them, and caller-level `env` does not propagate into the called
  workflow. GitHub rejects the file at workflow-validation time — the run
  cannot even resolve its own `name:` and is reported by file path instead.
  Use `with:`.

### Locally — the `ROADMAP_PATH` env var

For `/plan`, `gate_fast.sh`, and `check-phase-tags.sh` run from your own shell,
export it:

```bash
export ROADMAP_PATH=docs/roadmap.md
```

`check_version_collision.py`, `check_spec_taxonomy.sh`,
`claim_roadmap_version.py` and `check-phase-tags.sh` all read it, falling back
to `ROADMAP.md` when unset or empty.

**Do not symlink a root `ROADMAP.md` to your real file as a substitute.**
`check_version_collision.py` and `claim_roadmap_version.py` both compare
against `origin/main`'s copy via `git show origin/main:<path>`, which does
NOT dereference symlinks — it returns the raw symlink target-path string as
the file's "content." This makes every real version look "new" and produces
false `COLLISION` failures against your own milestone history (confirmed
live on Keystone's first attempt, reverted the same night). Set
`ROADMAP_PATH` instead.

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
| `version-collision` check fails with "COLLISION" | Your branch's `ROADMAP.md` claims a `v<X.Y>` that `origin/main` or a live GitHub milestone already uses under a different title | Renumber to a free version (see the check's own output for the specific collision), or if you're intentionally updating an existing Phase's title, make sure `ROADMAP.md` and the milestone agree |
| `version-collision` check never appears at all — not even a red X, no run in the Actions tab | Missing `permissions:` block in your `dev-platform-gate.yml`. This is a cross-repo (often cross-org) reusable-workflow call — GitHub silently rejects it (`startup_failure`) unless the caller explicitly grants at least `contents: read` + `issues: read` | Add a top-level `permissions: { contents: read, issues: read }` block to your `dev-platform-gate.yml` (present in the template since 2026-08-12 — re-copy the template if yours predates that) |
| Check reports "no ROADMAP.md — nothing to check" but you DO have a roadmap doc | It's not at the repo-root `ROADMAP.md` path the checks default to | In CI, pass `with: roadmap_path:` (needs `@v1.31`+); locally, export `ROADMAP_PATH`. See "Non-default roadmap location" — do not symlink, and `env:` on the calling job does not work |
| Whole call fails as `startup_failure` right after adding `with: roadmap_path:` | Your pin predates the input | Bump the pin to `@v1.31` or newer in the same commit that adds the input |

## See also

- [Glossary](GLOSSARY.md) — definitions for "taxonomy", "Roadmap Phase", "Spec Phase", and every other project-specific term.
- [dev-platform CLAUDE.md > Development Terminology](../CLAUDE.md) — the canonical rule the check enforces.
- [check_spec_taxonomy.sh](../scripts/check_spec_taxonomy.sh) — the script that does the work.
