# v0.8 Phase 4 — Consumer Version-Pin Tracking (closes v0.8)

## Coding Specification for Implementation

## Design Philosophy

Phase 1 answered "did the fleet's gates pass?" Phase 2 answered "what's the state of the fleet?" Phase 3 answered "how do consumers adopt?" Phase 4 answers "are consumers up-to-date?" — for every project in the registry, read the `dev-platform-gate.yml` workflow's `uses:` line, extract the `@vX.Y` pin, and compare against the latest dev-platform release tag. The output surfaces stale pins as `⚠ N minor behind`, floating pins (`@main` or any non-semver ref) as `⚠ floating pin`, and projects that haven't adopted yet as `— not adopted`. Read-only — same Scope-rule treatment as Phase 2 (the only mutating Phase in v0.8 is Phase 3's `fleet-install-template.sh`, governed by the existing carve-out).

The implementation reuses the v0.5 Monitoring + v0.8 Phase 2 patterns exactly: a Python aggregator (`monitoring/fleet_pins.py`) that walks the registry concurrently via `concurrent.futures.ThreadPoolExecutor`, plus a thin Bash CLI wrapper (`scripts/fleet-pins.sh`) that delegates to it. Output: markdown table (default) or JSON (`--format json`). The "latest release" lookup uses `gh api repos/teelr/dev-platform/releases/latest --jq .tag_name`; tests bypass the network via a `--latest <vX.Y>` override flag. No new code-component category — Python for aggregation matches [monitoring/fleet_dashboard.py](../monitoring/fleet_dashboard.py); Bash wrapper matches [scripts/fleet-status.sh](../scripts/fleet-status.sh).

Per the per-Spec-Phase strategy, Phase 4 ships as one PR (~500 LOC). Per the workflow-extension rule from PR #9, the spec names a **post-merge** step — **cut the v0.8 release tag** at the squash-merge SHA, **close the v0.8 GitHub Milestone**, and **bump the consumer-template default pin** from `@v0.7` to `@v0.8` in a follow-up chore PR (the bump can ONLY happen AFTER the tag exists, or fresh installs would hit a 404). This is the v0.7 Phase 4 pattern repeated at the v0.8 boundary — same ordering, same `gh release create` shape.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `monitoring/fleet_pins.py` | Python | Mirrors v0.8 Phase 2's `monitoring/fleet_dashboard.py` — argparse, dataclasses, JSON output, no `pip install` deps. Concurrent per-project queries via `concurrent.futures.ThreadPoolExecutor`. Regex pin extraction. |
| `scripts/fleet-pins.sh` | Bash | Entry-point pattern (`install.sh`, `gate_fast.sh`, `sync-vscode.sh`, `sync-milestones.sh`, `report.sh`, `fleet-gate.sh`, `fleet-status.sh`, `fleet-install-template.sh`). Thin wrapper delegating to the Python script. |
| `tests/fleet-pins/run.sh` | Bash | Test-suite pattern locked in v0.4; mock-project-tree pattern from v0.8 Phase 2. |

No new code-component category. Python for aggregation, Bash for the rest — matches every prior monitoring + entry-point spec.

## Overview

1. **Phase 1:** Fleet Pin Inspector (Changes 1–3)

Single-Phase Spec — total LOC ≤ ~550 (aggregator ~280 + wrapper ~25 + tests ~220 + lessons learned). Tightly coupled; one PR. Phase 4 closes v0.8 (release-tag cut as post-merge, NOT in the PR diff).

---

## Phase 1: Fleet Pin Inspector

### Change 1: `monitoring/fleet_pins.py` — per-project pin aggregator

**Problem:** The fleet-install-template (v0.8 Phase 3) writes a `dev-platform-gate.yml` pinned to a specific release tag (`@v0.7` by default). Over time, consumers' pins drift behind the dev-platform `main` — Phase 1's gate sweep can't detect this (it runs each project's own gate, not the dev-platform pin). The fleet operator needs a single view: who's adopted, what version they're pinned to, and how stale that is relative to the latest dev-platform release. Without this report, the only way to learn a consumer is on a stale pin is to manually grep each project's `.github/workflows/`.

**File:** `monitoring/fleet_pins.py` (new, ~280 lines)

**Implementation:**

Python aggregator, stdlib-only. Mirror [monitoring/fleet_dashboard.py](../monitoring/fleet_dashboard.py) section-for-section:

```python
#!/usr/bin/env python3
"""dev-platform fleet pin inspector.

Reads monitoring/projects.json and reports each project's adoption
of the dev-platform-gate consumer template + its `@vX.Y` pin
relative to the latest dev-platform release tag.

Read-only. No fleet sweep (that's scripts/fleet-gate.sh); no
mutations (that's scripts/fleet-install-template.sh, governed by
the v0.8 Phase 3 Scope-rule carve-out).

Usage:
    python3 monitoring/fleet_pins.py                          # markdown, all enabled
    python3 monitoring/fleet_pins.py --format json            # machine-readable
    python3 monitoring/fleet_pins.py --project atlas
    python3 monitoring/fleet_pins.py --registry <path>        # override (tests)
    python3 monitoring/fleet_pins.py --latest v0.8            # override latest-release lookup (tests)
"""
```

**Structure (lift from `fleet_dashboard.py` lines 24–298):**

1. **Module constants:** `REPO`, `REGISTRY_DEFAULT`, `SOURCE_TEMPLATE_PATH` (the local one at `extensions/github-actions/dev-platform-gate.yml`), `QUERY_TIMEOUT_S = 10`. Add `USES_RE = re.compile(r"uses:\s+teelr/dev-platform/[^@]+@(\S+)")` for the pin extraction.
2. **`@dataclass ProjectPin`** with fields: `name: str`, `path: str`, `adopted: object` (True / False / "self"), `pin: Optional[str]`, `latest: Optional[str]`, `status: str` (one of: `"self"`, `"up-to-date"`, `"behind"`, `"floating"`, `"unparseable"`, `"not-adopted"`), `minor_delta: Optional[int]` (None unless status == "behind").
3. **`_run(cmd, cwd)`** — identical to `fleet_dashboard.py:56-70`, copy verbatim.
4. **`fetch_latest_release(repo_slug="teelr/dev-platform")` -> Optional[str]** — calls `gh api repos/{slug}/releases/latest --jq .tag_name`. Returns the tag string (e.g., `"v0.7"`) or `None` if `gh` is unavailable / not authenticated / no releases yet. Catches `FileNotFoundError` (no `gh` on PATH) AND non-zero exit.
5. **`parse_semver_minor(tag)` -> Optional[tuple[int, int]]** — parses `vX.Y` into `(X, Y)` or returns `None` if the tag doesn't match. Accepts an optional trailing patch (`vX.Y.Z`) but ignores the patch component (we compare at minor granularity).
6. **`classify(pin, latest)` -> tuple[str, Optional[int]]** — returns `(status, minor_delta)`:
   - `pin is None` → `("not-adopted", None)`
   - `pin == ""` or fails `USES_RE` parsing → `("unparseable", None)`
   - `pin == "main"` or `parse_semver_minor(pin) is None` (any non-vX.Y ref) → `("floating", None)`
   - `parse_semver_minor(pin) == parse_semver_minor(latest)` → `("up-to-date", 0)`
   - `parse_semver_minor(pin) < parse_semver_minor(latest)` → `("behind", minor_delta)` where `minor_delta` is `(major_diff * 1000) + minor_diff` for sortability (one major diff dwarfs any minor diff in the display)
   - `parse_semver_minor(pin) > parse_semver_minor(latest)` → `("up-to-date", 0)` (consumer is ahead — e.g., they pinned to a pre-release; treat as fine, the warning shape exists for *stale* pins)
   - `latest is None` → return `(status_without_latest_comparison, None)` — adopted/floating/unparseable still surface, but "behind" can't be computed
7. **`extract_pin(template_path: Path)` -> Optional[str]** — reads the file if it exists; greps for the first line matching `USES_RE`; returns the captured group (the part after `@`). Returns `None` if file absent; returns `""` if file present but no `uses:` matches.
8. **`query_project(entry, latest)` -> ProjectPin** — for the registry entry:
   - Resolve `target = REPO if path == "." else REPO / path`. Same logic as `fleet_dashboard.py:77`.
   - `template_path = target / ".github" / "workflows" / "dev-platform-gate.yml"`.
   - If `name == "dev-platform"`: return `ProjectPin(name, path, adopted="self", pin=None, latest=latest, status="self", minor_delta=None)`.
   - Otherwise: `pin = extract_pin(template_path)`. Compute `adopted = template_path.exists()`. `(status, minor_delta) = classify(pin, latest)`.
9. **`load_registry(path)`** — lift from `fleet_dashboard.py:162-172` verbatim, including the `encoding="utf-8"` on `open()`.
10. **`format_status(status, minor_delta, pin)` -> str** — markdown-friendly:
    - `"self"` → `"self"`
    - `"up-to-date"` → `"✓ up-to-date"`
    - `"behind"` → `f"⚠ {minor_delta} minor behind"` (or `f"⚠ {major}.{minor} behind"` if cross-major)
    - `"floating"` → `"⚠ floating pin"`
    - `"unparseable"` → `"⚠ unparseable"`
    - `"not-adopted"` → `"— not adopted"`
11. **`render_markdown(pins, registry_path, latest)`** — table with columns: Project, Adopted, Pin, Status. Header line includes `Latest dev-platform release: {latest or "?"}`. Mirror `fleet_dashboard.py:200-230` row-format string.
12. **`render_json(pins, registry_path, latest)`** — same shape as `fleet_dashboard.py:233-246` with `latest_release` field added at the top level.
13. **`main()`** — argparse with `--format`, `--project`, `--registry`, `--latest`, plus the standard help. Calls `fetch_latest_release()` ONCE before the thread pool fans out (so the same `latest` value is passed to every worker). The `--latest` flag overrides the network call entirely (tests use this). Same `enabled = [e for e in entries if e.get("enabled", False)]` strict opt-in as `fleet_dashboard.py:275` (strict opt-in default — matches Phase 1 + Phase 2). Concurrent execution via `ThreadPoolExecutor(max_workers=8)` with `pool.map(lambda e: query_project(e, latest), enabled)`.

**Network handling:** `fetch_latest_release()` is best-effort. If it returns `None`, the dashboard still renders — every project's `latest` column shows `?`, status drops "behind" but keeps "floating" / "unparseable" / "not-adopted" / "self" / "up-to-date" (the last requires a known latest, so it degrades to a generic "adopted" row when latest is unknown). Print a one-line stderr warning when the lookup fails so the user knows.

**Acceptance Test:**

```bash
# Syntax + import
python3 -c "import ast; ast.parse(open('monitoring/fleet_pins.py').read())"

# --help renders
python3 monitoring/fleet_pins.py --help | grep -q "fleet pin inspector"

# Live run against the real registry (gh available)
python3 monitoring/fleet_pins.py --format json | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert 'projects' in d and isinstance(d['projects'], list)
assert 'latest_release' in d
"

# Test override (no gh required)
python3 monitoring/fleet_pins.py --latest v0.7 --format json | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['latest_release'])"
# Expect: v0.7
```

---

### Change 2: `scripts/fleet-pins.sh` — thin CLI wrapper

**Problem:** Every other entry point in `scripts/` is a Bash wrapper around either a Python aggregator (`report.sh` → `aggregator.py`, `fleet-status.sh` → `fleet_dashboard.py`) or a self-contained Bash script (`fleet-gate.sh`, `fleet-install-template.sh`). Phase 4's user-facing surface must match — no `python3 monitoring/fleet_pins.py` invocations in docs; the wrapper IS the public API.

**File:** `scripts/fleet-pins.sh` (new, ~25 lines)

**Implementation:**

Copy [scripts/fleet-status.sh](../scripts/fleet-status.sh) verbatim, change only the script name in the header comment + the `DASHBOARD` variable name + the file it points at:

```bash
#!/usr/bin/env bash
# scripts/fleet-pins.sh — fleet pin inspector CLI.
# Thin wrapper that delegates to monitoring/fleet_pins.py.
#
# Usage:
#   ./scripts/fleet-pins.sh                       # markdown, all enabled projects
#   ./scripts/fleet-pins.sh --format json         # machine-readable
#   ./scripts/fleet-pins.sh --project atlas
#   ./scripts/fleet-pins.sh --latest v0.8         # override latest-release lookup (tests)
#   ./scripts/fleet-pins.sh --registry <path>     # override registry path (tests)
#   ./scripts/fleet-pins.sh --help

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSPECTOR="${REPO}/monitoring/fleet_pins.py"

if [[ ! -f "${INSPECTOR}" ]]; then
    echo "ERROR: inspector not found at ${INSPECTOR}" >&2
    exit 1
fi

# Pass args through. Python script handles --help.
exec python3 "${INSPECTOR}" "$@"
```

**Acceptance Test:**

```bash
test -x scripts/fleet-pins.sh
bash -n scripts/fleet-pins.sh
./scripts/fleet-pins.sh --help | grep -q "fleet pin inspector"
./scripts/fleet-pins.sh --latest v0.7 --format json | python3 -c "import json,sys; json.load(sys.stdin)"
```

---

### Change 3: `tests/fleet-pins/run.sh` — fixture suite

**Problem:** Phase 4's pin extraction has 5 distinct branches (`not-adopted`, `up-to-date`, `behind`, `floating`, `unparseable`, plus the `self` short-circuit). Without a fixture suite covering every branch, a future refactor of `classify()` or `extract_pin()` could silently regress one branch and ship undetected. The path-guard + tilt-the-tree test pattern from Phase 3 already proved fleet tests catch bug classes the unit-tier doesn't.

**File:** `tests/fleet-pins/run.sh` (new, ~220 lines)

**Implementation:**

Source `tests/helpers/assert.sh` + `tests/helpers/mock-project-tree.sh` (shipped in Phase 2). Build a mock project tree under `mktemp -d`:

- `mock-projects/clean-1/` — no template file (not-adopted)
- `mock-projects/pinned-v07/` — template pinned to `@v0.7`
- `mock-projects/pinned-v08/` — template pinned to `@v0.8`
- `mock-projects/floating-1/` — template pinned to `@main`
- `mock-projects/garbled-1/` — template exists but has no `uses:` line matching the regex (e.g., a comment-only file or a different `uses:` reference)

Write the mock registry inline (same pattern as `tests/fleet-dashboard/run.sh:54-62`). Use `--latest v0.8 --registry "${MOCK_REGISTRY}"` everywhere to bypass the network.

**Template variants (write inline in the runner — don't extend the helper):**

```bash
# pinned-v07: standard install
mock_project_install_template "${MOCK_ROOT}/pinned-v07"
# (helper writes @v0.7 — matches the dev-platform-gate.yml example exactly)

# pinned-v08: same template, rewritten to @v0.8 via sed
mock_project_install_template "${MOCK_ROOT}/pinned-v08"
sed -i 's|@v0.7$|@v0.8|' "${MOCK_ROOT}/pinned-v08/.github/workflows/dev-platform-gate.yml"

# floating-1: same template, rewritten to @main
mock_project_install_template "${MOCK_ROOT}/floating-1"
sed -i 's|@v0.7$|@main|' "${MOCK_ROOT}/floating-1/.github/workflows/dev-platform-gate.yml"

# garbled-1: drop a file that exists but has no parseable uses: line
mkdir -p "${MOCK_ROOT}/garbled-1/.github/workflows"
echo "# garbled — no uses: line" > "${MOCK_ROOT}/garbled-1/.github/workflows/dev-platform-gate.yml"
```

**Required assertions (≥ 14):**

1. **`bash -n`** — runner syntax clean
2. **`python3 -c "import ast..."`** — `fleet_pins.py` parses clean
3. **`--help`** — renders the descriptor string
4. **Markdown render** exits 0 with `# Fleet Pins` (or similar) header line
5. **JSON render** parses + has `latest_release` field set to `"v0.8"` (from `--latest`)
6. **`clean-1`** → `adopted=False`, `status="not-adopted"`, `pin=None`
7. **`pinned-v07`** → `adopted=True`, `pin="v0.7"`, `status="behind"`, `minor_delta` indicates 1 minor behind
8. **`pinned-v08`** → `adopted=True`, `pin="v0.8"`, `status="up-to-date"`
9. **`floating-1`** → `pin="main"`, `status="floating"`
10. **`garbled-1`** → `adopted=True`, `pin=""` (or None — runner inspects whichever shape `classify` produces), `status="unparseable"`
11. **`dev-platform`** entry (if mocked into registry with `path: "."`) → `status="self"` (or skip if mock registry doesn't include dev-platform)
12. **`--project pinned-v07` filter** returns exactly 1 row in the markdown output (regex-count rows in the table)
13. **`--registry` override** — script uses the provided registry instead of the default
14. **`--latest` override** — passing `--latest v0.6` makes `pinned-v07` show as `up-to-date` (proves the latest is configurable, not hardcoded)
15. **Path-guard contract** — same as Phase 3 Check 12: snapshot the mock-projects tree before any invocation and re-snapshot after; assert NO new files appeared (fleet-pins is read-only)

Test runner uses `mktemp -d` + `trap` cleanup. Auto-discovered by `gate_fast.sh`.

**Acceptance Test:**

```bash
bash tests/fleet-pins/run.sh
# Expect: 15 PASS / 0 FAIL

./scripts/gate_fast.sh 2>&1 | grep -q "tests/fleet-pins/run.sh"
# Expect: present in output

# Gate count grows by 15 (was 114 → 129 after Phase 4)
```

---

## Post-merge step (deferred, in spec — runs after PR squash-merges)

**Close v0.8 + cut the release tag + bump the consumer-template default pin.** This is the v0.7 Phase 4 sequence repeated at the v0.8 boundary. Order matters — tag MUST exist before the pin-bump merges, or fresh consumer installs would 404.

```bash
# (1) Pull the squash-merge SHA on local main
git checkout main && git pull --ff-only
MERGE_SHA="$(git rev-parse HEAD)"

# (2) Cut the v0.8 release tag at the merge SHA
gh release create v0.8 --target "${MERGE_SHA}" \
  --title "v0.8 Cross-project orchestration" \
  --notes "Fleet operations: registry, gate sweep, dashboard, opt-in drift correction, version-pin tracking. Closes v0.8."

# (3) Verify the @v0.8 pin resolves
gh api "repos/teelr/dev-platform/contents/extensions/github-actions/dev-platform-gate.yml?ref=v0.8" --jq .sha

# (4) Close the v0.8 GitHub Milestone (or use sync-milestones.sh --apply after marking
#     v0.8 entry as (complete ...) in ROADMAP.md — same as v0.7 Phase 4's flow)

# (5) Open a follow-up chore PR that bumps the default pin from @v0.7 to @v0.8:
#     - extensions/github-actions/dev-platform-gate.yml: `uses: ...@v0.7` → `@v0.8`
#     - scripts/fleet-install-template.sh: `DEFAULT_PIN="v0.7"` → `"v0.8"`
#     - tests/fleet-install/run.sh: update Check 10's --pin v0.6 case to compare against the new default
#     This PR ships separately because (a) the bump CANNOT happen until step (2) completes
#     (otherwise @v0.8 doesn't resolve) and (b) tagging Phase 4's PR with both fleet-pins.py
#     AND a default-pin bump conflates the new-tracking-feature commit with a content change
#     that mechanically depends on the merge having already happened.

# (6) Run fleet-pins.sh against the real fleet — confirm:
#     - dev-platform: self
#     - atlas / kermit / kermit-pa / keystone: "— not adopted" or "✓ up-to-date" or "⚠ ..."
#       depending on whether Phase 3's post-merge step was ever invoked
./scripts/fleet-pins.sh
```

**Phase 4 closes v0.8.** No further work is in scope for v0.8. The next Roadmap Phase is v0.9 (Migration tooling).

---

## What NOT to Do

- **Do NOT fetch the latest release inside `query_project()`** — that would issue N `gh api` calls (one per worker) for the same answer. Fetch ONCE in `main()` and pass `latest` into every worker.
- **Do NOT skip the `--latest <vX.Y>` override flag.** Tests MUST run without network access — Phase 1's fleet-gate test infra runs on CI without `gh` authentication. The override is the testability primitive.
- **Do NOT use a hardcoded URL** (e.g., `https://api.github.com/repos/teelr/dev-platform/releases/latest`) instead of `gh api`. `gh` is already a project-wide requirement (Phase 1's fleet-gate.sh + v0.7 Phase 4's sync-milestones.sh both depend on it); duplicate auth paths are a maintenance hazard.
- **Do NOT treat `@main` as up-to-date** even when the resolved SHA matches the latest tag. Floating pins break reproducibility — they're explicitly anti-pattern per [docs/CI-INTEGRATION.md](../docs/CI-INTEGRATION.md): "Do not use `@main` — floating tags break reproducibility." The report MUST flag them as `⚠ floating pin` so consumers see the warning regardless of whether `main` currently points at v0.8.
- **Do NOT auto-bump pins.** Phase 4 is READ-ONLY. The Scope-rule carve-out from Phase 3 covers ONLY `fleet-install-template.sh` writing the canonical filename — not editing existing consumer files. A `--bump-pin` flag would require a NEW carve-out paragraph in `CLAUDE.md`; out of scope for v0.8.
- **Do NOT add a `--bump-default` flag** to fleet-pins.sh that edits dev-platform's own files. The DEFAULT_PIN bump is a manual chore-PR, NOT an aggregator feature — see post-merge step (5).
- **Do NOT include the pin-bump in the Phase 4 PR itself.** The bump MUST land after the v0.8 release tag exists, or fresh installs hit a 404 on `@v0.8`. Two separate PRs: this Phase, then the bump-chore.
- **Do NOT compare at patch granularity.** Pins are minor-bumped (`v0.7`, `v0.8`, `v0.9`); the dev-platform release cadence per [ROADMAP.md](../ROADMAP.md) is one Roadmap Phase per minor bump. Patches (`v0.7.1`) are rare hotfixes; the staleness column treats `v0.7.1` and `v0.7.5` as both "1 minor behind v0.8" — equivalent for the consumer's upgrade decision.
- **Do NOT crash on registries that include `dev-platform` itself.** The `name == "dev-platform"` short-circuit MUST trigger before attempting to read the template (dev-platform has no `.github/workflows/dev-platform-gate.yml` of the consumer shape — it has the SOURCE template at `extensions/github-actions/`; reading the consumer path would return `not-adopted` and confuse the report).
- **Do NOT use `pip install` or any non-stdlib dependency.** `requests`, `pyyaml`, `pyaml`, `tomli`, `semver` — all banned. `re` + `subprocess` + `argparse` + `json` + `dataclasses` are sufficient.
- **Do NOT block on slow `gh api` calls.** Apply `QUERY_TIMEOUT_S=10` to the `gh api` invocation in `fetch_latest_release()` exactly as `query_project` does. A hung network call must not freeze the whole report — degrade to `latest=None` instead.
- **Do NOT report on disabled projects** by default. Same strict opt-in as Phase 1's `fleet-gate.sh` and Phase 2's `fleet_dashboard.py`: `entries = [e for e in registry if e.get("enabled", False)]`. Missing field → excluded.
- **Do NOT name fixture subdirectories `projects/`** under `tests/fleet-pins/fixtures/`. Use `mock-projects/` per the Phase 1 lesson. (Restated here for the same reason Phases 2 + 3 restated it — fixture trees that ignore the lesson silently break the suite.)

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `monitoring/fleet_pins.py` | New | Per-project pin aggregator. Concurrent `ThreadPoolExecutor`; regex pin extraction; `gh api` latest-release lookup with `--latest` override; markdown + JSON output. |
| `scripts/fleet-pins.sh` | New | Thin Bash wrapper, mirrors `fleet-status.sh` verbatim. |
| `tests/fleet-pins/run.sh` | New | 15-assertion fixture suite using mock-project-tree helper + 5 template variants (clean / v0.7 / v0.8 / @main / garbled). Path-guard contract included. |

No `.gitignore` extensions needed — every file type already in the allow-list:

- `monitoring/*.py` covered by `!monitoring/**/*.py` ✓
- `scripts/*.sh` covers `fleet-pins.sh` ✓
- `tests/**/*.sh` covers `run.sh` ✓

Consumer Audit (5-point checklist) reduces to confirming `git check-ignore -v` on every new file — same as Phase 3's audit.

## Implementation Order

1. **Change 1** (`monitoring/fleet_pins.py`) — main deliverable; everything else depends on it.
2. **Change 2** (`scripts/fleet-pins.sh`) — thin wrapper; can be written immediately after Change 1's interface stabilizes.
3. **Change 3** (`tests/fleet-pins/run.sh`) — depends on Change 1 + the mock-project-tree helper from Phase 2.
4. **Local verification** — `bash tests/fleet-pins/run.sh` → 15/15, then `./scripts/gate_fast.sh` → 129 PASS / 0 FAIL / 0 SKIP.
5. **Live verification** — `./scripts/fleet-pins.sh` against the real 5-project registry; eyeball the markdown output. Confirm dev-platform = `self`, and the other 4 are either `— not adopted` (likely, since Phase 3's post-merge dogfooding was skipped) or `⚠ ...` / `✓ up-to-date` as applicable.
6. **Post-merge** — close v0.8 + cut v0.8 release tag + bump the consumer-template default pin (separate chore PR). See post-merge step section.

## Verification Checklist

- [ ] `monitoring/fleet_pins.py` exists, python-syntax clean (`python3 -c "import ast; ast.parse(...)"`).
- [ ] `--help` renders without network calls.
- [ ] Argparse robustness: `--registry` / `--project` / `--latest` / `--format` each emit a sensible error when their value is missing OR malformed (argparse handles this by default; the test asserts behavior, not source).
- [ ] `--latest v0.8` override bypasses `gh api` (no network call observed when running tests with `PATH=/tmp`).
- [ ] `scripts/fleet-pins.sh` exists, bash-syntax clean, executable.
- [ ] `./scripts/fleet-pins.sh --help` exits 0 with descriptor text.
- [ ] Markdown render exits 0 + contains the title line + the latest-release header.
- [ ] JSON render parses + has `latest_release`, `projects[]`, and every required project field per the `ProjectPin` dataclass.
- [ ] `not-adopted` / `up-to-date` / `behind` / `floating` / `unparseable` / `self` — each status surfaces on the right mock project.
- [ ] `--project <name>` filter narrows the output to one row.
- [ ] `--registry <path>` override works.
- [ ] **Path-guard contract**: script never writes to any filesystem location (read-only by design).
- [ ] `bash tests/fleet-pins/run.sh` → 15 PASS / 0 FAIL.
- [ ] `./scripts/gate_fast.sh` → **129 PASS** / 0 FAIL / 0 SKIP (was 114 + 15 fleet-pins assertions).
- [ ] `./scripts/check_spec_taxonomy.sh` clean (13 spec files conform).
- [ ] Consumer Audit: every new file `git check-ignore -v`'d; all show re-include rules.
- [ ] **Post-merge (deferred)**: v0.8 release tag cut at the merge SHA; v0.8 Milestone closed; `gh api .../contents/.../dev-platform-gate.yml?ref=v0.8` returns 200; follow-up chore PR opened to bump DEFAULT_PIN.

## Out of Scope (Future Specs)

- **Auto-bump pins across the fleet.** Would require a new Scope-rule carve-out. Phase 3's carve-out is narrow ("ONE filename in ONE directory") and explicitly excludes editing existing files. Out of v0.8 and v0.9 — would need its own spec.
- **Notification when a consumer falls behind.** Email / Slack / GitHub issue creation when staleness exceeds N minor versions. Speculative; the report itself is the notification mechanism today.
- **Per-consumer release-note diff.** "Here's what changed between v0.7 and v0.8 that affects you." A nice-to-have docs feature; v0.7's GitHub Release notes already serve as the canonical source.
- **Patch-granularity comparison.** As argued in "What NOT to Do" — dev-platform's minor-bump cadence makes patch tracking low-value. Revisit if patch releases become common.
- **`fleet-pins.sh --check` flag that exits non-zero when ANY consumer is stale.** Useful as a CI gate someday; pre-mature today. v0.5 Monitoring's `report.sh` deliberately exits 0 regardless — same posture here. A future `fleet-pins-gate.sh` could wrap this with thresholds (e.g., "exit 1 if any consumer is ≥ 2 minor behind").

## Notes for Implementation

- **The `--latest` override is mandatory infrastructure, not a "test convenience."** Real users may also want to ask "is anyone behind v0.7?" without bumping to compare against latest. Default to `gh api` lookup; flag is the explicit override.
- **`fetch_latest_release()` failure modes:** (a) `gh` not on PATH → `FileNotFoundError` from `subprocess.run` (with `_run` returning `(127, "")`); (b) `gh` present but not authenticated → non-zero exit; (c) repo has no releases yet → JSON-parse failure on the `--jq .tag_name` output. All three degrade to `latest=None` with a one-line stderr warning. NEVER raise — the report should still render.
- **The path-guard test (Change 3, assertion 15) is load-bearing in the same spirit as Phase 3's Check 12.** fleet-pins.py is READ-ONLY by design; the path-guard test mechanically enforces it. Any future change that accidentally writes a `.cache` / `.tmp` / etc. file under `mock-projects/` would be caught immediately.
- **The mock-project-tree helper from Phase 2 (`mock_project_install_template`) writes `@v0.7` — that's the helper's hardcoded pin.** Tests that need a different pin re-write via `sed` AFTER calling the helper (see Change 3's template-variants block). Do not extend the helper to take a pin argument; that would be over-design for one consumer.
- **The default-pin bump (post-merge step (5)) lives in a follow-up chore PR.** When you implement that chore: update `extensions/github-actions/dev-platform-gate.yml`, `scripts/fleet-install-template.sh:DEFAULT_PIN`, AND `tests/fleet-install/run.sh` Check 10 (which currently asserts on `--pin v0.6` to compare against `@v0.7` default — that needs to become `--pin v0.7` comparing against `@v0.8`). All three land atomically in the chore PR.
- **The branch name follows convention:** `v0.8/phase-4-fleet-pins`. `/pr` will auto-derive the title from this spec's `## Phase 1: Fleet Pin Inspector` heading; the auto-detected milestone will be `v0.8: Cross-project orchestration` (still open until post-merge step (4) closes it).
- **Gate count math:** 114 (Phase 3 close) + 15 (Phase 4 assertions) = 129. If the count differs, the auto-discovery picked up a stray fixture or missed a suite — investigate before claiming PASS.
