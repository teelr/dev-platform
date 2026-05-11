# v0.8 Phase 2 — Fleet Dashboard

## Coding Specification for Implementation

## Design Philosophy

Phase 1 answered "did the fleet's gates pass?" Phase 2 answers "what's the current state of the fleet?" — per-project last-commit recency, current branch, uncommitted file count, taxonomy compliance, and dev-platform-gate consumer-template adoption. All read-only, all derivable from the registry + `git` + `check_spec_taxonomy.sh` + a filesystem `test -f`. No fleet sweep (Phase 1's job); no mutations (Phase 3's job). The dashboard is the static-state companion to fleet-gate's behavioral-state report.

The implementation is the v0.5 Monitoring pattern at fleet granularity: a Python aggregator (`monitoring/fleet_dashboard.py`) that walks the registry concurrently via `concurrent.futures.ThreadPoolExecutor`, plus a thin Bash CLI wrapper (`scripts/fleet-status.sh`) that delegates to it. The wrapper mirrors `scripts/report.sh`'s shape one-to-one. Output: markdown table (default) or JSON (`--format json`). No new code-component category triggers the Language Matrix — Python for aggregation matches the existing [monitoring/aggregator.py](../monitoring/aggregator.py) pattern; Bash wrapper matches the existing entry-point convention.

Per the per-Spec-Phase strategy, Phase 2 ships as one PR (~250 LOC). Per the workflow-extension rule from PR #9, the spec names a **post-merge** step — verify the dashboard against live state. Per the Phase 1 lesson on fixture-dir naming + auto-discovery, the new test suite re-uses Phase 1's `tests/fleet-gate/fixtures/mock-projects/<X>/` shape (NOT `projects/`) and lives at `tests/fleet-dashboard/` with no runnable `.sh` files inside `fixtures/`. A reusable `tests/helpers/mock-project-tree.sh` helper is added in this Phase so Phase 3 + 4's tests can share it.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `monitoring/fleet_dashboard.py` | Python | Mirrors v0.5's `monitoring/aggregator.py` — argparse, dataclasses, JSON output, no `pip install` deps. Concurrent per-project queries via `concurrent.futures.ThreadPoolExecutor`. |
| `scripts/fleet-status.sh` | Bash | Entry-point pattern (`install.sh`, `gate_fast.sh`, `sync-vscode.sh`, `sync-milestones.sh`, `report.sh`, `fleet-gate.sh`). Thin wrapper delegating to the Python script. |
| `tests/fleet-dashboard/run.sh` + `tests/helpers/mock-project-tree.sh` | Bash | Test-suite pattern locked in v0.4; mock-project-tree pattern from v0.8 Phase 1. |

No new code-component category. Python for aggregation, Bash for the rest — matches every prior monitoring + entry-point spec.

## Overview

1. **Phase 1:** Fleet Dashboard (Changes 1–3, plus the shared mock-project-tree helper)

Single-Phase Spec — total LOC ≤ ~250 (aggregator ~200 + wrapper ~30 + tests ~150 + helper ~50). Tightly coupled; one PR.

---

## Phase 1: Fleet Dashboard

### Change 1: `tests/helpers/mock-project-tree.sh` — reusable fixture helper

**Problem:** Phase 2's tests need a mock-project tree where each "project" has a real `.git` (so `git log -1` returns something) and optional state (uncommitted files, taxonomy violation, consumer template installed). Phase 3 + 4's tests will need the same setup. Without a shared helper, three test suites would each reimplement the same mktemp + `git init` + commit dance. Ship the helper FIRST in Phase 2 so Phases 3 + 4 can reuse it.

**File:** `tests/helpers/mock-project-tree.sh` (new, ~50 lines)

**Implementation:**

Bash source-able library (mirrors `tests/helpers/assert.sh`). Defines functions, NOT a runnable script.

```bash
# tests/helpers/mock-project-tree.sh — set up a mock fleet for Phase 2+
# test suites. Source it from a test runner; do NOT execute directly.
#
# Pattern: each "project" is a subdirectory under a parent root with
# its own .git, at least one commit, and optional state (uncommitted
# files, tasks/-spec.md with a taxonomy violation, .github/workflows/
# dev-platform-gate.yml consumer template).
#
# Usage:
#   source "${REPO}/tests/helpers/mock-project-tree.sh"
#   ROOT="$(mktemp -d /tmp/fleet-mock.XXXX)"
#   mock_project_init "${ROOT}/pass-1"
#   mock_project_commit "${ROOT}/pass-1" "initial"
#   mock_project_dirty "${ROOT}/pass-1" "uncommitted-file.txt"
#   mock_project_taxonomy_violation "${ROOT}/pass-1"
#   mock_project_install_template "${ROOT}/pass-1"
#   trap "rm -rf '${ROOT}'" EXIT

mock_project_init() {
    local dir="$1"
    mkdir -p "${dir}"
    (cd "${dir}" && git init -q && git -c user.email=t@t -c user.name=t commit --allow-empty -q -m "init")
}

mock_project_commit() {
    local dir="$1"
    local msg="${2:-fixture commit}"
    (cd "${dir}" && git -c user.email=t@t -c user.name=t commit --allow-empty -q -m "${msg}")
}

mock_project_dirty() {
    local dir="$1"
    local file="${2:-uncommitted.txt}"
    echo "uncommitted content" > "${dir}/${file}"
}

mock_project_taxonomy_violation() {
    # Adds a tasks/foo-spec.md with a killed Roadmap-Phase prefix.
    # check_spec_taxonomy.sh will flag this on the next scan.
    local dir="$1"
    mkdir -p "${dir}/tasks"
    cat > "${dir}/ROADMAP.md" <<'EOF'
# Roadmap
- **Sprint K: Foo** *(planned)* — killed-prefix triggers taxonomy violation
EOF
}

mock_project_install_template() {
    # Drops the consumer dev-platform-gate.yml into the project's
    # .github/workflows/. Triggers the dashboard's "adopted" flag.
    local dir="$1"
    mkdir -p "${dir}/.github/workflows"
    cat > "${dir}/.github/workflows/dev-platform-gate.yml" <<'EOF'
name: dev-platform-gate
on: [pull_request]
jobs:
  taxonomy:
    uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@v0.7
EOF
}
```

**Consumer Audit:** `tests/helpers/*.sh` — confirm with `git check-ignore -v` post-create. `tests/helpers/assert.sh` is already tracked via `!tests/**/*.sh`, so this matches the same rule.

**Acceptance Test:**

```bash
test -f tests/helpers/mock-project-tree.sh
bash -n tests/helpers/mock-project-tree.sh

# Smoke-test the helper functions
TMP="$(mktemp -d /tmp/mpt-test.XXXX)"
source tests/helpers/mock-project-tree.sh
mock_project_init "${TMP}/p1"
mock_project_dirty "${TMP}/p1" "drift.txt"
test -d "${TMP}/p1/.git"
test -f "${TMP}/p1/drift.txt"
(cd "${TMP}/p1" && git log -1 --oneline | grep -q init)
rm -rf "${TMP}"
echo "OK helper smoke"
```

### Change 2: `monitoring/fleet_dashboard.py` — per-project state aggregator

**Problem:** Today, querying "what state is each project in?" requires manually `cd`-ing into each project and running half a dozen `git` commands. As the active project count grew past 3, the manual sweep stopped being useful. A scriptable dashboard reading the v0.8 Phase 1 registry, running per-project queries concurrently, and emitting a single table or JSON payload makes fleet state visible at a glance.

**File:** `monitoring/fleet_dashboard.py` (new, ~200 lines)

**Implementation:**

Python script. Argparse: `--format markdown|json` (default `markdown`), `--project <name>` (single-project filter, optional), `--registry <path>` (default `monitoring/projects.json`), `--help`. Reads the registry. For each enabled entry (or single project), runs per-project queries concurrently via `concurrent.futures.ThreadPoolExecutor(max_workers=8)`:

- `git -C <path> log -1 --format=%ci|%H|%s` — last commit timestamp, sha, subject
- `git -C <path> rev-parse --abbrev-ref HEAD` — current branch
- `git -C <path> status --porcelain` (count lines) — uncommitted file count
- `bash <REPO>/scripts/check_spec_taxonomy.sh <path>` (silent; exit code 0 = OK, 1 = drift) — taxonomy compliance flag
- `os.path.exists(f"{path}/.github/workflows/dev-platform-gate.yml")` — consumer-template adoption flag

Aggregate the per-project results into a list ordered by registry order. Format per `--format`:

**Markdown** (default — render to stdout):

```text
# Fleet Dashboard

Generated: 2026-05-12T09:32:00Z
Registry: monitoring/projects.json (5 enabled)

| Project      | Branch       | Last commit       | Uncommitted | Taxonomy | dev-platform-gate |
| ------------ | ------------ | ----------------- | ----------- | -------- | ----------------- |
| dev-platform | main         | 2026-05-11 (1d)   | 0           | OK       | self              |
| atlas        | main         | 2026-05-11 (1d)   | 3           | DRIFT    | —                 |
| kermit       | v2.21-prep   | 2026-05-11 (1d)   | 0           | OK       | —                 |
| kermit-pa    | main         | 2026-05-11 (1d)   | 1           | OK       | —                 |
| keystone     | atlas-merge  | 2026-05-05 (7d)   | 0           | OK       | —                 |
```

Last-commit column uses `<YYYY-MM-DD> (<age-days>d)`. Age computed as `(now - last_commit_ts).days`. Branch is truncated to ~20 chars with ellipsis if needed.

**JSON** (`--format json`):

```json
{
  "generated_at": "2026-05-12T09:32:00Z",
  "registry_path": "monitoring/projects.json",
  "projects": [
    {
      "name": "dev-platform",
      "path": ".",
      "branch": "main",
      "last_commit_iso": "2026-05-11T15:31:32Z",
      "last_commit_sha": "aa1db43",
      "last_commit_subject": "feat: v0.7 Phase 4...",
      "last_commit_age_days": 1,
      "uncommitted_count": 0,
      "taxonomy_ok": true,
      "dev_platform_gate_installed": "self"
    },
    ...
  ]
}
```

`dev_platform_gate_installed`: `"self"` for dev-platform (it IS the gate); `true` if `.github/workflows/dev-platform-gate.yml` exists in the project; `false` otherwise.

Single-source-of-truth: this script does NOT run gates (Phase 1's job) or mutate anything. It only queries cheap state. Per-project query budget < 500ms; total dashboard < 2s for 5 projects.

**Imports** (stdlib only — matches v0.5 aggregator.py):

```python
import argparse, json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
```

**Argparse robustness**: every value-taking flag (`--format`, `--project`, `--registry`) explicit; missing value yields actionable error + exit 2. (Per the v0.7 Phase 4 lesson.)

**Acceptance Test:**

```bash
test -f monitoring/fleet_dashboard.py
python3 -c "import ast; ast.parse(open('monitoring/fleet_dashboard.py').read())" && echo "OK syntax"

# Help works without git/filesystem calls
python3 monitoring/fleet_dashboard.py --help | grep -q "Fleet Dashboard"

# Markdown render against real registry
python3 monitoring/fleet_dashboard.py | head -10
# Expect: "# Fleet Dashboard" title + "Generated:" line + table with 5+ rows

# JSON render — parseable
python3 monitoring/fleet_dashboard.py --format json | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert 'projects' in d and isinstance(d['projects'], list)
assert len(d['projects']) >= 5
print(f'{len(d[\"projects\"])} projects')
"

# Single-project filter
python3 monitoring/fleet_dashboard.py --project dev-platform --format json | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert len(d['projects']) == 1
assert d['projects'][0]['name'] == 'dev-platform'
print('OK single-project')
"

# Required-tool gate (no jq needed for Python; only registry must exist)
python3 monitoring/fleet_dashboard.py --registry /nonexistent 2>&1 | grep -q "registry not found"
```

### Change 3: `scripts/fleet-status.sh` — Bash CLI wrapper

**Problem:** Power users invoke Python aggregators via `python3 monitoring/fleet_dashboard.py ...`. Most dev-platform users expect a Bash entry-point matching the rest of the scripts (`./scripts/<verb>.sh`). The wrapper is a thin redirect, identical in shape to `scripts/report.sh`.

**File:** `scripts/fleet-status.sh` (new, ~30 lines)

**Implementation:**

```bash
#!/usr/bin/env bash
# scripts/fleet-status.sh — fleet dashboard CLI.
# Thin wrapper that delegates to monitoring/fleet_dashboard.py.
#
# Usage:
#   ./scripts/fleet-status.sh                       # markdown, all enabled projects
#   ./scripts/fleet-status.sh --format json         # machine-readable
#   ./scripts/fleet-status.sh --project dev-platform
#   ./scripts/fleet-status.sh --registry <path>     # override registry path (tests)
#   ./scripts/fleet-status.sh --help

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DASHBOARD="${REPO}/monitoring/fleet_dashboard.py"

if [[ ! -f "${DASHBOARD}" ]]; then
    echo "ERROR: dashboard not found at ${DASHBOARD}" >&2
    exit 1
fi

# Pass args through. Python script handles --help.
exec python3 "${DASHBOARD}" "$@"
```

Mirrors [scripts/report.sh](../scripts/report.sh)'s structure — no duplicated help, no env-var injection, just `exec`-through.

**Consumer Audit:** `scripts/*.sh` allow-list already covers; confirm via `git check-ignore -v` post-create.

**Acceptance Test:**

```bash
test -x scripts/fleet-status.sh
bash -n scripts/fleet-status.sh

# Help delegates to Python
./scripts/fleet-status.sh --help | grep -q "Fleet Dashboard"

# Full markdown dashboard
./scripts/fleet-status.sh | head -8

# JSON
./scripts/fleet-status.sh --format json | python3 -c "import json, sys; json.load(sys.stdin); print('JSON OK')"
```

### Change 4: `tests/fleet-dashboard/run.sh` — fixture suite

**Problem:** `fleet_dashboard.py` queries git + filesystem + `check_spec_taxonomy.sh` — every query is a regression surface. A mock-project-tree fixture exercises markdown rendering + JSON shape + each per-project query path WITHOUT touching real projects.

**File:** `tests/fleet-dashboard/run.sh` (new, ~150 lines) + `tests/fleet-dashboard/fixtures/registry.json` (mock registry pointing at the test's mock-project tree)

**Implementation:**

Source `tests/helpers/assert.sh` AND `tests/helpers/mock-project-tree.sh` (Change 1). In `mktemp -d`, set up 4 mock projects with varied state:

- `pass-1`: clean, 1 commit, no taxonomy issue, no consumer template
- `dirty-1`: 1 commit + 2 uncommitted files
- `drift-1`: 1 commit + taxonomy violation (mock `ROADMAP.md` with killed prefix)
- `adopted-1`: 1 commit + consumer template installed

Write a fixture registry pointing at the 4 mock projects. Then invoke the dashboard against that registry.

Required assertions (≥ 8):

1. **Python syntax clean** — `python3 -c "import ast; ast.parse(...)"`
2. **`--help` renders** without git/filesystem invocations
3. **Markdown render against mock registry** — output has the `# Fleet Dashboard` title + table with 4 rows
4. **JSON render against mock registry** — parses; `projects` array of length 4; every entry has all 9 required fields
5. **Single-project filter** (`--project pass-1`) returns a 1-row table
6. **Uncommitted count surfaces** — dirty-1's row shows `2` in the Uncommitted column
7. **Taxonomy DRIFT surfaces** — drift-1's row shows `DRIFT` in the Taxonomy column
8. **Adoption flag surfaces** — adopted-1's row shows the consumer-template adoption marker (e.g. `✓` or `installed`)
9. **Concurrency works** — runtime against 4 mock projects < 2s wall time (validates the ThreadPoolExecutor isn't running sequentially)
10. **Missing-registry gate** — `--registry /nonexistent` exits non-zero with actionable error

Mock-tree setup uses the `tests/helpers/mock-project-tree.sh` helper. Cleanup via `trap`.

**Acceptance Test:**

```bash
bash tests/fleet-dashboard/run.sh
# Expect: 10 PASS / 0 FAIL

# Auto-discovered by gate_fast.sh per the v0.4 contract
./scripts/gate_fast.sh 2>&1 | grep -q "tests/fleet-dashboard/run.sh"

# Gate count: 90 → 100 (+10 fleet-dashboard assertions)
./scripts/gate_fast.sh 2>&1 | tail -3 | grep -q "100 PASS"
```

---

## Post-merge step (deferred, in spec — runs after PR squash-merges)

**Verify dashboard against live state.** Run `./scripts/fleet-status.sh` and eyeball the markdown output against expected state for the 5 active projects. Confirm:

- Last-commit dates match `git log -1` per project
- Branches match `git branch --show-current` per project
- Uncommitted counts match `git status --porcelain | wc -l` per project
- Taxonomy column is OK for all 5 (Phase 1's live sweep already showed no violations)
- dev-platform-gate column is `self` for dev-platform, `—` for everyone else (no consumer has adopted the template yet)

Capture the output for the planning.md "Recently shipped" entry.

No release tag cut (that's Phase 4's job).

---

## What NOT to Do

- **Do NOT name fixture subdirectories `projects/`** under `tests/<suite>/fixtures/`. The unanchored `.gitignore:132 projects/` excludes them. Use `mock-projects/` per the v0.8 Phase 1 lesson — and prefer reusing Phase 1's existing tree where the test fixtures don't conflict.
- **Do NOT put runnable `.sh` test fixtures under `tests/<suite>/fixtures/`.** `scripts/gate_fast.sh`'s auto-discovery excludes that path explicitly, but the rule is: fixtures contain data; runners live one level up.
- **Do NOT use `pip install` or any non-stdlib dependency.** Match `monitoring/aggregator.py`'s stdlib-only approach. `requests`, `pyyaml`, `rich` — none of them.
- **Do NOT run gates as part of the dashboard.** Phase 1 owns "did the gates pass." Phase 2 owns "what's the state." Conflating them blurs the read-only semantics of the dashboard. If a user wants both, they invoke `fleet-gate.sh` then `fleet-status.sh`.
- **Do NOT modify any file under `projects/`.** Phase 2 is read-only. The Scope-rule carve-out for Phase 3's `fleet-install-template.sh` does NOT apply to Phase 2 — every git query uses `git -C <path>` to scope read-only operations to the named directory.
- **Do NOT add a `--gate` or `--with-gate` flag** that pipes through to fleet-gate.sh. Compose the scripts shell-side (`./scripts/fleet-gate.sh && ./scripts/fleet-status.sh`) rather than entangling them.
- **Do NOT auto-detect taxonomy compliance by re-implementing the regex.** Call `bash scripts/check_spec_taxonomy.sh <path>` and check the exit code. Single source of truth.
- **Do NOT block on slow git queries.** `subprocess.run(timeout=10)` on every `git` call — a hung git query in one project must not freeze the whole dashboard. Show `?` for that column if a query times out.
- **Do NOT use `concurrent.futures.ProcessPoolExecutor`.** ThreadPool is correct here — the queries are I/O-bound (subprocess + filesystem), not CPU-bound. ProcessPool would add overhead with no benefit and complicate `subprocess.run` ownership.
- **Do NOT report metrics for disabled projects** by default. The dashboard respects the registry's `enabled: true` filter, same as fleet-gate.sh. Add `--all` later if a real use case appears (deliberately out of scope for Phase 2).
- **Do NOT exceed the 200-character description in `frontmatter`** — N/A for this Spec (no slash command).

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `tests/helpers/mock-project-tree.sh` | New | Shared Bash helper for Phase 2+ test suites — init, commit, dirty, taxonomy-violation, install-template functions |
| `monitoring/fleet_dashboard.py` | New | ~200-line Python aggregator. Reads registry, runs concurrent per-project queries, emits markdown or JSON |
| `scripts/fleet-status.sh` | New | ~30-line Bash wrapper delegating to fleet_dashboard.py |
| `tests/fleet-dashboard/run.sh` | New | 10-assertion suite using the mock-project-tree helper |
| `tests/fleet-dashboard/fixtures/registry.json` | New | Mock registry pointing at 4 mock projects (pass / dirty / drift / adopted) |

No `.gitignore` extension needed — every file type already in the allow-list:

- `tests/**/*.sh` covers run.sh + mock-project-tree.sh
- `tests/**/*.json` covers the fixture registry
- `monitoring/**/*.py` covers fleet_dashboard.py
- `scripts/*.sh` covers fleet-status.sh

Consumer Audit reduces to confirming `git check-ignore -v` on every new file.

## Implementation Order

1. **Change 1** (mock-project-tree.sh helper) — ship first; downstream tests source it.
2. **Change 2** (fleet_dashboard.py) — main deliverable; depends on registry from Phase 1.
3. **Change 3** (fleet-status.sh wrapper) — depends on Change 2 existing.
4. **Change 4** (tests + fixture registry) — depends on Changes 1+2+3.
5. **Local verification** — `bash tests/fleet-dashboard/run.sh` → 10/10, then `./scripts/gate_fast.sh` → 100/0/0.
6. **Post-merge** — live dashboard run + planning.md "Recently shipped" entry capture.

## Verification Checklist

- [ ] `tests/helpers/mock-project-tree.sh` exists, bash-syntax clean, helper functions smoke-test successfully
- [ ] `monitoring/fleet_dashboard.py` exists, python-ast clean, `--help` renders without git invocations
- [ ] `python3 monitoring/fleet_dashboard.py` (live registry) renders markdown table with 5+ rows
- [ ] `python3 monitoring/fleet_dashboard.py --format json` produces parseable JSON with `projects` array
- [ ] `python3 monitoring/fleet_dashboard.py --project dev-platform` filters to 1-row output
- [ ] `python3 monitoring/fleet_dashboard.py --registry /nonexistent` exits non-zero with actionable error
- [ ] `scripts/fleet-status.sh` exists, executable, bash-syntax clean
- [ ] `./scripts/fleet-status.sh --help` delegates correctly to Python
- [ ] `bash tests/fleet-dashboard/run.sh` → 10 PASS / 0 FAIL
- [ ] `./scripts/gate_fast.sh` → **100 PASS** / 0 FAIL / 0 SKIP (was 90 + 10 fleet-dashboard assertions)
- [ ] `./scripts/check_spec_taxonomy.sh` clean
- [ ] No file under `projects/` modified (Scope rule respected; Phase 2 is read-only)
- [ ] Consumer Audit: every new file `git check-ignore -v`'d, all show re-include rules
- [ ] **Post-merge:** `./scripts/fleet-status.sh` against live registry surfaces realistic state (5 projects, accurate last-commit dates, accurate uncommitted counts)

## Out of Scope (Future Specs)

- **Telemetry integration** — feeding fleet_gate_run + report.sh metrics into the dashboard. Out of Phase 2; a future enhancement after v0.8 ships.
- **Per-project gate-state** in the dashboard (PASS/FAIL/TIMEOUT from the last fleet-gate run). Belongs in a future spec that decides where the per-project gate-state cache lives (currently transient under `/tmp/fleet-gate.<timestamp>/`).
- **Auto-refresh / watch mode** — `./scripts/fleet-status.sh --watch` (continuously polling). Out of scope; users invoke on demand.
- **Web UI** — JSON output is the API; consumers can build their own UI. dev-platform stays CLI-first.
- **Notification on drift** — Slack / email / Discord webhook when a project crosses a threshold (e.g., uncommitted count > 10). Out of scope.
- **Cross-project diff visualization** — show what changed since last commit across the fleet. Speculative — defer until a real use case lands.

## Notes for Implementation

- **Reuse Phase 1's mock-project tree pattern** but DO NOT name the fixture dir `projects/`. Use `tests/fleet-dashboard/fixtures/mock-projects/{pass-1,dirty-1,drift-1,adopted-1}/` OR run setup in `mktemp -d` (preferred — keeps the suite hermetic and the tracked file count low).
- **The shared helper at `tests/helpers/mock-project-tree.sh`** ships in this Phase. Phase 3 and Phase 4's tests reuse it (no duplication).
- **`git -C <path>` is the read-only way** to query a remote working tree. Never `cd` (which has session-state side effects).
- **Subprocess timeout** is 10s per query. The dashboard's overall budget is < 2s for 5 projects when queries succeed; timeouts are exceptional and surface as `?` in the markdown column.
- **`dev_platform_gate_installed` field**: `"self"` for dev-platform (it IS the gate); `True` if `.github/workflows/dev-platform-gate.yml` exists in the project; `False` otherwise. Renders as `self` / `✓` / `—` in markdown.
- **Last-commit age formatting**: `<YYYY-MM-DD> (<N>d)` where N is `(now - last_commit).days`. For commits today: `(today)` instead of `(0d)`.
- **Branch column truncation**: max 20 chars; longer branches get `…` suffix. Today's longest active branch (`v0.8/phase-1-registry-fleet-gate`) is 32 chars; renders as `v0.8/phase-1-registr…`.
- **No `console.log` equivalent in Python**: don't `print()` debug output to stdout — that pollutes the JSON output. Use `sys.stderr.write(...)` for diagnostic output.
- **The argparse robustness pattern from v0.7 Phase 4** applies: every value-taking flag explicit, missing value → actionable error + exit 2. Python's `argparse` does this by default IF you declare positional/required correctly; verify by passing `--project` alone (no value).
- **`monitoring/aggregator.py` is the canonical reference** for argparse + dataclass + JSON shape. Mirror it; don't reinvent.
- **NO new gh CLI invocations** (Phase 2 doesn't touch GitHub). The gh-version-skew lesson from PR #13's /test still applies for future Phases (3 + 4 will use gh for branch protection + release queries).
