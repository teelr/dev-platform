# v0.8: Cross-project Orchestration

## Coding Specification for Implementation

## Design Philosophy

v0.8 is the first Roadmap Phase where dev-platform deliberately reaches OUT of itself. Through v0.7, the Scope rule in [CLAUDE.md](../CLAUDE.md) was absolute: dev-platform sessions never touched files under `projects/`. v0.8 walks that back — **carefully and explicitly** — for two operations: (a) **read-only** sweeps across the fleet (run each project's gate, query state, generate dashboards) and (b) **opt-in correction** of the dev-platform-CI integration files (the `dev-platform-gate.yml` consumer template + `@vX.Y` pin bumps). Per-project feature work, business-logic edits, schema migrations, and anything else stay strictly out of scope and continue to belong in their own project sessions.

The implementation pivots on a central **registry** at [monitoring/projects.json](../monitoring/projects.json) — one entry per active project listing the project path, gate command, primary language, and optional metadata. Centralized is solo-Rich-friendly and avoids touching every project to add a `.dev-platform.json` (which would itself violate the pre-v0.8 Scope rule). A team-scale future could migrate to per-project manifests in v0.9 or later; for today's 5–8 active projects, a single JSON file is the right granularity. The reading-rule precedent: dev-platform already maintains lists about other projects ([extensions/vscode/server-extensions.json](../extensions/vscode/server-extensions.json), [.github/workflows/](../.github/workflows/)) — adding a fleet registry is the same shape.

Per the per-Spec-Phase strategy locked in PR #9, v0.8 ships across **4 PRs** (one per Spec Phase). The Scope-rule carve-out lands in Phase 3 (the first mutating Phase), NOT in Phase 1 — Phases 1+2 are read-only and don't need the rule change. Phase 4 (version-pin tracking) is sized small because there are zero consumer projects pinning `@v0.7` yet (the tag cut today); the tracking infrastructure ships now, the consumer adoption happens later. Per the workflow-extension rule from PR #9, every Phase explicitly names its **post-merge** step — Phase 1's is "run the first fleet sweep against real projects", Phase 2's is "verify dashboard against live state", Phase 3's is "deploy template into 1–2 projects opt-in", Phase 4's is "audit current pins". v0.8 release tag cuts at Phase 4 merge.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/fleet-gate.sh`, `scripts/fleet-status.sh`, `scripts/fleet-install-template.sh`, `scripts/fleet-pins.sh` | Bash | Entry-point pattern (`install.sh`, `gate_fast.sh`, `sync-vscode.sh`, `sync-milestones.sh`). Spawn child processes (per-project gates), parse `git` output, write to log files. No CPU/AI/network workload. |
| `monitoring/fleet_dashboard.py`, `monitoring/fleet_pins.py` | Python | Parallel to [monitoring/aggregator.py](../monitoring/aggregator.py) from v0.5. JSON parsing, aggregation, markdown rendering — Python's strength. Argparse, dataclasses, no `pip install` deps. |
| `monitoring/projects.json` | JSON | Registry format. Read by both the Bash entry-points and the Python aggregators — JSON is the lingua franca. |
| `tests/fleet-*/run.sh` + `tests/fleet-*/fixtures/mock-bin/git`, `tests/fleet-*/fixtures/mock-bin/sh-runner` | Bash | Test-suite pattern locked in v0.4; mock-binary pattern locked in v0.6. |

No new code-component category triggers the Language Matrix elsewhere. v0.8 is pure orchestration on top of existing project-side workloads (which keep their own language choices per the matrix in their own repos).

## Overview

1. **Phase 1:** Registry + Fleet Gate (Changes 1–3)
2. **Phase 2:** Fleet Dashboard (Changes 4–6)
3. **Phase 3:** Opt-in Drift Correction + Scope Carve-out (Changes 7–10)
4. **Phase 4:** Consumer Version-Pin Tracking (Changes 11–12)

**Demo when v0.8 ships:**

- `./scripts/fleet-gate.sh` — runs each enabled project's gate in parallel with timeouts; emits a fleet-level PASS/FAIL summary. Reads `monitoring/projects.json` for per-project gate commands.
- `./scripts/fleet-status.sh` — markdown dashboard showing per-project last-commit recency, current branch, `gate-fast` CI state on `main`, taxonomy compliance, dev-platform-gate adoption status.
- `./scripts/fleet-install-template.sh --project <name>` — copies `extensions/github-actions/dev-platform-gate.yml` into that project's `.github/workflows/`. Dry-run by default; `--apply` writes. The ONLY mutation v0.8 performs against `projects/`.
- `./scripts/fleet-pins.sh` — surveys every consumer's `dev-platform-gate.yml` to report which `@vX.Y` tag they pin. Identifies projects on stale pins.

---

## Phase 1: Registry + Fleet Gate

### Change 1: `monitoring/projects.json` — fleet registry

**Problem:** Every cross-project operation v0.8 introduces — gate sweep, status query, template install — needs to know which projects exist, where they live, and how to invoke their gate. Without a single source of truth, every script would re-discover this on its own (and disagree). The registry centralizes the answer.

**File:** `monitoring/projects.json` (new)

**Implementation:**

JSON array of project entries. Each entry has `name` (the directory name under `projects/`), `path` (absolute or `projects/<name>`-relative), `gate_cmd` (the exact shell command to run from inside the project root), `primary_language` (informational; matches the Language Matrix), `enabled` (skip if false — e.g., stale projects), and optional `notes`.

Seed entries (verified against current `projects/` directory):

```json
[
  {
    "name": "dev-platform",
    "path": ".",
    "gate_cmd": "./scripts/gate_fast.sh",
    "primary_language": "bash",
    "enabled": true,
    "notes": "self — included so the fleet sweep is symmetric"
  },
  {
    "name": "atlas",
    "path": "projects/atlas",
    "gate_cmd": "./scripts/gate_fast.sh",
    "primary_language": "python",
    "enabled": true
  },
  {
    "name": "kermit",
    "path": "projects/kermit",
    "gate_cmd": "make check",
    "primary_language": "python",
    "enabled": true
  },
  {
    "name": "kermit-pa",
    "path": "projects/kermit-pa",
    "gate_cmd": "./scripts/gate.sh fast",
    "primary_language": "python",
    "enabled": true
  },
  {
    "name": "keystone",
    "path": "projects/keystone",
    "gate_cmd": "./scripts/gate_fast.sh",
    "primary_language": "go",
    "enabled": true
  }
]
```

Stale projects (`richteel-portal`, `RICH_NVR`, `SQRL`, `OPIE`, etc.) are intentionally NOT in the initial registry — they can be added later with `enabled: false` if Rich wants the dashboard to surface their last-commit recency without including them in gate sweeps. Adding/removing entries is a one-line edit; the registry is the source of truth.

**Acceptance Test:**

```bash
test -f monitoring/projects.json
python3 -c "import json; data = json.load(open('monitoring/projects.json')); assert isinstance(data, list); assert all('name' in e and 'gate_cmd' in e for e in data); print(f'{len(data)} projects in registry')"
# Expect: "5 projects in registry"

# Every named path exists on disk (entries reference real directories)
python3 -c "
import json, os
data = json.load(open('monitoring/projects.json'))
for e in data:
    p = e['path'] if e['path'] != '.' else '.'
    assert os.path.isdir(p), f'missing: {p}'
    print(f'OK {e[\"name\"]} -> {p}')
"

# Schema check — every entry has the required fields
jq -e 'all(. | has(\"name\") and has(\"path\") and has(\"gate_cmd\") and has(\"primary_language\") and has(\"enabled\"))' monitoring/projects.json
```

**Consumer Audit:** `monitoring/**/*.json` is already in the allow-list ([!.gitignore:96 region](../.gitignore)) — no rule extension needed. Confirm with `git check-ignore -v monitoring/projects.json` post-create.

### Change 2: `scripts/fleet-gate.sh` — read-only fleet sweep

**Problem:** Today every cross-project gate run is manual — `cd projects/atlas && ./scripts/gate_fast.sh`, then `cd projects/kermit-pa && ./scripts/gate.sh fast`, etc. As the active project count grew past 3, this stopped scaling. A fleet sweep that walks the registry, runs each gate in parallel with a per-project timeout, and emits a one-line-per-project summary is the v0.5 Monitoring equivalent at fleet scale.

**File:** `scripts/fleet-gate.sh` (new, ~130 lines)

**Implementation:**

Bash entry point. Parse args: `--project <name>` (single-project run), `--parallel <N>` (concurrency cap, default 4), `--timeout <SEC>` (per-project hard timeout, default 300), `--enabled-only` (skip `enabled: false`, default), `--all` (override; include disabled), `--help`. Reads `monitoring/projects.json` via `jq`. For each enabled entry, runs `(cd "${path}" && timeout "${timeout}" bash -c "${gate_cmd}")` in the background (up to `--parallel` at a time), captures stdout+stderr to a per-project log under `/tmp/fleet-gate.<timestamp>/`, records exit code. Aggregates results: PASS / FAIL / TIMEOUT / SKIP. Final summary table + per-failing-project log path.

Pattern reuses the v0.4 [scripts/gate_fast.sh](../scripts/gate_fast.sh)'s aggregation discipline (PASS/FAIL counters; exit non-zero if any FAIL) but at the fleet level. Telemetry: emit a `fleet_gate_run` event per sweep into `~/.claude/dev-platform-telemetry.log` matching v0.5's schema (one event per fleet sweep, fields: outcome, pass_count, fail_count, skip_count, project_count, duration_s).

Output format (markdown table to stdout):

```text
=== fleet gate ===

Registry: monitoring/projects.json (5 enabled)
Parallel: 4
Timeout:  300s

| Project        | Result   | Duration |
| -------------- | -------- | -------- |
| dev-platform   | PASS     | 17s      |
| atlas          | PASS     | 3m12s    |
| kermit         | FAIL     | 1m04s    |
| kermit-pa      | TIMEOUT  | 5m00s    |
| keystone       | PASS     | 28s      |

=== summary ===
3 PASS  1 FAIL  1 TIMEOUT  0 SKIP  (5m12s total)

Failing logs:
  kermit:    /tmp/fleet-gate.20260512-093200/kermit.log
  kermit-pa: /tmp/fleet-gate.20260512-093200/kermit-pa.log

FLEET GATE: FAIL
```

Exit codes: 0 if all enabled gates PASS; 1 if any FAIL/TIMEOUT; 2 on setup error (missing registry, jq absent).

**Acceptance Test:**

```bash
test -x scripts/fleet-gate.sh
bash -n scripts/fleet-gate.sh

# --help renders without launching any gates
./scripts/fleet-gate.sh --help | grep -q "fleet gate"

# Required-tools gate
PATH=/tmp ./scripts/fleet-gate.sh 2>&1 | grep -qE "jq required|registry not found"

# Single-project run against a known-passing project (dev-platform itself)
./scripts/fleet-gate.sh --project dev-platform 2>&1 | tee /tmp/fg-self.out
grep -q "FLEET GATE: PASS" /tmp/fg-self.out
rm -f /tmp/fg-self.out

# Full sweep (real-world; will surface real project state, may FAIL or TIMEOUT)
./scripts/fleet-gate.sh --parallel 2 --timeout 60 2>&1 | head -30
# Expect: tabular output, summary line, exit code reflects pass/fail
```

### Change 3: `tests/fleet-gate/` fixture suite

**Problem:** `fleet-gate.sh` parses JSON, spawns subprocesses, applies timeouts, aggregates results — every one of those is a place to regress. A mock-project-tree fixture (each "project" is a small dir with a scripted gate stub) exercises every code path without touching real projects.

**File:** `tests/fleet-gate/run.sh` (new), `tests/fleet-gate/fixtures/registry-good.json`, `tests/fleet-gate/fixtures/registry-mixed.json`, `tests/fleet-gate/fixtures/mock-projects/{pass-1,fail-1,timeout-1,disabled-1}/gate.sh` (4 mock projects)

**Implementation:**

Mock project tree under `tests/fleet-gate/fixtures/mock-projects/`:
- `pass-1/gate.sh` — exits 0, prints "OK"
- `fail-1/gate.sh` — exits 1, prints "FAIL: simulated"
- `timeout-1/gate.sh` — `sleep 999` then exit 0 (never reached under a short test timeout)
- `disabled-1/gate.sh` — exits 0 (would PASS if invoked; the test confirms it's NOT invoked when enabled: false)

Two registry fixtures pointing at this mock tree:
- `registry-good.json` — only `pass-1`
- `registry-mixed.json` — all 4 (pass-1 enabled, fail-1 enabled, timeout-1 enabled, disabled-1 disabled)

Runner asserts (≥ 10 assertions):

1. `bash -n` syntax clean
2. `--help` renders without invocations
3. Required-tools gate (PATH=/tmp triggers jq-not-found)
4. Single-project `--project pass-1` against `registry-good.json` → exit 0, output contains "PASS  pass-1"
5. Mixed sweep against `registry-mixed.json` with `--timeout 2` → exit non-zero (some FAIL)
6. Mixed sweep summary line contains the expected count: 1 PASS + 1 FAIL + 1 TIMEOUT + 1 SKIP
7. The disabled-1 project is NOT in the output (verifies `enabled: false` skip)
8. The fail-1 log path is referenced in the output (per-failing-project log)
9. Telemetry event emitted: a JSONL line ending with `event=fleet_gate_run` appears in the test's mock telemetry log file
10. `--all` flag overrides `enabled: false` and INCLUDES disabled-1 in the sweep

Test runner uses `mktemp -d` + `trap` cleanup like every v0.4+ test runner.

**Acceptance Test:**

```bash
test -x tests/fleet-gate/run.sh
bash tests/fleet-gate/run.sh
# Expect: 10 PASS / 0 FAIL

# Auto-discovered by gate_fast.sh
./scripts/gate_fast.sh 2>&1 | grep -q "tests/fleet-gate/run.sh"

# Gate count grows 78 -> 88 (10 new assertions)
./scripts/gate_fast.sh 2>&1 | tail -3 | grep -q "88 PASS"
```

---

## Phase 2: Fleet Dashboard

### Change 4: `monitoring/fleet_dashboard.py` — per-project state aggregator

**Problem:** Phase 1 answers "did the gates pass?" Phase 2 answers "what's the current state of the fleet?" Last-commit recency (when did this project last change?), current branch (is anyone in flight?), taxonomy compliance (does this project pass `check_spec_taxonomy.sh`?), and dev-platform-gate adoption (does it have the consumer template installed yet?). All read-only, all derivable from the registry + git + filesystem.

**File:** `monitoring/fleet_dashboard.py` (new, ~200 lines)

**Implementation:**

Python script structured like [monitoring/aggregator.py](../monitoring/aggregator.py). Argparse: `--format markdown|json`, `--project <name>` (single-project view), `--log <path>` (override telemetry log path for tests), `--registry <path>` (override registry path for tests). Reads `monitoring/projects.json`. For each enabled entry, runs (in parallel via `concurrent.futures.ThreadPoolExecutor`):
- `git log -1 --format=%ci %H %s` to capture last-commit timestamp + sha + subject
- `git rev-parse --abbrev-ref HEAD` for current branch
- `git status --porcelain | wc -l` for uncommitted file count
- `bash /home/rich/dev/scripts/check_spec_taxonomy.sh <project-path>` (silent; exit code = taxonomy compliance)
- `test -f <project-path>/.github/workflows/dev-platform-gate.yml` for adoption flag

Markdown output (default):

```markdown
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

JSON output (machine-readable, for piping to dashboards):

```json
{
  "generated_at": "2026-05-12T09:32:00Z",
  "registry_path": "monitoring/projects.json",
  "projects": [
    {"name": "dev-platform", "branch": "main", "last_commit_iso": "2026-05-11T15:31:32Z", "last_commit_age_days": 1, "uncommitted_count": 0, "taxonomy_ok": true, "dev_platform_gate_installed": "self"},
    ...
  ]
}
```

Single-source-of-truth: this script doesn't run gates (Phase 1's job); it just queries cheap state. Total per-project query time should be <500ms.

**Acceptance Test:**

```bash
test -f monitoring/fleet_dashboard.py
python3 -c "import ast; ast.parse(open('monitoring/fleet_dashboard.py').read())" && echo "OK syntax"

# Help works
python3 monitoring/fleet_dashboard.py --help | grep -q "Fleet Dashboard"

# Markdown output (real-world)
python3 monitoring/fleet_dashboard.py | head -10
# Expect: title, table, ~5 rows

# JSON output
python3 monitoring/fleet_dashboard.py --format json | python3 -c "import json, sys; d=json.load(sys.stdin); assert 'projects' in d and isinstance(d['projects'], list); print(f'{len(d[\"projects\"])} projects')"
```

### Change 5: `scripts/fleet-status.sh` — Bash CLI wrapper

**Problem:** Power users invoke Python aggregators via `python3 monitoring/fleet_dashboard.py ...`. Most users expect a Bash entry-point matching the rest of the dev-platform scripts (`./scripts/<verb>.sh`). The wrapper is a thin redirect.

**File:** `scripts/fleet-status.sh` (new, ~50 lines)

**Implementation:**

Mirrors [scripts/report.sh](../scripts/report.sh)'s structure exactly — delegate to a Python aggregator after checking it exists. Args pass through: `--format markdown|json`, `--project <name>`, `--registry <path>`, `--help`.

```bash
#!/usr/bin/env bash
# scripts/fleet-status.sh — fleet dashboard CLI.
# Thin wrapper that delegates to monitoring/fleet_dashboard.py.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DASHBOARD="${REPO}/monitoring/fleet_dashboard.py"

if [[ ! -f "${DASHBOARD}" ]]; then
    echo "ERROR: dashboard not found at ${DASHBOARD}" >&2
    exit 1
fi

# Pass args through.
exec python3 "${DASHBOARD}" "$@"
```

Help is handled by the Python script (no duplication).

**Acceptance Test:**

```bash
test -x scripts/fleet-status.sh
bash -n scripts/fleet-status.sh

# Help renders (via the Python script)
./scripts/fleet-status.sh --help | grep -q "Fleet Dashboard"

# Full markdown dashboard
./scripts/fleet-status.sh | head -8
```

### Change 6: `tests/fleet-dashboard/` fixture suite

**Problem:** `fleet_dashboard.py` queries git, the filesystem, and (later) telemetry — every query is a place to regress. A mock-project-tree fixture exercises the format-rendering + per-project-state code paths without touching real projects.

**File:** `tests/fleet-dashboard/run.sh` (new), fixtures matching Change 3's mock-project shape

**Implementation:**

Reuse `tests/fleet-gate/fixtures/mock-projects/*` if practical (each project dir has a `.git` and minimal state). Add per-project git state as needed for the dashboard's queries — `git init`, one commit per fixture-project so `git log -1` returns something.

Mock-tree setup happens in the runner (`git init` + `git commit --allow-empty -m "fixture"` per fixture project, inside `mktemp -d`). Reusable helper at `tests/helpers/mock-project-tree.sh` so Phase 3's tests can also use it.

Required assertions (≥ 8):

1. `python3 -c "import ast; ast.parse(...)"` — script parses
2. `--help` renders without git invocations
3. Markdown render against a 3-project fixture tree → table has 3 rows
4. JSON render → parses, contains `projects` array of length 3
5. `--project pass-1` → single-row table
6. Project with uncommitted files → uncommitted count > 0 in output
7. Project with taxonomy violation (mock spec under `tasks/` with killed term) → `DRIFT` in table cell
8. Project with consumer template installed (mock `.github/workflows/dev-platform-gate.yml`) → "✓" or path-segment in adoption column

**Acceptance Test:**

```bash
bash tests/fleet-dashboard/run.sh
# Expect: 8 PASS / 0 FAIL

./scripts/gate_fast.sh 2>&1 | grep -q "tests/fleet-dashboard"
# Gate count: 88 -> 96
```

---

## Phase 3: Opt-in Drift Correction + Scope Carve-out

### Change 7: Update Scope rule in `/home/rich/dev/CLAUDE.md`

**Problem:** Pre-v0.8, the Scope rule's prose is absolute: "no edits, commits, or fixes to project code from here." Phase 3 introduces a narrowly-scoped exception (deploy the dev-platform-CI integration files). The exception MUST land IN the rule, not just IN the spec — future sessions don't read this spec, they read CLAUDE.md.

**File:** `/home/rich/dev/CLAUDE.md` (existing, modify the "Scope — dev-platform Is For The Environment, Not The Projects" section)

**Implementation:**

Locate the existing Scope-rule prose (around the "Behavioral rule for the assistant" paragraph; the rule says "STOP and ask the user to switch to that project's working directory — never silently reach into projects/ from this session"). Add a new explicit carve-out paragraph AFTER it:

```markdown
**Exception — v0.8 fleet orchestration (mutating subset):** v0.8's
`scripts/fleet-install-template.sh` (and any future v0.8+ script
documented here) IS allowed to write the **dev-platform-CI
integration files** into a project's `.github/workflows/` directory.
Specifically: `dev-platform-gate.yml` from
`extensions/github-actions/`, and any future v0.8-introduced
template equivalents. ALL other writes against `projects/` remain
forbidden from dev-platform sessions: no source code edits, no
schema changes, no business-logic fixes, no spec authorship, no
test additions, no commits made on behalf of a project. The
mutation must be opt-in (explicit `--apply` flag) and reversible
(write the same file the user could `cp` manually). The carve-out
exists because per-project install of the consumer template is
exactly the v0.8 use case that doesn't fit either "stay out
entirely" or "open a session in the project" — adopting the
dev-platform CI integration is a dev-platform operation, not a
per-project feature decision.
```

Update the "Why this rule exists" paragraph to mention the v0.8 carve-out explicitly so the rationale stays clear.

**Acceptance Test:**

```bash
grep -A 3 "v0.8 fleet orchestration" /home/rich/dev/CLAUDE.md | head -5
# Expect: the new exception paragraph appears

./scripts/check_spec_taxonomy.sh  # CLAUDE.md is not a spec; the check shouldn't care, just confirm gate-clean
./scripts/gate_fast.sh             # Gate still passes after CLAUDE.md edit
```

### Change 8: `scripts/fleet-install-template.sh` — opt-in consumer adoption

**Problem:** The v0.7 Phase 2 consumer template at [extensions/github-actions/dev-platform-gate.yml](../extensions/github-actions/dev-platform-gate.yml) is copy-paste-ready, but copy-paste is manual per-project work. A fleet-level script that walks the registry, checks adoption state, and writes the template into projects opting in (via `--apply --project <name>`) makes the integration scale.

**File:** `scripts/fleet-install-template.sh` (new, ~120 lines)

**Implementation:**

Bash. Args: `--project <name>` (required; explicit per-project opt-in — NO `--all`), `--apply` (default is dry-run), `--force` (overwrite existing template; default is refuse-to-clobber), `--pin <vX.Y>` (override the `@v0.7` default to a different tag), `--help`. Reads `monitoring/projects.json` to resolve `<name>` → path.

Algorithm:

1. Resolve project from registry. Error if not found or `enabled: false`.
2. Read the source template at `extensions/github-actions/dev-platform-gate.yml`.
3. Optional `@vX.Y` rewrite via sed if `--pin` is set.
4. Target path: `${project_path}/.github/workflows/dev-platform-gate.yml`.
5. Pre-flight: if target exists and `--force` not set → refuse with actionable error.
6. Dry-run (default): print "Would write ${bytes} bytes to ${target}"; show diff against existing if any.
7. `--apply`: write the file. Mirror [scripts/install.sh](../scripts/install.sh)'s refuse-to-clobber discipline.

The script CAN write to `projects/<X>/.github/workflows/` per Change 7's carve-out. The script CANNOT write anywhere else under `projects/` — enforced by hard-coding the target path computation. The user-visible contract is: this script writes exactly ONE filename, in exactly ONE directory, ever.

**Acceptance Test:**

```bash
test -x scripts/fleet-install-template.sh
bash -n scripts/fleet-install-template.sh
./scripts/fleet-install-template.sh --help | grep -q "fleet-install-template"

# Dry-run against a known-non-adopted project (mock or live)
./scripts/fleet-install-template.sh --project atlas
# Expect: dry-run output showing the planned write

# Refuse-to-clobber test (mock setup)
# Create a tmpdir with an existing dev-platform-gate.yml, run the script with --apply (no --force) against it; expect exit 1
```

### Change 9: `tests/fleet-install/` fixture suite

**Problem:** The install script writes into `projects/*/.github/workflows/` — the only mutating operation v0.8 performs against projects. It must NEVER write outside that path, and it must respect the refuse-to-clobber discipline. Hermetic tests with a mock project tree prove both.

**File:** `tests/fleet-install/run.sh` (new)

**Implementation:**

Mock project tree under `mktemp -d`. Mock registry pointing at the tmpdir. Required assertions (≥ 8):

1. `bash -n` syntax clean
2. `--help` renders
3. `--project` required (no args → error + non-zero)
4. Dry-run mode produces no file write (after invocation, target file does NOT exist)
5. `--apply` writes the file at the expected target path
6. Re-running `--apply` without `--force` refuses (existing target → exit 1)
7. `--apply --force` overwrites
8. The script REFUSES to write outside `.github/workflows/` — try `--project` pointing at an entry whose path is bogus; expect setup error
9. `--pin v0.6` produces a file with `@v0.6` instead of `@v0.7`
10. Telemetry event `fleet_install_template` emitted to mock telemetry log on `--apply`

**Acceptance Test:**

```bash
bash tests/fleet-install/run.sh
# Expect: 10 PASS / 0 FAIL

./scripts/gate_fast.sh 2>&1 | grep -q "tests/fleet-install"
# Gate count: 96 -> 106
```

### Change 10: Document the carve-out in [docs/CI-INTEGRATION.md](../docs/CI-INTEGRATION.md)

**Problem:** Phase 2's `CI-INTEGRATION.md` instructs users to manually `curl` the template into their project. With Change 8 shipped, there's now an automated path. The guide should mention it — without removing the manual instructions (they remain valid for non-Rich consumers).

**File:** `docs/CI-INTEGRATION.md` (existing, append a new section)

**Implementation:**

Add a section "Automated install (Rich's own projects)" after "Adoption — 3 steps":

```markdown
## Automated install (Rich's own projects)

If your project is in dev-platform's [project registry](../monitoring/projects.json),
you can use the v0.8 fleet helper instead of the manual `curl`:

​```bash
# From the dev-platform repo root
./scripts/fleet-install-template.sh --project <name>           # dry-run
./scripts/fleet-install-template.sh --project <name> --apply   # write
./scripts/fleet-install-template.sh --project <name> --apply --pin v0.7  # specify tag
​```

This is functionally identical to the manual `curl` flow — same file, same
target path. The helper just walks the registry so you don't repeat the
project path each time. Per the v0.8 Scope-rule carve-out, this is the
ONLY write the fleet helper performs against your project; everything else
in this guide stays manual.
```

**Acceptance Test:**

```bash
grep -q "Automated install" docs/CI-INTEGRATION.md
grep -q "fleet-install-template" docs/CI-INTEGRATION.md
```

---

## Phase 4: Consumer Version-Pin Tracking

### Change 11: `monitoring/fleet_pins.py` — pin survey + `scripts/fleet-pins.sh`

**Problem:** Once consumer projects adopt the dev-platform-gate template, each pins a specific `@vX.Y` tag. As dev-platform releases new versions (v0.8, v0.9, v1.0+), some consumers will lag — pinning `@v0.7` when `@v0.9` is current. A pin survey identifies the lag without touching project code.

**File:** `monitoring/fleet_pins.py` (new, ~120 lines), `scripts/fleet-pins.sh` (new, ~20 lines wrapper matching `fleet-status.sh`)

**Implementation:**

For each enabled project in the registry, check whether `<project>/.github/workflows/dev-platform-gate.yml` exists. If yes, grep for `taxonomy-check.yml@v` and extract the pinned tag. Build a markdown table:

```markdown
# Fleet Pins

Generated: 2026-05-12T09:32:00Z
Latest dev-platform release: v0.8

| Project      | Pin     | Latest | Status   |
| ------------ | ------- | ------ | -------- |
| dev-platform | (self)  | v0.8   | self     |
| atlas        | v0.7    | v0.8   | ⚠ STALE  |
| kermit       | —       | v0.8   | NOT INSTALLED |
| kermit-pa    | v0.8    | v0.8   | ✓ CURRENT |
| keystone     | v0.7    | v0.8   | ⚠ STALE  |
```

"Latest dev-platform release" is queried via `gh release list --limit 1 --json tagName` (the most recent tag).

JSON output for machine consumption. Bash wrapper at `scripts/fleet-pins.sh` mirrors `scripts/fleet-status.sh`.

**Acceptance Test:**

```bash
test -f monitoring/fleet_pins.py
test -x scripts/fleet-pins.sh
./scripts/fleet-pins.sh --help | grep -q "Fleet Pins"

# Real-world run (depending on how many projects have adopted v0.7 at run time)
./scripts/fleet-pins.sh | head -10
```

### Change 12: `tests/fleet-pins/` fixture suite

**Problem:** The pin survey grep-parses YAML — brittle. A fixture suite catches regex regressions before they ship.

**File:** `tests/fleet-pins/run.sh` (new)

**Implementation:**

Mock-project tree with three projects: one with `@v0.7` pinned, one with `@v0.8` pinned, one with no consumer template. Mock `gh` (`tests/fleet-gate/fixtures/mock-bin/gh` from Phase 1 is reusable — same pattern as v0.7 Phase 4's milestone-sync) to return a canned "latest release" response.

Required assertions (≥ 6):

1. `python3 -c "import ast; ast.parse(...)"` clean
2. `--help` renders
3. Real release queried via mock-gh returns `v0.8` (mock-controllable)
4. Project with `@v0.7` reports STALE
5. Project with `@v0.8` reports CURRENT
6. Project without template reports NOT INSTALLED
7. JSON output parses

**Acceptance Test:**

```bash
bash tests/fleet-pins/run.sh
# Expect: 6 PASS / 0 FAIL

./scripts/gate_fast.sh 2>&1 | grep -q "tests/fleet-pins"
# Gate count: 106 -> 112
```

---

## Post-merge step (deferred, in spec — runs after EACH Phase's PR squash-merges)

Each Spec Phase has its own post-merge:

**Phase 1 post-merge:** After PR squash-merges, run `./scripts/fleet-gate.sh` against the live `projects/` tree. Verify it walks the registry, runs each gate in parallel, surfaces the actual PASS/FAIL state of the fleet today. Capture the output for the planning.md "Recently shipped" entry.

**Phase 2 post-merge:** Run `./scripts/fleet-status.sh` and verify the live dashboard matches expected state for the 5 active projects. Confirm last-commit dates align with `git log` per project.

**Phase 3 post-merge:** Adopt the dev-platform-gate template into 1–2 active consumer projects via `./scripts/fleet-install-template.sh --project <name> --apply`. Open a PR IN EACH consumer project (NOT from a dev-platform session — switch working directories) to verify the consumer adoption end-to-end. Confirm the gate-fast check runs on the next consumer PR.

**Phase 4 post-merge:** Run `./scripts/fleet-pins.sh` and verify the pin survey accurately reports state. Cut the **v0.8 release tag** at the Phase 4 merge commit. Close the v0.8 GitHub Milestone.

```bash
# Phase 4 post-merge (cuts v0.8 release):
git checkout main && git pull --ff-only
MERGE_SHA=$(git rev-parse HEAD)
gh release create v0.8 --target "${MERGE_SHA}" \
    --title "v0.8: Cross-project orchestration" \
    --notes "..."  # see Phase 4 ship notes template
gh api -X PATCH "repos/teelr/dev-platform/milestones/8" -f state=closed
./scripts/sync-milestones.sh --apply   # syncs ROADMAP "(complete)" status onto Milestone descriptions
```

---

## What NOT to Do

- **Do NOT write outside `.github/workflows/dev-platform-gate.yml`** in any v0.8 script. The Scope-rule carve-out is exactly ONE filename in exactly ONE directory. Adding a second exception requires a new spec, not a flag.
- **Do NOT auto-deploy the consumer template to all projects.** `fleet-install-template.sh` requires explicit `--project <name>` per invocation. No `--all` flag exists; never add one. Per-project adoption is an intentional, opt-in decision.
- **Do NOT run the fleet sweep automatically from any CI workflow.** The fleet gate is a manual Rich-invoked operation. Auto-running it from dev-platform's CI would burn minutes on every push to main; auto-running from a consumer's CI would re-introduce the cross-project coupling v0.8 is intentionally limited.
- **Do NOT modify any file under `projects/<name>/` other than `.github/workflows/dev-platform-gate.yml`** from a v0.8 script. The Scope-rule prohibits it; the script must hard-code the target path.
- **Do NOT skip the dry-run default on `fleet-install-template.sh`.** Tools that mutate shared state require explicit opt-in (`--apply`). Same discipline as `sync-milestones.sh`.
- **Do NOT add a "force-pull main" or "git pull --rebase" step to fleet-gate.sh.** Each project is on whatever branch the user left it on. The gate runs against the working-tree state, not a pristine `main`.
- **Do NOT include disabled projects in sweeps by default.** `enabled: false` opts a project out of all v0.8 operations; only `--all` overrides for diagnostic purposes.
- **Do NOT consolidate the 4 wrapper scripts** (`fleet-gate.sh`, `fleet-status.sh`, `fleet-install-template.sh`, `fleet-pins.sh`) **into one mega-script.** Each verb is independently invokable and matches the dev-platform entry-point pattern.
- **Do NOT add `.dev-platform.json` files to individual projects** as part of v0.8. That's a v0.9-or-later refactor; today the registry is centralized in dev-platform.
- **Do NOT add a "register a new project" interactive flow** to v0.8. New projects get scaffolded via [scripts/new-project.sh](../scripts/new-project.sh) (v0.3); v0.8 just orchestrates over already-existing projects. Adding new entries to `monitoring/projects.json` is a manual JSON edit — that's fine.
- **Do NOT skip the per-project timeout in fleet-gate.sh.** A runaway project gate (infinite loop, hung process) must not block the entire sweep. Default 300s, override with `--timeout`.
- **Do NOT use `pip install` or any non-stdlib Python dependency.** Match the existing aggregator.py pattern — stdlib only.
- **Do NOT name fixture subdirectories `projects/`** anywhere under `tests/<suite>/fixtures/`. The repo-wide `.gitignore:132` excludes `projects/` as an unanchored pattern (it matches any directory named `projects/`, at any depth). Even with `!tests/**/*.sh` in scope, gitignore rule-order makes the later `projects/` exclude win. Use `mock-projects/` (or any other name) instead. Caught at /code time during Phase 1 implementation; spec backfilled.
- **Do NOT put runnable `.sh` files under `tests/<suite>/fixtures/`** that are intended as FIXTURES (mock gates, mock binaries, mock CLI tools). `scripts/gate_fast.sh`'s auto-discovery walks `tests/<suite>/**/*.sh` and would treat fixture scripts as test runners. The exclusion `! -path "*/fixtures/*"` in `gate_fast.sh`'s find pattern (added in Phase 1 to make this contract explicit) protects the discovery from picking them up, but the contract — "test runners live at `tests/<suite>/*.sh` or `tests/<suite>/<test>/*.sh`, NEVER under `fixtures/`" — is the actual rule. Mock binaries live under `tests/<suite>/fixtures/mock-bin/` (already-handled pattern from v0.6); mock-project gates live under `tests/<suite>/fixtures/mock-projects/<X>/`.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `monitoring/projects.json` | New | Fleet registry: 5 active projects + their gate commands + enabled flag |
| `scripts/fleet-gate.sh` | New | Parallel fleet sweep with timeouts, telemetry emit |
| `tests/fleet-gate/run.sh` | New | 10-assertion suite + mock project tree |
| `tests/fleet-gate/fixtures/{registry-good,registry-mixed}.json` | New | Fixture registries |
| `tests/fleet-gate/fixtures/mock-projects/{pass-1,fail-1,timeout-1,disabled-1}/gate.sh` | New | Mock project gates |
| `monitoring/fleet_dashboard.py` | New | Per-project state aggregator (git, taxonomy, adoption flag) |
| `scripts/fleet-status.sh` | New | Bash wrapper delegating to fleet_dashboard.py |
| `tests/fleet-dashboard/run.sh` | New | 8-assertion suite |
| `tests/helpers/mock-project-tree.sh` | New | Reusable helper for mock-project setup |
| `/home/rich/dev/CLAUDE.md` | Modify | Scope-rule carve-out for v0.8 fleet operations |
| `scripts/fleet-install-template.sh` | New | Opt-in consumer-template install |
| `tests/fleet-install/run.sh` | New | 10-assertion suite |
| `docs/CI-INTEGRATION.md` | Modify | "Automated install (Rich's own projects)" section |
| `monitoring/fleet_pins.py` | New | Consumer pin survey |
| `scripts/fleet-pins.sh` | New | Bash wrapper |
| `tests/fleet-pins/run.sh` | New | 6-assertion suite |
| `tasks/dev-platform-fleet-orchestration-spec.md` | (this) | Spec |

## Implementation Order

1. **Phase 1** (Changes 1, 2, 3) — Registry + fleet sweep. Read-only; no Scope-rule change needed. Ship as PR #12.
2. **Phase 2** (Changes 4, 5, 6) — Dashboard. Read-only; depends on Phase 1's registry. Ship as PR #13.
3. **Phase 3** (Changes 7, 8, 9, 10) — Scope-rule update + opt-in template install + adoption guide section. First mutating Phase; rule change MUST land in Change 7 before Change 8. Ship as PR #14.
4. **Phase 4** (Changes 11, 12) — Pin tracking. Depends on Phase 3 (template adoption is what creates pins to track). Ship as PR #15.

Each Phase ships as its own PR per the per-Spec-Phase strategy. Phase 4 closes v0.8; release tag cuts post-merge.

## Verification Checklist

- [ ] `monitoring/projects.json` exists, valid JSON, 5+ entries, every path resolves to a real directory
- [ ] `scripts/fleet-gate.sh` runs `--help` cleanly without launching gates
- [ ] `scripts/fleet-gate.sh` against `--project dev-platform` exits 0 (self-gate passes)
- [ ] `scripts/fleet-gate.sh` full sweep produces tabular output with summary line; exit code reflects pass/fail
- [ ] `bash tests/fleet-gate/run.sh` → 10 PASS / 0 FAIL
- [ ] `monitoring/fleet_dashboard.py --format json` produces parseable JSON with `projects` array
- [ ] `monitoring/fleet_dashboard.py` markdown output renders 5+ project rows
- [ ] `scripts/fleet-status.sh --help` renders (delegates to Python)
- [ ] `bash tests/fleet-dashboard/run.sh` → 8 PASS / 0 FAIL
- [ ] `/home/rich/dev/CLAUDE.md` contains the v0.8 Scope-rule carve-out paragraph
- [ ] `scripts/fleet-install-template.sh --project <name>` dry-run shows the planned write
- [ ] `scripts/fleet-install-template.sh --project <name> --apply` writes the template into the project's `.github/workflows/dev-platform-gate.yml`
- [ ] `scripts/fleet-install-template.sh` refuses to write outside `.github/workflows/` (defensive hard-coding)
- [ ] `bash tests/fleet-install/run.sh` → 10 PASS / 0 FAIL
- [ ] `docs/CI-INTEGRATION.md` contains the "Automated install" section
- [ ] `monitoring/fleet_pins.py` accurately reports consumer pin state
- [ ] `bash tests/fleet-pins/run.sh` → 6 PASS / 0 FAIL
- [ ] `./scripts/gate_fast.sh` → 112 PASS / 0 FAIL / 0 SKIP after Phase 4 (was 78; +10+8+10+6 = 112)
- [ ] `./scripts/check_spec_taxonomy.sh` clean
- [ ] No file under `projects/<name>/` modified OTHER than `.github/workflows/dev-platform-gate.yml` (defensive grep at post-merge)
- [ ] **Post-merge (Phase 4):** v0.8 release tag cut, v0.8 Milestone closed, consumer-template installed into 1–2 active projects

## Out of Scope (Future Specs)

- **Per-project `.dev-platform.json` manifests** — future refactor when team scale demands distributed config.
- **Cross-project release notifier** — automatically open a PR in each consumer when dev-platform cuts a new release. Out of scope; consumers bump their own pin per their own cadence.
- **Auto-merge in consumer PRs** — even when pin-bump PRs are mechanical, the merge stays manual per consumer project.
- **Telemetry dashboards beyond markdown/JSON** — Grafana/Prometheus integration deferred until there's a use case beyond solo Rich.
- **Migration of `keystone` Sprint K/L/M and `kermit`/`kermit-pa` bare-Phase taxonomy** — v0.9 scope (Migration tooling); NOT v0.8.
- **Multi-repo dev-platform mirror** — running dev-platform across multiple GitHub orgs. Out of v0.8 scope.
- **A web UI for the fleet dashboard** — JSON output is the API; consumers can build their own UI. dev-platform stays CLI-first.

## Notes for Implementation

- **The registry is centralized in dev-platform.** Per-project manifests are a v0.9-or-later refactor. Today's 5 active projects fit easily in one JSON file; adding a 6th is a one-line edit.
- **Phase 1's `fleet-gate.sh` is the only v0.8 script that runs project-side commands.** Phase 2 (dashboard) only invokes `git` + `check_spec_taxonomy.sh`; Phase 3 (template install) only writes a file; Phase 4 (pin survey) only reads a file. The fleet-gate's parallelism + timeout discipline matters most because it's where things can go wrong.
- **The Scope-rule carve-out paragraph (Change 7) MUST land before Change 8 implements writing into `projects/`.** Per the workflow extension from PR #9, carve-outs must exist in the canonical rule BEFORE the code that depends on them ships. If Change 8 lands first, the spec violates the rule it's trying to update.
- **Mock-project tree pattern** (`tests/fleet-*/fixtures/mock-projects/<name>/`) reuses the v0.6 mock-binary discipline at a coarser granularity — each "project" is a mock filesystem subtree instead of a mock executable. Pattern documentation belongs in `tests/helpers/mock-project-tree.sh` (Change 6) so all 4 fleet test suites share it.
- **`gh release list --limit 1` in `fleet_pins.py`** can fail (network down, gh unauthenticated). The script should treat that as "latest unknown" and report PINS without a STALE/CURRENT comparison — not crash.
- **Parallel-gate concurrency cap defaults to 4** — well below typical workstation core count; prevents one heavyweight gate (e.g., kermit's load-tier smokes) from saturating CPU and starving the others. Override with `--parallel <N>`.
- **Per-project gate output goes to per-project log files** under `/tmp/fleet-gate.<timestamp>/`. The summary table is concise; deep-diving a failing gate is one `cat` away. Don't pipe per-project output to the summary terminal — that's noise.
- **Phase 4 closes v0.8.** The release-tag-cut + Milestone-close cascade mirrors v0.7's Phase 4 (which closed v0.7) — same pattern, same discipline. The `sync-milestones.sh --apply` post-step picks up ROADMAP.md's v0.8 entry change from `*(planned)*` to `*(complete — 2026-MM-DD, …)*`.
- **The Language Architecture Matrix continues to be enforced for the fleet scripts' OWN language choices.** Bash for orchestration, Python for aggregation — matches the entry-point + monitoring pattern locked in v0.4 and v0.5. No new Go/Rust/TypeScript components warranted.
- **dev-platform's own gate (`./scripts/gate_fast.sh`) is one entry in `monitoring/projects.json`.** The fleet sweep includes self for symmetry. No special-casing.
