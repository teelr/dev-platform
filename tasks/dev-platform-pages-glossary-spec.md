# v0.7 Phase 3 — GitHub Pages Docs Site + Glossary

## Coding Specification for Implementation

## Design Philosophy

v0.7 Phase 3 publishes `dev-platform/docs/` as a hosted site at `teelr.github.io/dev-platform/` and lands a `docs/GLOSSARY.md` covering every project-specific term in active use across this repo. The motivation isn't aesthetics — it's vocabulary parity. Phase 1's [taxonomy enforcement](dev-platform-team-enablement-spec.md#phase-1-taxonomy-enforcement-at-the-roadmap-level) and Phase 2's [CI-INTEGRATION guide](../docs/CI-INTEGRATION.md) both expose dev-platform's insider vocabulary (`gate fast`, `Roadmap Phase`, `Spec Phase`, `Change`, `ship`, `cut`, `live cutover`, `workflow_sha`, `Consumer Audit`, `lift checks`) to anyone reading PRs or docs. Without a glossary, a teammate reading `docs/CI-INTEGRATION.md` for the first time has to context-derive ~15 terms; with one, they have a linkable definition per term. The recurring pain captured 2026-05-11 ("use consistent terminology for a newbie here") is exactly what this Phase fixes.

The implementation is intentionally thin — GitHub Pages renders any Markdown tree with a Jekyll `_config.yml` plus a one-shot workflow that calls `actions/jekyll-build-pages@v1`. No JavaScript, no theme customization beyond the default Cayman, no Pages-side build scripts. The `docs/CI-INTEGRATION.md` from Phase 2 already references `GLOSSARY.md` with a `(lands in v0.7 Phase 3)` hedge — Phase 3 makes that link resolve and removes the hedge.

Scope discipline: per the Scope rule (`dev/CLAUDE.md`), Phase 3 touches only files in `dev-platform/` itself — no project edits. Per the Honesty rule, the GLOSSARY lists ONLY terms genuinely in use today; speculative future vocab stays out. Per the per-Spec-Phase strategy (codified in PR #9), this Phase ships as one PR (~250 LOC across 4–5 files, under the per-Spec-Phase "single branch" threshold). Per the Consumer Audit rule (`dev/CLAUDE.md`), `docs/_config.yml` is the first non-`.md` file under `docs/` — the `.gitignore` allow-list needs `!docs/*.yml` extended before this PR can ship. Per the workflow extension locked in PR #9, the spec explicitly names a `post-merge` step for the one-time `gh api` Pages-enable call.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `docs/GLOSSARY.md` | Markdown | Documentation content, alphabetical glossary entries. |
| `docs/index.md` | Markdown | Pages landing page. Thin entry-point linking to canonical docs at the repo root. |
| `docs/_config.yml` | YAML | Jekyll configuration. The only format GitHub Pages reads for site-level settings. |
| `.github/workflows/pages.yml` | YAML | GitHub Actions workflow. Mirrors the `gate.yml` pattern shipped in Phase 2. |

No new code components — Phase 3 is content + deploy plumbing. No Language Architecture Decision Matrix violation; YAML/Markdown are the correct (and only sensible) choice for each artifact.

## Overview

1. **Phase 1:** Site content + deploy (Changes 1–5)

Single-Phase Spec — see "small Roadmap Phase" carve-out from v0.6 lessons (`tasks/lessons.md`, 2026-05-11): when total LOC ≤ ~250 and Spec Phases would only artificially split the work, ship as one Phase with all Changes in one PR.

---

## Phase 1: Pages Site

### Change 1: `docs/GLOSSARY.md` — terminology reference

**Problem:** Every dev-platform doc and PR uses insider vocabulary (`gate`, `Roadmap Phase`, `Spec Phase`, `Change`, `cut`, `ship`, `the gate`, `workflow_sha`, etc.). New contributors and Rich's future self can't read PRs without context-deriving these terms. Captured 2026-05-11 as recurring user pain.

**File:** `docs/GLOSSARY.md` (new, ~150 lines — 28+ terms with tight 1-3 sentence definitions per the "GET TO THE POINT" rule in `dev/CLAUDE.md`; a verbose treatment would push 250+ but adds words for words' sake)

**Implementation:**

Markdown file, alphabetized by term (case-insensitive sort). One `### Term` heading per entry, 1–3 sentence definition, link to authoritative source when relevant. Each definition cross-links other glossary terms (Markdown anchor links like `[Gate fast](#gate-fast)`).

Required entries (28 — every one verified to appear in `*.md` content across the repo via `grep -r` 2026-05-11):

- **Auto-discovery** — the contract `scripts/gate_fast.sh` enforces: it walks `tests/*/` and runs every `*.sh` runner under each subdir, no orchestrator edit needed when adding a new suite.
- **Change** — atomic implementation step inside a Spec (`### Change N: <title>`). Numbered continuously across the whole Spec. One Change = one commit when implemented. See `dev/CLAUDE.md > Development Terminology`.
- **CI green / CI red** — the result of the `gate-fast` workflow on a PR. Green = pass, red = fail. "No merge before CI green" is canonical per PR #9.
- **Commit** — git record bundling feature code + doc updates per the Docs-Before-Commit rule. `dev/CLAUDE.md`.
- **Consumer Audit** — 5-point checklist run when introducing a new file type in a glob-managed directory (`.gitignore`, install scripts, verify scripts, directory README, test orchestrators). Promoted to `dev/CLAUDE.md` as PR #5.
- **Cut release** — tag a GitHub Release (`v0.6`, etc.) at the merge commit closing a Roadmap Phase. Done via `gh release create`.
- **Deploy / Live cutover** — running `scripts/install.sh` to symlink tracked files from the repo into `~/.claude/`. "Live cutover" is the first deploy of a new artifact onto Rich's machine, where the tracked file becomes the source of truth.
- **Drift** — divergence between the tracked file in this repo and its deployed copy under `~/.claude/`. Detected by `scripts/verify.sh`; the **Gate fast** lift check blocks commits when drift exists locally.
- **Gate** — shorthand for "the constitutional check that must pass before something advances." Three tiers exist for dev-platform; see `Gate fast / full / release`. Other projects (kermit, kermit-pa) have their own gates with the same three-tier shape per `dev/CLAUDE.md`.
- **Gate fast** — the inner-loop gate run before every commit (`./scripts/gate_fast.sh` in dev-platform). Constitutional checks + unit tests + smoke-fast. ~5–20s. The MUST-pass gate before commit, and the only gate currently wired into CI as of PR #8.
- **Gate full** — the outer-loop gate run after structural changes. Adds load-tier smokes for projects that have them. ~10–35 min.
- **Gate release** — the pre-release gate. Adds full load tests. ~3+ hours. Only run before tagging a release.
- **GitHub Milestone** — repo-level container 1:1 with a Roadmap Phase. Title matches the Phase header (`v0.7: Team Enablement`). Closed when the Phase ships.
- **In flight** — a Spec Phase that's implemented on a feature branch but not yet merged. Tracked in `planning.md`'s "In flight" section.
- **Land** — synonym for merge: a commit that has been squash-merged into `main`. "PR #8 landed at `a551d95`."
- **Lift checks** — the five top-of-gate checks in `scripts/gate_fast.sh`: spec taxonomy, bash syntax, JSON validity, secrets scan, live `~/.claude/` verify. Run before the per-suite test runners.
- **Mock binary** — testability pattern: an extension-less executable script under `tests/<suite>/fixtures/mock-bin/` that mimics an external CLI (e.g., `code`, `gh`) via an env-var state file. Lets round-trip tests run without touching live state. Pattern landed in v0.6.
- **Per-Spec-Phase strategy** — branching convention adopted v0.5+: each Spec Phase → one feature branch (`v0.7/phase-2-github-actions` etc.) → one PR assigned to the Roadmap Phase's Milestone → squash-merge to `main`. Small Spec Phases can ship as a single combined PR per the v0.6 carve-out.
- **Post-merge** — the workflow step running deferred actions a Spec called out (branch-protection updates that require the workflow to exist on `main` first; release-tag cuts; one-time `gh api` setup calls). The Spec lists what's deferred; `post-merge` runs those. No-op if the Spec defers nothing. Locked in PR #9.
- **PR (Pull Request)** — GitHub primitive that bundles a feature branch into a merge proposal against `main`. Opened with `gh pr create`. The PR boundary is where CI runs.
- **Reusable workflow** — a GitHub Actions workflow with a `workflow_call:` trigger that other workflows invoke via `uses:`. Used by consumer projects to call dev-platform's `taxonomy-check.yml` without vendoring the script. See `.github/workflows/taxonomy-check.yml`.
- **Roadmap Phase** — major product milestone (`v0.5: Monitoring`). Format `v<MAJOR>.<MINOR>[<letter>]: <Title>`, enforced by `scripts/check_spec_taxonomy.sh`. Each maps 1:1 to a GitHub Milestone.
- **Seed** — populate something with initial data — e.g., "seed GitHub Milestones from `ROADMAP.md`" means create one Milestone per Roadmap Phase entry. Phase 4's `sync-milestones.sh` is the canonical seeder.
- **Sentinel** — a fixed string or value used in test fixtures to prove an operation didn't run (e.g., `tests/scaffold/run.sh` writes a sentinel into a file then asserts the install-refuse-to-clobber path preserved it).
- **Ship** — verb for "shipped a Spec Phase": the per-Spec-Phase PR is merged AND any post-merge tasks ran. Distinct from "merged" (commit landed but post-merge may still be pending). "v0.7 Phase 1 shipped 2026-05-11."
- **Spec** — `tasks/{name}-spec.md` file produced by `/plan`. Implementation specification a separate `/code` agent can execute without additional context.
- **Spec Phase** — group of related Changes inside one Spec (`## Phase N: <title>`). Distinct from Roadmap Phase. Bare "Phase" in dev context = Spec Phase.
- **Squash merge** — merge strategy where all PR commits are squashed into one commit on `main`. The dev-platform default. Tools: `gh pr merge <N> --squash --delete-branch`.
- **Symlink deploy** — `scripts/install.sh`'s deploy mechanism: every tracked file in `commands/`, `hooks/`, `settings/`, `skills/` is symlinked into the corresponding `~/.claude/` location. The tracked file in the repo is the source of truth; `~/.claude/` is the deployment.
- **The gate** — informal for **Gate fast**. "Did the gate pass?" always means gate-fast unless qualified.
- **Tracked file** — a file in this repo (committed to `git`). Opposite of `deployed copy` under `~/.claude/`. The tracked file is the source of truth; `verify.sh` flags drift.
- **`v<MAJOR>.<MINOR>: <Title>`** — Roadmap Phase header format (e.g. `v0.5: Monitoring`). Enforced by `scripts/check_spec_taxonomy.sh` against `ROADMAP.md` and `planning.md`. See `dev/CLAUDE.md > Development Terminology`.
- **Wired-in** — a feature is "wired in" when its full data path (UI → API → backend → storage → response) exists end-to-end. Per `dev/CLAUDE.md > Data Lifecycle & Wiring Rules`: every new feature must be traceable end-to-end before being marked done.
- **`workflow_call` / `workflow_sha`** — GitHub Actions context primitives. `workflow_call` is a reusable-workflow trigger; `workflow_sha` is the commit SHA of the running workflow. Used in `.github/workflows/taxonomy-check.yml` to check out dev-platform at the consumer's pinned ref. See lessons.md 2026-05-11.

Each entry: bold term in `### Heading` form (so the spec-taxonomy script's `### Change N` rule isn't confused — these aren't Phase-child Changes, they're glossary entries). The `## Phase N` killed-term check from the existing taxonomy script does NOT trigger on `### Term` headings under non-Phase parents, so the glossary file passes the gate cleanly.

**Acceptance Test:**

```bash
test -f docs/GLOSSARY.md
wc -l docs/GLOSSARY.md     # expect 100+ lines (tight 1-3 sentences/entry × 28+ entries)
grep -c '^### ' docs/GLOSSARY.md   # expect 28+

# Every term I documented as in-use IS in the glossary
for term in "Gate fast" "Roadmap Phase" "Consumer Audit" "Spec Phase" "Symlink deploy" "workflow_sha" "Post-merge"; do
    grep -q "^### .*${term}" docs/GLOSSARY.md && echo "OK ${term}" || echo "MISSING ${term}"
done

# Taxonomy check still passes (glossary entries are ### but not under ## Phase N)
./scripts/check_spec_taxonomy.sh && echo "OK taxonomy clean"
```

### Change 2: `docs/_config.yml` — Jekyll configuration

**Problem:** GitHub Pages renders Markdown using Jekyll. Without `_config.yml`, Pages uses bare defaults — no theme, no relative-link plugin, no site title. The `_config.yml` lives at the root of whatever directory Pages renders; in our case `docs/`.

**File:** `docs/_config.yml` (new) + `.gitignore` (modify)

**Implementation:**

```yaml
# Jekyll config for GitHub Pages render of dev-platform/docs/.
# Minimal — default Cayman theme + relative-links plugin so the
# inter-doc links resolve correctly when rendered.
title: dev-platform
description: Source of truth for Rich's developer environment.
theme: jekyll-theme-cayman
markdown: kramdown
plugins:
  - jekyll-relative-links
relative_links:
  enabled: true
  collections: false
include:
  - CONTRIBUTING.md
```

**Consumer Audit (mandatory):** `docs/_config.yml` is the first non-`.md` file under `docs/`. The existing `.gitignore` line `!docs/*.md` allows only Markdown. Without a new allow-list line, `_config.yml` is silently gitignored. Extend `.gitignore`:

```text
!docs/*.md
!docs/*.yml      # v0.7 Phase 3: Jekyll config for GitHub Pages
```

Run `git check-ignore -v docs/_config.yml` after editing — expect the output to name `!docs/*.yml` as the matching re-include rule.

**Acceptance Test:**

```bash
test -f docs/_config.yml
python3 -c "import yaml; d = yaml.safe_load(open('docs/_config.yml')); assert d['theme'] == 'jekyll-theme-cayman'; print('YAML OK')"

# Consumer Audit
git check-ignore -v docs/_config.yml 2>&1 | grep -q '!docs/\*\.yml' && echo "OK gitignore re-include"
```

### Change 3: `.github/workflows/pages.yml` — Pages deploy workflow

**Problem:** GitHub Pages can deploy from a branch (auto-built by Jekyll) OR from a workflow artifact (manually built and uploaded). Workflow mode is cleaner for our use case — no surprise rebuilds, deploy triggers only when `docs/` actually changes, build steps are explicit and inspectable.

**File:** `.github/workflows/pages.yml` (new)

**Implementation:**

```yaml
name: deploy-pages

on:
  push:
    branches: [main]
    paths:
      - 'docs/**'
      - '.github/workflows/pages.yml'
  # Manual trigger so a re-deploy can run without a docs commit
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

# Single deploy at a time; cancel any in-progress run if a newer
# commit lands while it's running.
concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/configure-pages@v4
      - name: Build Jekyll site
        uses: actions/jekyll-build-pages@v1
        with:
          source: docs
          destination: ./_site
      - uses: actions/upload-pages-artifact@v3
        with:
          path: ./_site
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

Key design notes:

- `on.push.paths` scopes deploys to actual `docs/` changes — no wasted runs for code-only commits.
- `workflow_dispatch` lets a re-deploy run from the Actions UI without a doc commit (useful when fixing the Pages site config, for example).
- `permissions` grants exactly what `deploy-pages` needs and nothing more — no `write-all`.
- `concurrency.cancel-in-progress: false` means a newer commit's deploy QUEUES rather than KILLS the in-progress one — important for sites where a half-deployed site is worse than a slightly-stale one.

**Consumer Audit:** `.github/workflows/pages.yml` matches the existing `!.github/**/*.yml` re-include from Phase 2. No `.gitignore` extension needed; verify with `git check-ignore -v`.

**Acceptance Test:**

```bash
test -f .github/workflows/pages.yml
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/pages.yml')); print('YAML OK')"

# Triggers + permissions look right
python3 -c "
import yaml
d = yaml.safe_load(open('.github/workflows/pages.yml'))
on_block = d.get(True) or d.get('on')
assert 'push' in on_block and 'workflow_dispatch' in on_block
assert d['permissions']['pages'] == 'write'
print('OK structure')
"

# Consumer Audit: tracked
git check-ignore -v .github/workflows/pages.yml 2>&1 | grep -q '!.github/\*\*/\*\.yml' && echo "OK gitignore"
```

### Change 4: `docs/index.md` — Pages landing page

**Problem:** GitHub Pages defaults to rendering `index.md` (or `README.md`) at the site root. The repo's `README.md` is what GitHub displays in the repo view; duplicating it under `docs/` would create two sources of truth. A thin `docs/index.md` that links to the root `README.md` and key docs is the cleaner pattern.

**File:** `docs/index.md` (new, ~20-40 lines — thin link list, no prose padding)

**Implementation:**

```markdown
# dev-platform

Source of truth for Rich's developer environment: rules, slash commands, skills, hooks, settings, install scripts, telemetry, VSCode extensions, GitHub Actions CI.

## Documentation

- **[README](../README.md)** — what this repo is, quick start, repo structure
- **[ROADMAP](../ROADMAP.md)** — Roadmap Phases v0.1 → v1.0
- **[CLAUDE.md](../CLAUDE.md)** — full development standards (workflow, taxonomy, language matrix, port registry, project structure)
- **[Glossary](GLOSSARY.md)** — every project-specific term defined
- **[CI Integration](CI-INTEGRATION.md)** — how to plug your repo into dev-platform's taxonomy gate
- **[New Project](NEW-PROJECT.md)** — conversational Q&A for scaffolding new projects
- **[Project CLAUDE.md template](PROJECT_CLAUDE_TEMPLATE.md)** — what every project's CLAUDE.md should contain

## Latest release

See [Releases](https://github.com/teelr/dev-platform/releases). v0.6 (VSCode Coverage Server-Side) is the most recent tag.

## Workflow

`/plan → /code → /test → /review → /gate fast → /docs → commit → push → PR → CI → merge → post-merge`

Each step is mechanical and reproducible. See [CLAUDE.md](../CLAUDE.md) for the full discipline.
```

The relative-links plugin from `_config.yml` resolves `../README.md` etc. — without it, the links would 404 on the Pages site.

**Acceptance Test:**

```bash
test -f docs/index.md
grep -q "GLOSSARY.md" docs/index.md
grep -q "CI-INTEGRATION.md" docs/index.md
grep -q "PR → CI → merge → post-merge" docs/index.md   # new workflow chain
```

### Change 5: Remove the "(lands in v0.7 Phase 3)" hedge from `docs/CI-INTEGRATION.md`

**Problem:** Phase 2's [docs/CI-INTEGRATION.md:101](../docs/CI-INTEGRATION.md#L101) currently reads:

```markdown
- [Glossary](GLOSSARY.md) — definitions for "taxonomy", "Roadmap Phase", "Spec Phase", etc. (lands in v0.7 Phase 3).
```

The hedge was correct when Phase 2 shipped (GLOSSARY didn't exist yet). After Phase 3 ships GLOSSARY, the hedge is stale and the link to a now-real file should stand without the qualifier.

**File:** `docs/CI-INTEGRATION.md` (modify, line ~101)

**Implementation:**

```diff
-- [Glossary](GLOSSARY.md) — definitions for "taxonomy", "Roadmap Phase", "Spec Phase", etc. (lands in v0.7 Phase 3).
+- [Glossary](GLOSSARY.md) — definitions for "taxonomy", "Roadmap Phase", "Spec Phase", and every other project-specific term.
```

**Acceptance Test:**

```bash
! grep -q "lands in v0.7 Phase 3" docs/CI-INTEGRATION.md && echo "OK hedge removed"
grep -q "every other project-specific term" docs/CI-INTEGRATION.md && echo "OK new copy"
```

---

## Post-merge step (deferred, in spec — runs after PR squash-merges)

**One-time GitHub Pages enable.** GitHub Pages must be turned on for the repo before any deploy workflow can publish. As of spec authoring, Pages is NOT yet enabled (verified via `gh api repos/teelr/dev-platform/pages` → 404). The first `pages.yml` workflow run will FAIL until this one-shot setup runs.

```bash
# Set Pages source to GitHub Actions (so our pages.yml is the build).
# This call is idempotent — re-running has no effect once Pages is enabled.
gh api -X POST repos/teelr/dev-platform/pages -f build_type=workflow
```

Verification:

```bash
gh api repos/teelr/dev-platform/pages --jq '.build_type'
# Expect: "workflow"
```

After this call, the next `docs/**` commit (or `workflow_dispatch`) deploys the site to `https://teelr.github.io/dev-platform/`.

Pattern mirrors Phase 2's Change 6 — a `gh api` call that requires the workflow to exist on `main` first. Phase 2 documented Change 6 explicitly in its post-merge section; Phase 3 does the same for Pages-enable.

---

## What NOT to Do

- **Do NOT enable Pages from "branch" mode** (the older Jekyll-from-branch option). The workflow-mode + explicit `actions/jekyll-build-pages@v1` is more reproducible and matches the rest of the CI in `.github/workflows/`.
- **Do NOT add `_config.yml` at the repo root** — Pages would try to render the entire repo (including `tasks/`, `scaffolding/`, etc.) which is content not meant for the public site. `docs/_config.yml` scopes Jekyll to `docs/` only via the `pages.yml` `source: docs` line.
- **Do NOT duplicate `README.md` into `docs/`.** The repo `README.md` is the canonical Quick Start; `docs/index.md` is a thin landing page that links to it via the relative-links plugin.
- **Do NOT add `jekyll-relative-links` to `gemfile`-style dependency manifests.** Pages auto-installs the plugin when `_config.yml` declares it. No separate manifest needed.
- **Do NOT use a custom theme.** Cayman is the default and renders cleanly without theme-asset wrangling.
- **Do NOT add JavaScript or client-side interactivity.** This is a static doc site, not an app.
- **Do NOT modify `dev/CLAUDE.md`.** It already documents the canonical taxonomy and workflow. GLOSSARY is a *reference* of those terms, not a *re-definition*.
- **Do NOT skip Consumer Audit on `docs/_config.yml`.** The `.gitignore` extension `!docs/*.yml` is mandatory — without it, the file is silently gitignored and Pages fails to build with no obvious error.
- **Do NOT split the spec into Phase 1 (content) + Phase 2 (deploy) Spec Phases.** Total LOC is ~250; per the v0.6 small-Roadmap-Phase carve-out, a single-Phase Spec is appropriate. Per-Spec-Phase strategy applies when Phases exceed ~150 LOC each.
- **Do NOT add the GLOSSARY to the gate's taxonomy check as an enforcement target.** The taxonomy check enforces `## Phase N` / `### Change N` headers in *spec* and *roadmap* files — the GLOSSARY uses `### Term:` headings (no Phase/Change semantics), so it's outside the enforcement scope and would generate false-positive churn if accidentally swept in.
- **Do NOT use `@latest` for any GitHub Actions in `pages.yml`.** Pin to `@v4` for major-pinned official actions, per the rule locked in PR #8.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `docs/GLOSSARY.md` | New | Alphabetized definitions for 28 dev-platform terms in active use |
| `docs/_config.yml` | New | Jekyll config (Cayman theme, relative-links plugin, site metadata) |
| `docs/index.md` | New | Pages landing page (links to root README + key docs) |
| `.github/workflows/pages.yml` | New | Pages deploy workflow (path-scoped to `docs/**`, workflow_dispatch, concurrency-safe) |
| `.gitignore` | Modify | `!docs/*.yml` re-include (Consumer Audit for first non-`.md` file under `docs/`) |
| `docs/CI-INTEGRATION.md` | Modify | Remove "(lands in v0.7 Phase 3)" hedge — GLOSSARY now exists |

## Implementation Order

1. **Change 2** (`docs/_config.yml` + `.gitignore`) — Consumer Audit first so the new file isn't silently gitignored downstream.
2. **Change 1** (`docs/GLOSSARY.md`) — most content; the rest builds on it.
3. **Change 4** (`docs/index.md`) — links to GLOSSARY, so GLOSSARY exists first.
4. **Change 5** (`docs/CI-INTEGRATION.md` hedge removal) — references GLOSSARY which now exists.
5. **Change 3** (`.github/workflows/pages.yml`) — deploy plumbing last; nothing else depends on it.
6. **Post-merge** — `gh api -X POST repos/teelr/dev-platform/pages -f build_type=workflow` runs ONCE after this PR squash-merges to `main`.

## Verification Checklist

- [ ] All 5 Changes implemented per the spec
- [ ] `python3 -c "import yaml; yaml.safe_load(open(path))"` passes for `docs/_config.yml` and `.github/workflows/pages.yml`
- [ ] `git check-ignore -v docs/_config.yml` shows `!docs/*.yml` as the matching re-include
- [ ] `git check-ignore -v .github/workflows/pages.yml` shows `!.github/**/*.yml` as the matching re-include
- [ ] `./scripts/check_spec_taxonomy.sh` exits 0 — GLOSSARY's `### Term:` headings don't trigger killed-term flags (they're under no `## Phase N` parent)
- [ ] `./scripts/gate_fast.sh` PASS — no new test suite added in Phase 3 (Pages workflows test themselves at CI runtime), gate count unchanged at 66
- [ ] Every term documented as in-use in repo `*.md` is present in GLOSSARY (`grep` audit of 28 expected terms)
- [ ] `docs/index.md` references `GLOSSARY.md`, `CI-INTEGRATION.md`, new workflow chain (`PR → CI → merge → post-merge`)
- [ ] `docs/CI-INTEGRATION.md` no longer contains "lands in v0.7 Phase 3"
- [ ] No file under `projects/` modified
- [ ] Single-PR strategy applied (~250 LOC, under per-Spec-Phase threshold)
- [ ] **Post-merge:** `gh api repos/teelr/dev-platform/pages --jq '.build_type'` returns `"workflow"` after the one-shot enable call
- [ ] **Post-merge:** Pages deploys on the FIRST `docs/**`-touching commit after the post-merge enable; site reachable at `https://teelr.github.io/dev-platform/`
- [ ] **Post-merge:** Landing page renders, GLOSSARY link from CI-INTEGRATION resolves, GLOSSARY → CLAUDE.md cross-link resolves (via `jekyll-relative-links`)

## Out of Scope (Future Specs)

- **Custom domain / CNAME.** Pages on `teelr.github.io/dev-platform/` is the default URL; custom domains are a separate (one-time) configuration unrelated to this Spec.
- **Search functionality.** Static-site search needs a JS bundle (Lunr.js, Algolia, etc.). Out of v0.7 scope; the docs site is a curated reference, not a search-heavy reference.
- **Pages preview for PRs.** Some Pages deployments offer per-PR preview environments. Not free, not needed at 2–10 dev team scale.
- **Migrating root `README.md` into `docs/`.** Repo's README is the GitHub repo-view content; moving it would degrade the GitHub repo landing page for no Pages-side benefit. The relative-links plugin makes `docs/index.md` → `../README.md` resolve cleanly.
- **Other docs (NEW-PROJECT.md, PROJECT_CLAUDE_TEMPLATE.md) re-edits.** Both exist and render correctly under Jekyll. Out of scope unless drift surfaces.
- **GLOSSARY content beyond ~28 terms.** Capped at terms in active use; speculative future vocab stays out per the Honesty rule.
- **Auto-link-checking on the Pages site.** A future spec could add a workflow that runs `lychee` or similar to validate every `*.md` link doesn't 404. Defer until link rot is observed.

## Notes for Implementation

- **`docs/_config.yml` is the FIRST `.yml` under `docs/`.** Consumer Audit explicitly mandates the `.gitignore` extension. Run `git check-ignore -v` after writing the file — if the rule isn't matched, the file is silently gitignored and Pages will fail to build with an obscure "no _config.yml found" error.
- **Jekyll relative-links plugin is what makes `../README.md` work.** Without it, Jekyll treats relative paths as literal and the link 404s. The `_config.yml` line `plugins: [jekyll-relative-links]` plus `relative_links: enabled: true` enables it.
- **Pages workflow has its own permissions block** — `contents: read`, `pages: write`, `id-token: write`. Don't paste `permissions: write-all` shortcuts; the narrow grant is what GitHub's security review wants.
- **The `concurrency.group: pages` + `cancel-in-progress: false`** means rapid-fire commits to `docs/` queue up deploys rather than killing in-progress ones. The opposite (`cancel-in-progress: true`) is right for code CI but wrong for sites — better to wait for the older one to finish than to leave the site half-deployed.
- **GLOSSARY `### Term:` headings under no `## Phase N` parent**: this is critical for taxonomy compatibility. The killed-term check (`scripts/check_spec_taxonomy.sh`) only flags `### Task/Step/Item/...` headings when they're under `## Phase N`. The GLOSSARY has no `## Phase N` headers at all, so `### Term` entries pass cleanly. Run `./scripts/check_spec_taxonomy.sh` post-implementation to confirm.
- **Phase 3 is the second spec under the now-required `gate-fast` branch protection.** Every commit pushed to the feature branch triggers gate-fast; the PR can't merge until it's green. Mind cycle time on pushes — batch related changes locally rather than push-per-commit if iterating fast.
- **The post-merge `gh api` call is one-shot.** Running it again after Pages is already enabled returns the existing state (no error, no destructive op). Safe to re-run if uncertainty about state — but track that it ran at least once after this Spec's merge.
- **First Pages deploy takes 1–3 minutes** after the post-merge enable call. Subsequent deploys (on each `docs/**` commit) run in ~30s. Patience required on the first run.
- **Cayman theme renders Markdown tables, code fences, headings, and inline code natively.** No theme-customization needed. If a future spec wants a different look, `theme: minima` or `theme: jekyll-theme-architect` are drop-in alternatives; no other config changes needed.
