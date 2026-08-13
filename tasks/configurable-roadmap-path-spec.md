# v1.13: Configurable Roadmap Path

## Coding Specification for Implementation

## Design Philosophy

`scripts/check_version_collision.py`, `scripts/check_spec_taxonomy.sh`, and `scripts/claim_roadmap_version.py` all hardcode `ROADMAP.md` at the repo root. Keystone's roadmap lives at `docs/roadmap.md` instead, and has no `planning.md` at all — so `check_version_collision.py` prints `"no ROADMAP.md — nothing to check"` and exits 0, `check_spec_taxonomy.sh`'s roadmap-level scan pass finds nothing to flag, and `claim_roadmap_version.py`'s roadmap-side of its `max(roadmap_high, milestone_high)` computation silently always contributes 0. All three degrade to a confident-looking PASS/silent-no-op that never actually checked anything — filed as [teelr/dev-platform#64](https://github.com/teelr/dev-platform/issues/64) by Keystone's own session, after their first fix attempt (symlinking root `ROADMAP.md` → `docs/roadmap.md`) made things *worse*: `git show origin/main:ROADMAP.md` does not dereference symlinks, so `check_version_collision.py` read the raw symlink target-path string as file content, made every real version look "new," and produced false `COLLISION` failures against Keystone's own pre-existing milestone-title drift (confirmed and reverted same night, `teelr/keystone#508` → `#509`).

The fix: a `ROADMAP_PATH` environment variable, read by all three scripts, defaulting to `ROADMAP.md` at the root when unset — fully backward compatible, zero behavior change for every consumer currently at the default location. This mirrors the existing `VERSION_GUARD_REPO_SLUG` override pattern already in `check_version_collision.py` and `claim_roadmap_version.py` (added in v1.11 for test isolation) — same shape, same place in the code, same "read once, default to the production value" contract. Each script's docstring gets an explicit warning that a symlinked roadmap path will NOT work with the `git show`-based diff (`check_version_collision.py` and `claim_roadmap_version.py` both read `origin/main`'s copy via `git show`, which is where the symlink footgun lives — `check_spec_taxonomy.sh` reads the working-tree file directly via plain shell redirection, so it isn't affected by this specific failure mode, but gets the same env var for path configurability).

**Scope decision — including `claim_roadmap_version.py`.** The filed issue names only `check_version_collision.py` and `check_spec_taxonomy.sh` ("both checkers" — the two that run automatically in CI/gate context). `claim_roadmap_version.py` has the identical hardcoded-path root cause, just lower observable impact (its roadmap-side computation silently contributes 0 and the script falls back to trusting GitHub milestones alone, which are usually still authoritative — no observed wrong claim yet, same reasoning already used when this exact gap was first flagged during v1.11's own `/review`). Since the fix is the same trivial, proven, one-line-per-script pattern, and leaving a third script with the identical bug after fixing two would recreate the "partial fix, one script still silently wrong" shape this whole guard exists to prevent, this spec fixes all three. Flagged here explicitly as a deliberate scope decision beyond the issue's literal ask, not a silent expansion.

**Not in scope:** making `planning.md`'s path configurable in `check_spec_taxonomy.sh`. The issue's own text explains Keystone "has no `planning.md` at all" as *context* (already handled correctly — `scan_roadmap_file` already no-ops gracefully on a missing file, per its existing `[[ -f "$f" ]] || return 0` guard), not as a second bug to fix. No consumer has reported a planning-equivalent doc at a different path that needs scanning.

**Branching:** single Phase, single PR. Diff is small (env var read added to 3 scripts + a docstring update on 2 of them + doc troubleshooting update + new test coverage), matching the v0.6/v1.12 "small Roadmap Phase" precedent.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/check_version_collision.py`, `scripts/claim_roadmap_version.py` edits | Python | Existing files, no new component. |
| `scripts/check_spec_taxonomy.sh` edit | Bash | Existing file, no new component. |
| `tests/version-collision/run.sh`, `tests/taxonomy/run.sh` edits | Bash | Extending existing suites in their established language. |

## Overview

1. **Phase 1 — Configurable Roadmap Path** (Changes 1–6): add `ROADMAP_PATH` support to all three scripts, document the symlink footgun, add test coverage proving the override works and default behavior is unchanged.

---

## Phase 1: Configurable Roadmap Path

### Change 1: `scripts/check_version_collision.py` — `ROADMAP_PATH` support

**Problem:** `main()` hardcodes `project_root / "ROADMAP.md"` (line 87) and the cross-branch comparison hardcodes `git show origin/main:ROADMAP.md` (line 96). Both need to read the same configurable path.

**File:** `scripts/check_version_collision.py`, lines 1-29 (docstring), 86-96

**Implementation:**

Add a symlink-footgun warning paragraph to the module docstring (after the existing "Exit 0 if fully checked..." paragraph, before "Usage:"):

```python
A note on the roadmap path itself: set ROADMAP_PATH (relative to the repo
root, e.g. "docs/roadmap.md") if your roadmap doesn't live at the default
ROADMAP.md. Do NOT satisfy this by symlinking a root ROADMAP.md to the real
file — `git show origin/main:ROADMAP.md` does not dereference symlinks, it
returns the raw symlink target-path string as the file's "content," which
makes every real version look "new" and produces false COLLISION failures
against your own milestone history. Set ROADMAP_PATH instead.
```

In `main()`, replace:

```python
def main(project_root: Path) -> int:
    roadmap = project_root / "ROADMAP.md"
    if not roadmap.exists():
        print("no ROADMAP.md — nothing to check")
        return 0

    local_text = roadmap.read_text()
    local_versions = _versions_in(local_text)

    fetch_ok = _run(["git", "fetch", "origin", "main", "--quiet"]) is not None
    main_text = _run(["git", "show", "origin/main:ROADMAP.md"], timeout=20)
```

with:

```python
def main(project_root: Path) -> int:
    roadmap_path = os.environ.get("ROADMAP_PATH", "ROADMAP.md")
    roadmap = project_root / roadmap_path
    if not roadmap.exists():
        print(f"no {roadmap_path} — nothing to check")
        return 0

    local_text = roadmap.read_text()
    local_versions = _versions_in(local_text)

    fetch_ok = _run(["git", "fetch", "origin", "main", "--quiet"]) is not None
    main_text = _run(["git", "show", f"origin/main:{roadmap_path}"], timeout=20)
```

`os` is already imported (used by `_repo_slug()`'s `VERSION_GUARD_REPO_SLUG` read) — no new import needed.

**Acceptance Test:**

```bash
# Default behavior unchanged
python3 -c "
import subprocess
out = subprocess.run(['python3', 'scripts/check_version_collision.py', '.'], capture_output=True, text=True)
assert 'no new Roadmap Phase' in out.stdout or 'new version header' in out.stdout, out.stdout
print('OK: default path still works')
"
```

---

### Change 2: `scripts/claim_roadmap_version.py` — `ROADMAP_PATH` support

**Problem:** `_highest_minor_in_roadmap()` hardcodes `git show origin/main:ROADMAP.md` (line 59). Same root cause as Change 1, same fix shape.

**File:** `scripts/claim_roadmap_version.py`, lines 1-16 (docstring), 57-64

**Implementation:**

Add the same symlink-footgun warning to the module docstring (append after the existing "Usage:" paragraph, before "Prints the claimed version..."):

```python
Set ROADMAP_PATH (relative to the repo root, e.g. "docs/roadmap.md") if your
roadmap doesn't live at the default ROADMAP.md. Do NOT symlink a root
ROADMAP.md to the real file as a substitute — `git show origin/main:...`
does not dereference symlinks; set ROADMAP_PATH instead.
```

Replace `_highest_minor_in_roadmap()`:

```python
def _highest_minor_in_roadmap(major: int) -> int:
    _run(["git", "fetch", "origin", "main", "--quiet"])
    roadmap_text = _run(["git", "show", "origin/main:ROADMAP.md"])
    highest = 0
    for maj_s, min_s in _ROADMAP_VERSION_RE.findall(roadmap_text):
        if int(maj_s) == major:
            highest = max(highest, int(min_s))
    return highest
```

with:

```python
def _highest_minor_in_roadmap(major: int) -> int:
    roadmap_path = os.environ.get("ROADMAP_PATH", "ROADMAP.md")
    _run(["git", "fetch", "origin", "main", "--quiet"])
    roadmap_text = _run(["git", "show", f"origin/main:{roadmap_path}"])
    highest = 0
    for maj_s, min_s in _ROADMAP_VERSION_RE.findall(roadmap_text):
        if int(maj_s) == major:
            highest = max(highest, int(min_s))
    return highest
```

`os` is already imported (used by `_repo_slug()`'s `VERSION_GUARD_REPO_SLUG` read) — no new import needed.

**Acceptance Test:**

```bash
python3 -c "
import ast
ast.parse(open('scripts/claim_roadmap_version.py').read())
print('OK: syntax clean')
"
```

---

### Change 3: `scripts/check_spec_taxonomy.sh` — `ROADMAP_PATH` support

**Problem:** Line 142 hardcodes `scan_roadmap_file "$PROJECT_ROOT/ROADMAP.md"`. `planning.md` (line 143) is explicitly NOT in scope — see Design Philosophy.

**File:** `scripts/check_spec_taxonomy.sh`, lines 140-143

**Implementation:**

Replace:

```bash
scan_roadmap_file "$PROJECT_ROOT/ROADMAP.md"
scan_roadmap_file "$PROJECT_ROOT/planning.md"
```

with:

```bash
ROADMAP_FILE="${ROADMAP_PATH:-ROADMAP.md}"
scan_roadmap_file "$PROJECT_ROOT/$ROADMAP_FILE"
scan_roadmap_file "$PROJECT_ROOT/planning.md"
```

Bash's `${VAR:-default}` gives the same "unset or empty → default" contract as the Python scripts' `os.environ.get(..., default)`.

**Acceptance Test:**

```bash
bash -n scripts/check_spec_taxonomy.sh && echo "OK: syntax clean"
./scripts/check_spec_taxonomy.sh .   # default behavior unchanged, clean against dev-platform's own repo
```

---

### Change 4: `docs/CI-INTEGRATION.md` — document `ROADMAP_PATH`

**Problem:** Consumers with a non-default roadmap location need to discover this knob exists.

**File:** `docs/CI-INTEGRATION.md`

**Implementation:**

1. Add a new subsection after "## Local pre-flight" (before "## Disabling"):

```markdown
## Non-default roadmap location

If your project's Roadmap Phase entries don't live at the repo-root
`ROADMAP.md` (e.g. Keystone's live at `docs/roadmap.md`), set `ROADMAP_PATH`
(relative to the repo root) — `check_version_collision.py`,
`check_spec_taxonomy.sh`, and `claim_roadmap_version.py` all read it, falling
back to `ROADMAP.md` when unset. Set it as a `env:` entry on the calling
step/job in your `dev-platform-gate.yml`, or export it before running
`/plan`/`gate_fast.sh` locally.

**Do not symlink a root `ROADMAP.md` to your real file as a substitute.**
`check_version_collision.py` and `claim_roadmap_version.py` both compare
against `origin/main`'s copy via `git show origin/main:<path>`, which does
NOT dereference symlinks — it returns the raw symlink target-path string as
the file's "content." This makes every real version look "new" and produces
false `COLLISION` failures against your own milestone history (confirmed
live on Keystone's first attempt, reverted the same night). Set
`ROADMAP_PATH` instead.
```

2. Add a troubleshooting row after the existing `version-collision` rows:

```markdown
| Check reports "no ROADMAP.md — nothing to check" but you DO have a roadmap doc | It's not at the repo-root `ROADMAP.md` path the checks default to | Set `ROADMAP_PATH` (see "Non-default roadmap location" above) — do not symlink |
```

**Acceptance Test:**

```bash
grep -n "ROADMAP_PATH" docs/CI-INTEGRATION.md | wc -l   # expect >= 3 (new section x2 + troubleshooting row)
```

---

### Change 5: `tests/version-collision/run.sh` — `ROADMAP_PATH` coverage

**Problem:** No test proves the override actually works, or that default behavior survives the change.

**File:** `tests/version-collision/run.sh`

**Implementation:**

Add two new checks after the existing Check 12 (the dual-form regression guards from v1.12), following the exact `run_check`/`run_claim` helper pattern already established in this file:

1. **Check 13 (`check_version_collision.py`, custom path):** build a THIRD small origin/work pair (mirroring the `HEADING_ORIGIN`/`HEADING_WORK` pattern from Change 4 of the v1.12 spec) whose seed content lives at `docs/roadmap.md` instead of `ROADMAP.md` — no `ROADMAP.md` at all in this one, so the test also proves the default-path behavior doesn't silently mask a wrong default. Run `check_version_collision.py` against it with `ROADMAP_PATH=docs/roadmap.md` set (added to `run_check`'s env-assignment args) and confirm it detects a new version header there. Then run it WITHOUT `ROADMAP_PATH` set against the same working dir and confirm it reports `"no ROADMAP.md — nothing to check"` (exit 0) — proving the default path genuinely doesn't find the non-default file (the exact silent-no-op this spec fixes, now under an explicit regression guard).

2. **Check 14 (`claim_roadmap_version.py`, custom path):** same custom-path origin/work pair, confirm `claim_roadmap_version.py` with `ROADMAP_PATH=docs/roadmap.md` set correctly computes `roadmap_high` from that path (i.e., claims a version consistent with what's actually in `docs/roadmap.md`, not silently treating the roadmap-side as empty).

Both checks reuse the existing `empty_titles` mock-milestone fixture and `VERSION_GUARD_REPO_SLUG=owner/repo` pattern already established for the other checks in this file.

**Acceptance Test:**

```bash
bash tests/version-collision/run.sh   # expect 14 PASS, 0 FAIL
```

---

### Change 6: `tests/taxonomy/run.sh` — `ROADMAP_PATH` coverage

**Problem:** No test proves `check_spec_taxonomy.sh`'s override works.

**File:** `tests/taxonomy/run.sh`

**Implementation:**

Add a new helper `run_roadmap_fixture_custom_path` (mirrors `run_roadmap_fixture`, lines 56-84, but writes the fixture to a caller-supplied relative path instead of hardcoding `${tmp}/ROADMAP.md`, and sets `ROADMAP_PATH` when invoking the checker):

```bash
run_roadmap_fixture_custom_path() {
    local fixture="$1"
    local rel_path="$2"
    local expected_exit="$3"
    local description="$4"
    local expected_match="${5:-}"

    local tmp
    tmp="$(mktemp -d)"
    trap "rm -rf '${tmp}'" RETURN

    mkdir -p "$(dirname "${tmp}/${rel_path}")"
    cp "${HERE}/fixtures/${fixture}" "${tmp}/${rel_path}"
    mkdir -p "${tmp}/tasks"
    echo "# stub" > "${tmp}/tasks/stub-spec.md"

    local output
    output="$(cd "${tmp}" && ROADMAP_PATH="${rel_path}" bash "${CHECKER}" 2>&1)"
    local actual_exit=$?

    if [[ ${actual_exit} -ne ${expected_exit} ]]; then
        record_fail "taxonomy: ${description} (expected exit ${expected_exit}, got ${actual_exit})"
        return
    fi
    if [[ -n "${expected_match}" ]] && ! grep -qF "${expected_match}" <<<"${output}"; then
        record_fail "taxonomy: ${description} (exit OK but expected output to contain '${expected_match}')"
        return
    fi
    record_pass "taxonomy: ${description} (exit ${expected_exit})"
}
```

Add two calls after the existing `run_roadmap_fixture` calls (reuse the existing `bad-roadmap-sprint.md` fixture — its content doesn't need to change, only where it's placed):

```bash
run_roadmap_fixture_custom_path "bad-roadmap-sprint.md" "docs/roadmap.md" 1 "ROADMAP_PATH override finds violation at custom path" "Sprint K:"
run_roadmap_fixture_custom_path "conformant-roadmap.md" "docs/roadmap.md" 0 "ROADMAP_PATH override: clean roadmap at custom path passes"
```

**Acceptance Test:**

```bash
bash tests/taxonomy/run.sh   # expect all existing + 2 new PASS, 0 FAIL
```

---

## What NOT to Do

- **Do not make `planning.md`'s path configurable.** Not in scope — see Design Philosophy. `scan_roadmap_file` already handles a missing `planning.md` gracefully.
- **Do not add a CLI flag as an alternative to the env var.** The issue explicitly asks for an env var mirroring `VERSION_GUARD_REPO_SLUG`; two mechanisms for the same knob is unnecessary surface area.
- **Do not attempt to fix the symlink footgun itself** (e.g., by making `git show` dereference symlinks, or by switching to reading the working-tree file instead of `origin/main`'s committed copy for the cross-branch comparison). That would be a much larger, riskier change to the comparison semantics (working-tree vs. committed-on-main is a meaningful distinction the whole collision-detection design depends on) for a footgun that's fully avoidable by just setting `ROADMAP_PATH` correctly in the first place. Document it; don't engineer around it.
- **Do not skip the "default behavior unchanged" half of each test.** Every new test case in Changes 5-6 must prove BOTH that the override works AND that the default path still behaves exactly as before — a fix that silently changes default behavior for the 6 consumers already at the default path would be worse than the bug it fixes.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/check_version_collision.py` | Modify | `ROADMAP_PATH` env var, symlink-footgun docstring warning |
| `scripts/claim_roadmap_version.py` | Modify | `ROADMAP_PATH` env var, symlink-footgun docstring warning |
| `scripts/check_spec_taxonomy.sh` | Modify | `ROADMAP_PATH` env var for the ROADMAP.md scan target |
| `docs/CI-INTEGRATION.md` | Modify | New "Non-default roadmap location" section + troubleshooting row |
| `tests/version-collision/run.sh` | Modify | 2 new checks (custom-path coverage for both Python scripts) |
| `tests/taxonomy/run.sh` | Modify | New helper + 2 new checks (custom-path coverage for the bash checker) |

## Implementation Order

1. Change 1 (`check_version_collision.py`) — independent, do first.
2. Change 2 (`claim_roadmap_version.py`) — independent of Change 1, same pattern.
3. Change 3 (`check_spec_taxonomy.sh`) — independent, same pattern in bash.
4. Change 4 (docs) — depends on Changes 1-3 existing so the documentation is accurate.
5. Change 5 (test coverage for the Python scripts) — depends on Changes 1-2.
6. Change 6 (test coverage for the bash checker) — depends on Change 3.

## Verification Checklist

- [ ] `check_version_collision.py` reads `ROADMAP_PATH`, defaults to `ROADMAP.md`, docstring warns about the symlink footgun
- [ ] `claim_roadmap_version.py` reads `ROADMAP_PATH`, defaults to `ROADMAP.md`, docstring warns about the symlink footgun
- [ ] `check_spec_taxonomy.sh` reads `ROADMAP_PATH` for the ROADMAP.md scan target only (not `planning.md`)
- [ ] `docs/CI-INTEGRATION.md` documents the env var and the symlink footgun
- [ ] `tests/version-collision/run.sh` passes 14/14 (12 existing + 2 new)
- [ ] `tests/taxonomy/run.sh` passes all existing + 2 new
- [ ] `./scripts/gate_fast.sh` passes (224 + 2 + 2 = 228 PASS expected)
- [ ] Dogfood: `python3 scripts/check_version_collision.py .` against dev-platform's own repo still reports correctly with `ROADMAP_PATH` unset (default path unaffected)
- [ ] No hardcoded settings introduced — the whole point of this spec is removing one
- [ ] Language architecture matrix followed (bugfix only, no new components, no language changes)
