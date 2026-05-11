# v0.7: Team Enablement

## Coding Specification for Implementation

## Design Philosophy

v0.7 moves dev-platform from "solo discipline" to "team-mechanical gate." Through v0.6, every quality check (gate_fast, taxonomy, install round-trip) ran locally on Rich's machine because nobody else was contributing. v0.7 makes the same checks run **on every PR via GitHub Actions** so a teammate's change can't reach `main` without passing them — even if the teammate forgets to run `gate_fast.sh` locally. The repo became public in PR #5; v0.7 finishes the team-scale transition by adding the mechanical enforcement layer that consumes-and-validates rather than trusts.

Three deliverables make this real: (a) **taxonomy enforcement extended to ROADMAP.md + planning.md** so Roadmap Phase headers must match `v<MAJOR>.<MINOR>:` (the canonical rule landed earlier today but isn't yet enforced — Change 1 ships the enforcement); (b) **CI workflows** — dev-platform gets its own `.github/workflows/gate.yml` that runs `scripts/gate_fast.sh` on every PR + a reusable workflow other projects can call; (c) **GitHub Pages docs site** at `teelr.github.io/dev-platform/` with a `docs/GLOSSARY.md` so new contributors can read PRs and docs without insider vocabulary (recurring user pain — captured 2026-05-11). Plus a small bonus: **Milestones automation** that keeps GitHub Milestones in sync with `ROADMAP.md`.

Scope discipline: this is a TEAM-SCALE Roadmap Phase, but it does NOT touch other projects under `projects/`. Per the Scope rule in `dev/CLAUDE.md`, dev-platform never silently reaches into projects. The CI workflow template at `extensions/github-actions/dev-platform-gate.yml` is a TEMPLATE — consumer projects manually copy it into their own `.github/workflows/` (instructions in `docs/CI-INTEGRATION.md`). No automated "deploy CI into all projects" step. That's v0.8 (Cross-project orchestration) territory.

Per-Spec-Phase branching strategy applies — v0.7's 4 Spec Phases ship as 4 separate PRs. Each Phase is independently valuable and ~150–300 LOC, well within the threshold where per-Spec-Phase makes more sense than a single mega-PR.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/check_spec_taxonomy.sh` extension | Bash | Existing script in Bash; extend in place |
| `.github/workflows/*.yml` (CI workflows) | YAML | GitHub Actions native format |
| `extensions/github-actions/dev-platform-gate.yml` | YAML | Consumer template; uses GitHub Actions' reusable-workflow `uses:` syntax to call dev-platform's reusable workflow — minimum boilerplate per consumer repo |
| `scripts/sync-milestones.sh` | Bash | Matches existing entry-point pattern (`install.sh`, `verify.sh`, `gate_fast.sh`, `report.sh`, `sync-vscode.sh`). Uses `gh api` + `jq`. |
| `docs/GLOSSARY.md`, `docs/CI-INTEGRATION.md`, `docs/index.md` | Markdown | Docs |
| `docs/_config.yml` | YAML | Jekyll/GitHub Pages config |
| `tests/milestone-sync/run.sh` | Bash | Matches v0.4 R3 test-suite pattern; auto-discovered by `gate_fast.sh` |

## Overview

1. **Phase 1:** Taxonomy enforcement extended to roadmap-level docs (Changes 1–2)
2. **Phase 2:** GitHub Actions CI — dev-platform's own gate + a reusable workflow for consumer projects (Changes 3–7)
3. **Phase 3:** GitHub Pages docs site + `docs/GLOSSARY.md` (Changes 8–10)
4. **Phase 4:** Milestones automation (Changes 11–12)

**Demo:** After v0.7 ships:

- A PR that introduces `## Sprint 1: Foo` into `ROADMAP.md` or `planning.md` fails the taxonomy check at CI time (Phase 1).
- Every PR on dev-platform runs `gate_fast.sh` via GitHub Actions and reports the result as a required status check; PRs can't merge with red CI (Phase 2).
- Browsing `teelr.github.io/dev-platform/` shows a docs site with the README, ROADMAP, CLAUDE.md, GLOSSARY, and CI-INTEGRATION guide rendered (Phase 3).
- Running `./scripts/sync-milestones.sh` updates GitHub Milestones to match `ROADMAP.md` exactly — adds new milestones for new Roadmap Phases, updates titles/descriptions on existing ones, leaves closed-and-released Milestones alone (Phase 4).

---

## Phase 1: Taxonomy Enforcement at the Roadmap Level

### Change 1: Extend `scripts/check_spec_taxonomy.sh` to scan ROADMAP.md + planning.md

**Problem:** The current `check_spec_taxonomy.sh` scans `tasks/*-spec.md` for killed-term Spec Phase headers (e.g., `### Sprint 1:`). But Roadmap Phase headers in `ROADMAP.md` and `planning.md` are NOT scanned. The Roadmap Phase format rule in `dev/CLAUDE.md` says headers MUST match `v<MAJOR>.<MINOR>: <Title>` — without scanning, a future contributor could silently introduce `R7: Foo` or `Sprint X: Bar` and the gate would pass.

**File:** `scripts/check_spec_taxonomy.sh` (existing — extend with a new scan pass)

**Implementation:**

After the existing `tasks/*-spec.md` loop (ends around [check_spec_taxonomy.sh:92](scripts/check_spec_taxonomy.sh#L92)) and BEFORE the final summary (line 94), add a new scan pass that walks ROADMAP.md and planning.md:

```bash
# Scan ROADMAP.md + planning.md for non-conforming Roadmap Phase headers.
# Roadmap Phase headers MUST match the v<MAJOR>.<MINOR>: <Title> format per
# the rule in dev/CLAUDE.md. List-item form (with leading "- **") is also
# valid (e.g., "- **v0.5: Monitoring** ...").
#
# Killed Roadmap-level prefixes (anything other than `v<N>.<N>:`):
#   - Bare integer like "## Phase 1:" — that's Spec Phase, not Roadmap Phase
#   - Old "R<N>:" form (taxonomy migrated 2026-05-11)
#   - "Sprint X", "Stage Y", quarter buckets like "Q2-2026", etc.

ROADMAP_RE='^(- \*\*|## )(v[0-9]+\.[0-9]+[a-z]?:[[:space:]])'
KILLED_ROADMAP_RE='^(- \*\*|## )(R[0-9]+(\.[0-9]+)?[a-z]?:|Sprint [A-Z0-9]+:|Stage [A-Z0-9]+:|Q[0-9]+-[0-9]+:|[0-9]+Q[0-9]+:)'

scan_roadmap_file() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    local violations=()
    while IFS= read -r line; do
        if [[ "$line" =~ $KILLED_ROADMAP_RE ]]; then
            violations+=("$line")
        fi
    done < "$f"
    if [[ ${#violations[@]} -gt 0 ]]; then
        if [[ "$found_roadmap_violations" -eq 0 ]]; then
            echo ""
            echo "check_spec_taxonomy: Roadmap Phase headers using killed terminology"
            echo "  Required format: v<MAJOR>.<MINOR>[<letter>]: <Title>"
            echo "  See: dev/CLAUDE.md > Development Terminology"
            echo ""
        fi
        found_roadmap_violations=1
        echo "  ${f#$PROJECT_ROOT/}"
        for v in "${violations[@]}"; do
            echo "    $v"
        done
    fi
}

found_roadmap_violations=0
scan_roadmap_file "$PROJECT_ROOT/ROADMAP.md"
scan_roadmap_file "$PROJECT_ROOT/planning.md"

if [[ "$found_roadmap_violations" -eq 1 ]]; then
    found_violations=1
fi
```

The final exit-code logic (existing) handles `found_violations=1` correctly — exits 1 if any violation found across either scan pass.

Update the existing comment block at the top of the file to document the new scope:

```bash
# Scans:
#   tasks/*-spec.md  — for killed Spec Phase headers (### Sprint 1: etc.)
#   ROADMAP.md        — for killed Roadmap Phase headers (R<N>:, Sprint X:, ...)
#   planning.md       — same
```

**Acceptance Test:**

```bash
# Existing tasks/ check still works
./scripts/check_spec_taxonomy.sh   # expect exit 0, all conform

# Inject a violation into a temp ROADMAP.md and confirm exit 1
TMP=$(mktemp -d /tmp/v07-c1.XXX)
cp ROADMAP.md "$TMP/ROADMAP.md"
echo "- **Sprint X: Bad header** *(should fail)*" >> "$TMP/ROADMAP.md"
# Also need a stub tasks/ dir for the existing check to not skip
mkdir -p "$TMP/tasks"
echo "# stub" > "$TMP/tasks/stub-spec.md"
./scripts/check_spec_taxonomy.sh "$TMP" 2>&1 | grep -q "Roadmap Phase headers using killed"
rc=$?
[[ $rc -eq 0 ]] && echo "OK   killed Roadmap header detected"
rm -rf "$TMP"
```

### Change 2: Add `tests/taxonomy/` fixtures for Roadmap-level scanning

**Problem:** The existing `tests/taxonomy/run.sh` tests the killed-term checker against spec fixtures only. Change 1 extends the script to also scan ROADMAP.md/planning.md; the test suite must grow to cover the new scan path so a future edit can't regress the Roadmap-level scanning silently.

**File:** `tests/taxonomy/fixtures/` (new fixtures), `tests/taxonomy/run.sh` (extend)

**Implementation:**

Add three new fixtures:

- `tests/taxonomy/conformant-roadmap.md` — minimal valid ROADMAP.md using `- **v0.1: Foo** ...` and `- **v1.0: Bar** ...` entries
- `tests/taxonomy/bad-roadmap-sprint.md` — uses `- **Sprint K: Foo**` (the Keystone-style violation we want to catch)
- `tests/taxonomy/bad-roadmap-rprefix.md` — uses `- **R7: Foo**` (legacy `R<N>` form we just migrated away from)

Extend `tests/taxonomy/run.sh` (existing) to add 3 new `run_fixture` calls testing these — pattern matching the existing fixture loop. Pass each as a ROADMAP.md inside a temp project root and assert the expected exit code.

The existing `run_fixture` helper invokes `check_spec_taxonomy.sh` from inside a temp dir with a populated `tasks/`. Extend the helper or add a parallel `run_roadmap_fixture` that puts the fixture at `<tmp>/ROADMAP.md` instead of `<tmp>/tasks/...`.

**Acceptance Test:**

```bash
bash tests/taxonomy/run.sh
# Expect: existing 4 PASS + 3 new PASS = 7 PASS total

# Gate count grows by 3 (was 62 at v0.6 close, will be 65 after Change 2)
bash scripts/gate_fast.sh
# Expect: 65 PASS / 0 FAIL
```

---

## Phase 2: GitHub Actions CI

### Change 3: `.github/workflows/gate.yml` — dev-platform's own CI

**Problem:** Today nothing runs `gate_fast.sh` on PRs except Rich manually. A teammate (or future-Rich on a different machine) could open a PR with broken code that local discipline didn't catch. Need a mechanical gate at the PR boundary.

**File:** `.github/workflows/gate.yml` (new)

**Implementation:**

```yaml
name: gate-fast
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
jobs:
  gate-fast:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install jq + python3
        run: sudo apt-get update && sudo apt-get install -y jq python3
      - name: Run gate_fast.sh
        run: bash scripts/gate_fast.sh
```

Minimal. Uses `ubuntu-latest` runner; jq + python3 cover all current gate dependencies. No secrets needed — gate_fast.sh runs entirely offline against checked-out code. The `vscode` test suite's `command -v code` check will gracefully skip on the runner (no VSCode there), which is intentional — the existing graceful-skip path is exercised.

The workflow triggers on (a) PRs targeting main (gate must pass before merge) and (b) push to main (catches any branch-protection bypass; alerts if main is broken).

**Acceptance Test:**

After commit + push, the workflow runs and reports a green check on the PR. Easiest way to verify post-merge: open a small PR (e.g., a typo fix) and confirm the gate-fast check appears under "Checks" with the expected pass/fail status. Alternative test: push a deliberately-broken commit to a feature branch and confirm the workflow goes red.

### Change 4: `.github/workflows/taxonomy-check.yml` — reusable workflow for consumer projects

**Problem:** Other projects (kermit, atlas, kermit-pa) follow dev-platform's taxonomy but can't easily run `check_spec_taxonomy.sh` themselves without vendoring it. GitHub Actions' reusable-workflow mechanism (`workflow_call`) lets them call dev-platform's check from their own CI without copying the script.

**File:** `.github/workflows/taxonomy-check.yml` (new)

**Implementation:**

```yaml
name: taxonomy-check
on:
  workflow_call:
    inputs:
      ref:
        description: 'Ref of the calling repo to check out for files to scan'
        type: string
        required: false
        default: ''
jobs:
  taxonomy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout caller's repo
        uses: actions/checkout@v4
        with:
          ref: ${{ inputs.ref }}
          path: caller
      - name: Checkout dev-platform (for the check script)
        uses: actions/checkout@v4
        with:
          repository: teelr/dev-platform
          ref: ${{ github.workflow_ref || 'main' }}
          path: dev-platform
      - name: Run taxonomy check against caller's repo
        run: bash dev-platform/scripts/check_spec_taxonomy.sh "${GITHUB_WORKSPACE}/caller"
```

The `workflow_call` trigger means this workflow doesn't run on its own — it's only invoked by another workflow's `uses:` line.

**Acceptance Test:**

This workflow can't be tested in isolation (it's only invokable via `workflow_call`). The test is indirect: Change 5's consumer template `uses:` this workflow, and Change 7's CI-INTEGRATION docs walk a project through adopting it. Confirm the YAML parses (`python3 -c "import yaml; yaml.safe_load(open('.github/workflows/taxonomy-check.yml'))"`).

### Change 5: `extensions/github-actions/dev-platform-gate.yml` — consumer template

**Problem:** Consumer projects (kermit, atlas, kermit-pa) need a copy-paste-ready workflow file. The reusable workflow from Change 4 does the work; the consumer template is the 5-line YAML each project drops into their own `.github/workflows/` to plug in.

**File:** `extensions/github-actions/dev-platform-gate.yml` (new)

**Implementation:**

```yaml
# extensions/github-actions/dev-platform-gate.yml
# Copy this file into your project's .github/workflows/ to plug into
# dev-platform's taxonomy enforcement at the PR boundary.
#
# Pin to a specific tag (e.g., @v0.7) for stability, or @main for latest.
# See docs/CI-INTEGRATION.md for the full adoption guide.

name: dev-platform-gate
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
jobs:
  taxonomy:
    uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@v0.7
```

Single job: invokes the reusable workflow. Consumer projects can extend (e.g., add their own project-specific gate after the taxonomy check) by adding more jobs in their copy.

**Acceptance Test:**

YAML parses (`python3 -c "import yaml; yaml.safe_load(open('extensions/github-actions/dev-platform-gate.yml'))"`). The actual end-to-end test happens when a consumer project adopts the template (out of scope for v0.7's own QC).

### Change 6: Configure dev-platform's `main` branch protection to require `gate-fast`

**Problem:** Just adding `.github/workflows/gate.yml` doesn't BLOCK PRs from merging with red CI. GitHub's branch protection has a separate "required status checks" list. Without explicitly adding `gate-fast` to that list, the workflow runs but PRs can still merge with failures.

**File:** none (procedural — `gh api` call)

**Implementation:**

```bash
gh api -X PUT repos/teelr/dev-platform/branches/main/protection \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["gate-fast"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 0
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": false,
  "required_linear_history": false
}
JSON
```

`strict: true` means PRs must be up-to-date with main before merge (i.e., CI runs against the latest base).

`contexts: ["gate-fast"]` — the name MUST match the workflow's job (`jobs.gate-fast` in Change 3). If renamed, this must update.

**Acceptance Test:**

```bash
gh api repos/teelr/dev-platform/branches/main/protection --jq '.required_status_checks.contexts'
# Expect: ["gate-fast"]
```

After this, open a PR with a deliberately-broken change (e.g., add a Sprint header to ROADMAP.md). Confirm:
- Workflow runs and goes red
- The "Merge" button is greyed out with "Required status check expected" message

### Change 7: `docs/CI-INTEGRATION.md` — consumer adoption guide

**Problem:** Without a walkthrough, consumer projects don't know how to plug in dev-platform's taxonomy enforcement. The README is brief; this file is the canonical "how to adopt" doc.

**File:** `docs/CI-INTEGRATION.md` (new, ~100 lines)

**Implementation:**

Markdown doc with these sections:

1. **What this gives you** — taxonomy enforcement on every PR; a green check that proves your repo conforms to dev-platform standards
2. **Prerequisites** — public or paid-private GitHub repo (Actions free minutes apply)
3. **Adoption — 3 steps** —
   - (a) Copy `extensions/github-actions/dev-platform-gate.yml` from dev-platform into your project's `.github/workflows/dev-platform-gate.yml`
   - (b) Pin to the latest dev-platform release tag (`@v0.7` at time of writing)
   - (c) (Optional) Add the new `dev-platform-gate / taxonomy` status check to your repo's branch protection
4. **Rollout** — push the workflow file; open a test PR; confirm the check appears; address any violations
5. **Upgrading** — when dev-platform cuts a new release, bump the `@vX.Y` tag in your copy
6. **Local pre-flight** — run `bash dev-platform/scripts/check_spec_taxonomy.sh /path/to/your-repo` before pushing to catch violations early
7. **Disabling** — if you need to take a project offline temporarily, delete the workflow file or change `on:` to never-trigger

**Acceptance Test:** The doc exists; sections 1–7 are present; instructions reference real paths/commands.

---

## Phase 3: GitHub Pages Docs Site + Glossary

### Change 8: `docs/GLOSSARY.md`

**Problem:** Recurring user pain (logged 2026-05-11): the dev-platform vocabulary (gate, ship, land, cut release, in flight, the gate, Roadmap Phase, Spec Phase, Change, seed, wired-in, consumer-audit) is opaque to new contributors. A glossary at one canonical URL is the linkable cure.

**File:** `docs/GLOSSARY.md` (new, ~200 lines)

**Implementation:**

Markdown doc, alphabetized by term. Each entry: term in bold, 1–2 sentence definition, link to authoritative source (CLAUDE.md section, ROADMAP.md, etc.) when relevant.

Required entries (minimum — flag any missing during /code):

- Change, Commit, Consumer Audit, Cut release, Deploy, Drift, Gate, Gate fast, Gate full, Gate green, Gate release, GitHub Milestone, In flight, Land, Live cutover, Per-Spec-Phase strategy, PR (Pull Request), Roadmap Phase, Seed, Ship, Spec, Spec Phase, Squash merge, Symlink deploy, The gate, Tracked file, Wired-in, `v<MAJOR>.<MINOR>`

Each entry follows the same shape:

```markdown
### Gate

The set of mechanical checks that must pass before a commit can land on `main`.
dev-platform's gate is `./scripts/gate_fast.sh` (62+ checks, <2s). See
[CLAUDE.md > Workflow Discipline > Gate Coverage](../CLAUDE.md) for the
asymmetric gate-fast vs gate-full vs gate-release split.
```

**Acceptance Test:**

```bash
test -f docs/GLOSSARY.md
wc -l docs/GLOSSARY.md   # expect 150+ lines

# Required terms present
for term in "Change" "Roadmap Phase" "Consumer Audit" "Gate" "Spec Phase" "Symlink deploy"; do
    grep -q "^### ${term}" docs/GLOSSARY.md && echo "OK ${term}" || echo "MISSING ${term}"
done
```

### Change 9: GitHub Pages config

**Problem:** GitHub Pages can render the entire `docs/` tree as a hosted site at `teelr.github.io/dev-platform/` for free (public repo). Without a config file, Pages uses defaults that may not render correctly with our existing Markdown.

**File:** `docs/_config.yml` (new), `.github/workflows/pages.yml` (new)

**Implementation:**

`docs/_config.yml`:

```yaml
# Jekyll config for GitHub Pages render of dev-platform/docs/.
# Minimal — uses the default Cayman theme; relies on Markdown rendering.
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

`.github/workflows/pages.yml`:

```yaml
name: deploy-pages
on:
  push:
    branches: [main]
    paths:
      - 'docs/**'
      - '.github/workflows/pages.yml'
permissions:
  contents: read
  pages: write
  id-token: write
jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/configure-pages@v4
      - name: Build Jekyll site
        uses: actions/jekyll-build-pages@v1
        with:
          source: docs
      - uses: actions/upload-pages-artifact@v3
      - uses: actions/deploy-pages@v4
```

Also: in the repo settings, enable Pages with source = "GitHub Actions" (not "branch"). This is a one-shot config step via `gh api`:

```bash
gh api -X POST repos/teelr/dev-platform/pages -f source.branch=main -f source.path=/docs
# or via UI: Settings → Pages → Build and deployment → Source: GitHub Actions
```

**Acceptance Test:**

After the workflow runs (post-merge), browse https://teelr.github.io/dev-platform/. The README renders as the landing page; navigation links to GLOSSARY work.

### Change 10: `docs/index.md` — landing page

**Problem:** GitHub Pages defaults to rendering `index.md` (or `README.md`) at the site root. `README.md` at the repo root is what GitHub displays in the repo view; copying it into `docs/` for Pages duplicates content. Better: a thin `docs/index.md` that links to the README and key docs.

**File:** `docs/index.md` (new, ~50 lines)

**Implementation:**

```markdown
# dev-platform

Source of truth for Rich's developer environment: rules, slash commands, skills, hooks, settings, install scripts, telemetry, VSCode extensions.

## Documentation

- **[README](../README.md)** — what this repo is, quick start, repo structure
- **[ROADMAP](../ROADMAP.md)** — Roadmap Phases v0.1 → v1.0
- **[CLAUDE.md](../CLAUDE.md)** — full development standards (workflow, taxonomy, language matrix, port registry, project structure)
- **[Glossary](GLOSSARY.md)** — every project-specific term defined
- **[CI Integration](CI-INTEGRATION.md)** — how to plug your repo into dev-platform's taxonomy gate
- **[New Project](NEW-PROJECT.md)** — conversational Q&A for scaffolding new projects
- **[Project CLAUDE.md template](PROJECT_CLAUDE_TEMPLATE.md)** — what every project's CLAUDE.md should contain

## Latest release

See [Releases](https://github.com/teelr/dev-platform/releases). Current: v0.7 (Team Enablement).

## Workflow

`/plan → /code → /test → /review → /gate fast → /docs → commit → push → PR`

Each step is mechanical and reproducible. See CLAUDE.md for the full discipline.
```

**Acceptance Test:**

```bash
test -f docs/index.md
grep -q "GLOSSARY.md" docs/index.md
grep -q "CI-INTEGRATION.md" docs/index.md
```

---

## Phase 4: Milestones Automation

### Change 11: `scripts/sync-milestones.sh`

**Problem:** GitHub Milestones currently track Roadmap Phases (one per `v<N>.<N>` entry), but they're maintained manually — when a new Roadmap Phase is added to ROADMAP.md, someone has to remember to create the matching Milestone. The Milestones-as-the-team's-shared-status promise from v0.5 needs automation to stay current.

**File:** `scripts/sync-milestones.sh` (new, ~80 lines)

**Implementation:**

```bash
#!/usr/bin/env bash
# scripts/sync-milestones.sh — mirror ROADMAP.md entries to GitHub Milestones.
# Idempotent: re-running creates missing milestones, updates existing ones,
# leaves closed milestones alone.
#
# Usage:
#   ./scripts/sync-milestones.sh                    # dry-run by default
#   ./scripts/sync-milestones.sh --apply            # actually create/update
#   ./scripts/sync-milestones.sh --apply --repo X/Y # different repo

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROADMAP="${REPO_ROOT}/ROADMAP.md"

GH_REPO="teelr/dev-platform"
APPLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply) APPLY=1 ;;
        --repo)  shift; GH_REPO="$1" ;;
        --help|-h)
            sed -n '2,12p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
    shift
done

command -v gh >/dev/null || { echo "ERROR: gh CLI required" >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq required" >&2; exit 1; }
[[ -f "${ROADMAP}" ]] || { echo "ERROR: ROADMAP.md not found at ${ROADMAP}" >&2; exit 1; }

# Parse ROADMAP.md entries — lines like "- **v0.5: Monitoring** *(complete — ...)*"
# Extract title (v<N>.<N>: <Title>) and state (complete | IN FLIGHT | planned).
parse_entries() {
    awk '
        /^- \*\*v[0-9]+\.[0-9]+[a-z]?: / {
            # Title is between **...** before " *("
            title = $0
            sub(/^- \*\*/, "", title)
            sub(/\*\* .*/, "", title)

            # State based on rest of line
            state = "open"
            if ($0 ~ /\(complete /) state = "closed"

            # Description — everything after the closing **
            desc = $0
            sub(/^- \*\*[^*]+\*\* /, "", desc)
            # Strip backslash + asterisks + parens
            gsub(/\\?[*()]/, "", desc)

            print title "|" state "|" desc
        }
    ' "${ROADMAP}"
}

# Fetch current Milestones
fetch_milestones() {
    gh api "repos/${GH_REPO}/milestones?state=all&per_page=100" \
        --jq '.[] | {number, title, state, description}'
}

# For each parsed entry: find by title, decide create/update/skip
existing="$(fetch_milestones | jq -s .)"

while IFS='|' read -r title state desc; do
    # Find existing milestone by title
    existing_id="$(echo "${existing}" | jq -r ".[] | select(.title == \"${title}\") | .number")"
    existing_state="$(echo "${existing}" | jq -r ".[] | select(.title == \"${title}\") | .state")"

    if [[ -z "${existing_id}" ]]; then
        action="CREATE"
        if [[ ${APPLY} -eq 1 ]]; then
            gh api "repos/${GH_REPO}/milestones" -X POST \
                -f title="${title}" -f state="${state}" -f description="${desc:0:500}" >/dev/null
        fi
    elif [[ "${existing_state}" == "closed" ]]; then
        action="SKIP (already closed)"
    else
        action="UPDATE"
        if [[ ${APPLY} -eq 1 ]]; then
            gh api "repos/${GH_REPO}/milestones/${existing_id}" -X PATCH \
                -f state="${state}" -f description="${desc:0:500}" >/dev/null
        fi
    fi
    echo "  ${action}: ${title}"
done < <(parse_entries)

if [[ ${APPLY} -eq 0 ]]; then
    echo ""
    echo "Dry-run. Re-run with --apply to commit changes."
fi
```

**Acceptance Test:**

```bash
# Dry-run against the real repo — should report SKIP for closed v0.1..v0.6
./scripts/sync-milestones.sh 2>&1 | grep -E "SKIP|CREATE|UPDATE"

# Help renders
./scripts/sync-milestones.sh --help | head -5

# Required tools enforced
PATH=/tmp ./scripts/sync-milestones.sh 2>&1 | grep -q "gh CLI required"
```

### Change 12: `tests/milestone-sync/` fixture suite

**Problem:** The sync-milestones script parses ROADMAP.md — a brittle awk pattern that can regress if ROADMAP.md formatting changes. A fixture suite catches regressions without making real `gh api` calls.

**File:** `tests/milestone-sync/run.sh` (new), `tests/milestone-sync/fixtures/sample-roadmap.md` (new)

**Implementation:**

Fixture `sample-roadmap.md` with three entries:

```markdown
# Test Roadmap

- **v0.1: Foundation** *(complete — 2026-05-08)* — first phase shipped
- **v0.2: Hooks** *(IN FLIGHT)* — phase in flight
- **v0.3: Next** *(planned)* — phase not started
```

Runner `tests/milestone-sync/run.sh` mocks `gh` (similar to v0.6's mock `code` pattern) to record what calls would be made, then asserts the right calls happen:

- For v0.1: GET milestones → not found → POST create with state=closed
- For v0.2: GET → not found → POST create with state=open  
- For v0.3: GET → not found → POST create with state=open

Mock `gh` at `tests/milestone-sync/fixtures/mock-bin/gh`:

```bash
#!/usr/bin/env bash
# Mock gh CLI. Records calls to $MOCK_GH_CALLS; returns empty list for `api .../milestones`.
set -uo pipefail
echo "$@" >> "${MOCK_GH_CALLS:-/dev/null}"
case "$2" in
    *milestones*)
        # Return empty list to simulate "no existing milestones"
        echo "[]"
        ;;
esac
```

Test runner asserts the recorded calls match expected sequence.

**Acceptance Test:**

```bash
bash tests/milestone-sync/run.sh
# Expect: ≥3 PASS (one assertion per phase parsed correctly)

# Auto-discovery picks it up
bash scripts/gate_fast.sh 2>&1 | grep "tests/milestone-sync"
# Expect: present in gate output
```

---

## Acceptance Criteria

- [ ] `check_spec_taxonomy.sh` scans ROADMAP.md + planning.md for `v<MAJOR>.<MINOR>` headers; killed-term Roadmap headers cause exit 1 (Change 1)
- [ ] `tests/taxonomy/` has 3 new fixtures + assertions for Roadmap-level scanning (Change 2)
- [ ] `.github/workflows/gate.yml` runs `gate_fast.sh` on every PR and push to main (Change 3)
- [ ] `.github/workflows/taxonomy-check.yml` is a valid `workflow_call` reusable workflow (Change 4)
- [ ] `extensions/github-actions/dev-platform-gate.yml` is a valid YAML template invoking the reusable workflow (Change 5)
- [ ] `main` branch protection requires the `gate-fast` status check (Change 6)
- [ ] `docs/CI-INTEGRATION.md` exists with sections 1–7 (Change 7)
- [ ] `docs/GLOSSARY.md` exists with all required terms (Change 8)
- [ ] GitHub Pages deploys on push to main (Change 9); site renders at `teelr.github.io/dev-platform/`
- [ ] `docs/index.md` exists, links to GLOSSARY + CI-INTEGRATION (Change 10)
- [ ] `scripts/sync-milestones.sh` dry-run shows SKIP for closed v0.1–v0.6 (Change 11)
- [ ] `tests/milestone-sync/run.sh` auto-discovered by `gate_fast.sh`, ≥3 PASS (Change 12)
- [ ] `bash scripts/gate_fast.sh` still PASS — total grows from 62 to ~70 (added taxonomy fixtures + milestone-sync tests)
- [ ] No file under `projects/` modified
- [ ] Consumer Audit applied at every new directory: `.github/workflows/`, `docs/_config.yml`, `tests/milestone-sync/`

## Out of Scope (Future Specs)

- **Auto-deploying CI to projects/** — dev-platform doesn't reach into projects/ per the Scope rule. Each project copies the template manually. Automated cross-project deployment is v0.8 (Cross-project orchestration) territory.
- **Migrating existing projects to use the taxonomy gate** — kermit/atlas/kermit-pa adoption is each project's own session work, scheduled separately. v0.9 (Migration tooling) automates the renames (Sprint K → v?).
- **`gate_full.sh` in CI** — gate_fast.sh is enough for the PR boundary. gate_full / load tiers are for release qualification, not every commit.
- **Linear / Jira tracker sync** — Milestones-only in v0.7. Tracker sync deferred until a tracker is picked.
- **GitHub Discussions integration** — out of scope.
- **Required CODEOWNERS file** — not needed at 2–10 dev scale.
- **Per-OS Pages preview builds** — Pages builds on GitHub-managed runners; no per-OS variation needed.

## What NOT to Do

- **Do not edit any file under `projects/`.** v0.7's whole point is enforcement WITHOUT silent cross-project reach. The CI workflow template at `extensions/github-actions/` is for consumers to manually copy.
- **Do not add `gate_full` or load-tier tests to the GitHub Actions workflow.** gate_fast.sh is the right granularity for every-PR enforcement. Slower tests run locally or in scheduled jobs.
- **Do not pin GitHub Actions versions to `@latest` or `@vN` (major-only).** Use a specific tag (`@v4` for major-pinned official actions; `@v0.7` for dev-platform's own reusable workflow). Floating tags break reproducibility.
- **Do not put secrets in any workflow YAML.** v0.7's checks are entirely offline (no API calls except `gh` for milestone sync, which auto-authenticates via GITHUB_TOKEN). If a future workflow needs secrets, use GitHub Encrypted Secrets, never inline.
- **Do not change `dev/CLAUDE.md`'s Roadmap Phase format from `v<MAJOR>.<MINOR>:` in this spec.** The migration landed already; v0.7 ENFORCES it. Changing the format here would invalidate every existing entry in ROADMAP.md.
- **Do not skip Phase 1's taxonomy extension as "redundant" because the CI workflow already runs gate_fast.sh.** gate_fast.sh runs `check_spec_taxonomy.sh`, which today only scans `tasks/*-spec.md`. Without Change 1, ROADMAP.md violations slip past the gate. Phase 1 is the actual enforcement.
- **Do not skip Phase 4's milestone automation thinking "manual sync was fine."** As Roadmap Phases accumulate, manual sync drifts. Better to automate now while the surface is small (10 phases) than later (50+).
- **Do not bundle the v0.6b client-side spec into v0.7.** That's a separate Roadmap Phase. v0.7's scope is CI + docs + milestones; v0.6b would be a separate spec when there's appetite.
- **Do not configure branch protection to require approval review** (`required_approving_review_count > 0`). Solo Rich self-merges; team-scale appetite for review-required can come later as a separate config tweak.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/check_spec_taxonomy.sh` | Modify | Add ROADMAP.md + planning.md scan pass |
| `tests/taxonomy/fixtures/conformant-roadmap.md` | New | Roadmap fixture (passes) |
| `tests/taxonomy/fixtures/bad-roadmap-sprint.md` | New | Roadmap fixture (Sprint X violation) |
| `tests/taxonomy/fixtures/bad-roadmap-rprefix.md` | New | Roadmap fixture (R7 violation) |
| `tests/taxonomy/run.sh` | Modify | Add 3 new fixture assertions |
| `.github/workflows/gate.yml` | New | dev-platform's own CI |
| `.github/workflows/taxonomy-check.yml` | New | Reusable workflow for consumer projects |
| `.github/workflows/pages.yml` | New | GitHub Pages deploy |
| `extensions/github-actions/dev-platform-gate.yml` | New | Consumer-side template |
| `docs/CI-INTEGRATION.md` | New | Adoption guide |
| `docs/GLOSSARY.md` | New | Terminology reference |
| `docs/index.md` | New | Pages landing page |
| `docs/_config.yml` | New | Jekyll config for Pages |
| `scripts/sync-milestones.sh` | New | ROADMAP.md → GitHub Milestones |
| `tests/milestone-sync/run.sh` | New | Fixture suite for sync script |
| `tests/milestone-sync/fixtures/sample-roadmap.md` | New | Roadmap parser fixture |
| `tests/milestone-sync/fixtures/mock-bin/gh` | New | Mock `gh` CLI for round-trip testing |
| `dev/CLAUDE.md` | Modify (by /docs) | Repo Structure: add `.github/` row; document the new workflows |
| `.gitignore` | Modify (by Consumer Audit) | Allow `!.github/**/*.yml` if not already; ensure new dirs are tracked |
| `tasks/dev-platform-team-enablement-spec.md` | (this file) | Spec |

## Implementation Order

1. **Phase 1 (Change 1, 2)** — extends an existing script + tests. Lowest risk, smallest blast radius. Establishes the enforcement primitive that Phase 2's CI will exercise.
2. **Phase 2 (Changes 3, 4, 5, 6, 7)** — biggest phase. Order within: gate.yml first (Change 3), then reusable workflow (Change 4), then consumer template (Change 5), then branch-protection config (Change 6), then docs (Change 7). Change 6 MUST come after Change 3 deploys (workflow needs to exist before being marked required).
3. **Phase 3 (Changes 8, 9, 10)** — docs site. Change 8 (GLOSSARY) is the content; Changes 9–10 are the deployment plumbing.
4. **Phase 4 (Changes 11, 12)** — sync script + tests. Independent of Phases 1–3.

Each Phase ships as its own PR per the per-Spec-Phase strategy.

## Verification Checklist

- [ ] All 12 Changes implemented per the spec
- [ ] `bash -n` passes on every modified `.sh` file
- [ ] Every new `.yml` parses (`python3 -c "import yaml; yaml.safe_load(open('<file>'))"`)
- [ ] `check_spec_taxonomy.sh` exits 1 on a fixture ROADMAP with Sprint/R-prefix violations
- [ ] `check_spec_taxonomy.sh` exits 0 on the conformant fixture
- [ ] `bash scripts/gate_fast.sh` PASS (target: ~70 checks after Phase 1+4 add fixtures)
- [ ] On a test PR: workflow runs, status check appears, merge blocked if red
- [ ] `gh api repos/teelr/dev-platform/branches/main/protection --jq '.required_status_checks.contexts'` returns `["gate-fast"]`
- [ ] `https://teelr.github.io/dev-platform/` renders index → GLOSSARY → CLAUDE.md navigation
- [ ] `./scripts/sync-milestones.sh` dry-run reports SKIP for closed v0.1–v0.6
- [ ] `./scripts/sync-milestones.sh --apply` is idempotent (second run reports SKIP for everything)
- [ ] `tests/milestone-sync/` auto-discovered by `gate_fast.sh`
- [ ] No file under `projects/` modified
- [ ] Consumer Audit applied: gitignore allow-list checked for `.github/**/*.yml`, `docs/_config.yml`, `tests/milestone-sync/**`, mock-bin/gh

## Notes for Implementation

- **`.github/workflows/` is a NEW top-level directory under dev-platform.** Verify gitignore covers `.yml` files at that depth before commit (Consumer Audit point #1). If not, extend `.gitignore` with `!.github/`, `!.github/workflows/`, `!.github/workflows/*.yml`.
- **`docs/_config.yml` is a YAML at the `docs/` root.** Verify `!docs/*.yml` is in gitignore (or extend).
- **The reusable workflow at `.github/workflows/taxonomy-check.yml` cannot be tested with `act` (local GitHub Actions runner) easily** — it requires `workflow_call` from another workflow. Manual end-to-end test via a real PR is the verification.
- **GitHub Pages first build takes 1–2 minutes after enabling** — patience required. After the first deploy succeeds, subsequent builds (on docs/ change) take ~30 seconds.
- **Branch protection's `required_status_checks.contexts` uses JOB names, not WORKFLOW names.** The job inside gate.yml is `gate-fast`, so the context name is `gate-fast`. If you rename the job, update the protection config.
- **`gh` CLI is required for sync-milestones.sh + branch-protection config.** Already available on dev environments; document the dependency in the relevant scripts.
- **The `dev-platform/scripts/check_spec_taxonomy.sh` invocation from taxonomy-check.yml passes the CALLER'S checkout path as argument**, so the check scans the caller's `tasks/`, `ROADMAP.md`, `planning.md` — NOT dev-platform's own. This is correct: a consumer project's CI checks the consumer's docs against the taxonomy.
- **Per-Spec-Phase ships v0.7 as 4 PRs.** Phase 1 (taxonomy extension) first since Phase 2's CI depends on it. Then Phase 2, then Phase 3 (docs), then Phase 4 (Milestones automation). Each PR assigned to the v0.7 Milestone.
- **The Consumer Audit rule (PR #5) is expected to fire at minimum twice in v0.7**: (a) first `.yml` files under `.github/workflows/` likely need gitignore allow-list extension; (b) first file under `docs/` that isn't `.md` (`_config.yml`) likely needs same. /code should run `git check-ignore -v` on every new file before commit.
