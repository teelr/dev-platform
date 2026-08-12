# v1.12: Version Guard List-Form Roadmap Support

## Coding Specification for Implementation

## Design Philosophy

v1.11 promoted `scripts/claim_roadmap_version.py` and `scripts/check_version_collision.py` from kermit-v3 into dev-platform, verbatim, per that spec's explicit "no logic changes" instruction. Both scripts detect Roadmap Phase version headers in `ROADMAP.md` with a regex that only matches the **heading form** — `## v<MAJOR>.<MINOR>: <Title>` — because that's the convention kermit-v3's own `ROADMAP.md` uses. dev-platform's own `ROADMAP.md` uses a different, equally legitimate convention instead: the **list form** — `- **v<MAJOR>.<MINOR>: <Title>** *(status — date, ...)* — description`. dev-platform's own `check_spec_taxonomy.sh` (the working, proven taxonomy checker) explicitly documents and supports BOTH forms (`scripts/check_spec_taxonomy.sh:109-111`: "Both forms count as headers: `- **<title>**` (markdown list item) and `## <title>` (heading)."); the promoted scripts support only one of the two.

**Practical consequence, discovered live during v1.11's own post-merge:** against dev-platform's own `ROADMAP.md`, `check_version_collision.py`'s regex never matches anything — every run reports "no new Roadmap Phase version headers introduced," not because nothing changed, but because the check can't see list-form entries at all. This means the `version-collision` CI job added to `taxonomy-check.yml` in v1.11 (already live on `main`, running on every PR since PR #60 merged) currently provides **zero actual protection** for dev-platform and any consumer using the list-form convention — it silently passes every time, which is worse than not running at all, because it looks like coverage that isn't there. This is exactly the "confident PASS on a broken check" failure mode `tasks/lessons.md`'s 2026-06-28 entry warns about (a different check, same shape of mistake).

This spec fixes both scripts to detect BOTH forms — mirroring `check_spec_taxonomy.sh`'s own dual-form pattern rather than inventing a new one — and adds test coverage using dev-platform's REAL `ROADMAP.md` format (list-form) as the primary fixture, since that's the format that was silently broken; heading-form gets a smaller supplementary check proving the fix didn't regress kermit-v3's own convention. `commands/plan.md`'s Step 2 prose (which currently says "the highest `` ## v<N>.<M>: `` header in `ROADMAP.md`," inheriting the same wrong assumption) is corrected in the same pass.

**Deliberately out of scope:** an optional letter suffix on the version (`v<MAJOR>.<MINOR>[<letter>]`, e.g. `v0.4a`) is part of `check_spec_taxonomy.sh`'s documented format but was ALSO never supported by the original kermit-v3 regexes — no live `ROADMAP.md` entry currently uses one, so this is a pre-existing, undemonstrated gap, not a live bug. Fixing it here would widen scope beyond what's actually broken; left as a known limitation, same treatment as v1.11's `/review`-flagged `_gh_available()` `or`/`and` quirk.

**Branching:** single Phase, single PR. The diff is small (~2 script edits + 1 test-fixture edit + doc corrections, well under the ~150-200 LOC threshold) — matches the v0.6 "small Roadmap Phase" precedent in the Per-Spec-Phase branching decision rule.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/claim_roadmap_version.py`, `scripts/check_version_collision.py` edits | Python | Fixing existing Python files in place — no new component, no language choice to make. |
| `tests/version-collision/run.sh` edits | Bash | Extending the existing suite in its established language, matching every other `tests/<suite>/run.sh`. |

## Overview

1. **Phase 1 — Dual-form regex support** (Changes 1–4): fix both scripts' version-detection regexes to match `check_spec_taxonomy.sh`'s own dual-form pattern, correct `commands/plan.md`'s Step 2 prose, and add list-form + heading-form test coverage.

---

## Phase 1: Dual-Form Regex Support

### Change 1: `scripts/claim_roadmap_version.py` — dual-form `_ROADMAP_VERSION_RE`

**Problem:** `_highest_minor_in_roadmap()` (line 55) uses `_ROADMAP_VERSION_RE` to find the highest `v<MAJOR>.<MINOR>` already present in `origin/main`'s `ROADMAP.md`. Against dev-platform's own list-form `ROADMAP.md`, this always returns 0 — the script silently falls back to trusting GitHub milestones alone for the roadmap-side half of its `max(roadmap_high, milestone_high) + 1` computation. Milestones happen to still be authoritative in practice (nothing currently edits `ROADMAP.md` by hand ahead of a milestone), so this hasn't caused a wrong claim yet — but it's a real, demonstrated gap, not a hypothetical one.

**File:** `scripts/claim_roadmap_version.py`, line 26

**Implementation:**

Change:

```python
_ROADMAP_VERSION_RE = re.compile(r"^## v(\d+)\.(\d+):", re.MULTILINE)
```

to:

```python
_ROADMAP_VERSION_RE = re.compile(r"^(?:## |- \*\*)v(\d+)\.(\d+):", re.MULTILINE)
```

This mirrors `scripts/check_spec_taxonomy.sh:112`'s `KILLED_ROADMAP_RE='^(- \*\*|## )...'` prefix alternation exactly — the two capture groups (major, minor) are unaffected, so no other line in this function needs to change; `_highest_minor_in_roadmap()`'s `_ROADMAP_VERSION_RE.findall(roadmap_text)` loop already unpacks `(maj_s, min_s)` correctly regardless of which prefix matched.

**Acceptance Test:**

```bash
python3 -c "
import re
pat = re.compile(r'^(?:## |- \*\*)v(\d+)\.(\d+):', re.MULTILINE)
assert pat.findall('## v0.5: Heading Form\n') == [('0', '5')]
assert pat.findall('- **v0.5: List Form** *(complete)* — desc\n') == [('0', '5')]
print('OK')
"
```

---

### Change 2: `scripts/check_version_collision.py` — dual-form `_VERSION_HEADER_RE`

**Problem:** Same root cause as Change 1, but this is the more serious instance — `_versions_in()` (line 49) feeds directly into the "new version" and "reused version, different title" collision checks that are the entire point of this script and the `version-collision` CI job. Against dev-platform's own `ROADMAP.md`, both collision-detection layers are currently dead code paths: `new_versions` and `reused_versions` are always empty dicts, so the function always takes the `if not new_versions and not reused_versions: return 0` early-exit at line 96, printing "OK: no new Roadmap Phase version headers introduced" regardless of what actually changed.

**File:** `scripts/check_version_collision.py`, lines 37, 49-53

**Implementation:**

Heading-form and list-form need different "where does the title end" logic (heading-form stops at an em-dash or end-of-line; list-form stops at the closing `**`), so this is two regexes merged in `_versions_in()`, not one combined pattern — mirrors `check_spec_taxonomy.sh`'s clean prefix/content separation rather than forcing an unreadable single regex.

Replace line 37:

```python
_VERSION_HEADER_RE = re.compile(r"^## (v(\d+)\.(\d+)): (.+?)\s*(?:—.*)?$", re.MULTILINE)
```

with:

```python
_VERSION_HEADER_HEADING_RE = re.compile(r"^## (v(\d+)\.(\d+)): (.+?)\s*(?:—.*)?$", re.MULTILINE)
_VERSION_HEADER_LIST_RE = re.compile(r"^- \*\*(v(\d+)\.(\d+)): (.+?)\*\*", re.MULTILINE)
```

Replace `_versions_in()` (lines 49-53):

```python
def _versions_in(text: str) -> dict[str, str]:
    """version token (e.g. 'v0.74') -> title, for every '## v<N>.<M>: <Title>' header."""
    out: dict[str, str] = {}
    for full, _maj, _min, title in _VERSION_HEADER_RE.findall(text):
        out[full] = title.strip()
    return out
```

with:

```python
def _versions_in(text: str) -> dict[str, str]:
    """version token (e.g. 'v0.74') -> title, for every Roadmap Phase entry —
    heading form ('## v<N>.<M>: <Title>') or list form
    ('- **v<N>.<M>: <Title>** ...'), matching check_spec_taxonomy.sh's
    dual-form support."""
    out: dict[str, str] = {}
    for full, _maj, _min, title in _VERSION_HEADER_HEADING_RE.findall(text):
        out[full] = title.strip()
    for full, _maj, _min, title in _VERSION_HEADER_LIST_RE.findall(text):
        out[full] = title.strip()
    return out
```

**Acceptance Test:**

```bash
python3 -c "
import sys
sys.path.insert(0, 'scripts')
from check_version_collision import _versions_in
assert _versions_in('## v0.5: Heading Form\n') == {'v0.5': 'Heading Form'}
assert _versions_in('- **v1.10: List Form** *(complete — 2026-01-01)* — desc\n') == {'v1.10': 'List Form'}
both = _versions_in('## v0.5: Heading Form\n- **v1.10: List Form** *(complete)* — desc\n')
assert both == {'v0.5': 'Heading Form', 'v1.10': 'List Form'}, both
print('OK')
"
# Dogfood against dev-platform's own real ROADMAP.md — must now find its (many) list-form entries
python3 -c "
import sys
sys.path.insert(0, 'scripts')
from check_version_collision import _versions_in
from pathlib import Path
versions = _versions_in(Path('ROADMAP.md').read_text())
assert len(versions) > 5, f'expected many list-form entries, found {len(versions)}'
assert 'v1.10' in versions and versions['v1.10'] == 'Roadmap-Phase Completion', versions.get('v1.10')
print(f'OK — found {len(versions)} Roadmap Phase entries in dev-platform ROADMAP.md')
"
```

---

### Change 3: `commands/plan.md` — correct Step 2's ROADMAP.md fallback wording

**Problem:** Step 2 sub-step 3 says "the highest `` ## v<N>.<M>: `` header in `ROADMAP.md`" as the fallback major-version source — inheriting the same heading-form-only assumption Changes 1-2 fix in code. This is prose, not executable, so it never caused a wrong claim (an agent reading "highest header" would likely still find the right answer by eyeballing the file) — but it's actively wrong about the format dev-platform's own `ROADMAP.md` uses, and should say what's actually true now that Change 1 makes the fallback logic dual-form-aware.

**File:** `commands/plan.md` (find the line added by v1.11's Change 3, containing `` the highest `## v<N>.<M>:` header in `ROADMAP.md` ``)

**Implementation:**

Change:

```markdown
Then derive the major version from `planning.md`'s stated Active Roadmap Phase line (e.g. `**Active Roadmap Phase:** **v1.10 SHIPPED**` → major `1`), or the highest `## v<N>.<M>:` header in `ROADMAP.md` if `planning.md` has none.
```

to:

```markdown
Then derive the major version from `planning.md`'s stated Active Roadmap Phase line (e.g. `**Active Roadmap Phase:** **v1.10 SHIPPED**` → major `1`), or the highest `v<N>.<M>:` Roadmap Phase entry in `ROADMAP.md` if `planning.md` has none — entries appear as either `- **v<N>.<M>: <Title>**` (list form, dev-platform's own convention) or `## v<N>.<M>: <Title>` (heading form); both are valid.
```

**Acceptance Test:**

```bash
grep -n "## v<N>.<M>: .header in .ROADMAP.md" commands/plan.md && echo "FAIL: stale heading-only wording still present" || echo "PASS"
grep -n "list form, dev-platform's own convention" commands/plan.md
```

---

### Change 4: `tests/version-collision/run.sh` — list-form primary fixture + dual-form regression guard

**Problem:** Every existing assertion in this suite (added by v1.11) seeds `ROADMAP.md` with heading-form content (`## v0.1: Foundation`) — the format that was NEVER broken. None of the 10 existing assertions would have caught the actual bug, because none of them exercised dev-platform's real list-form convention. This is why `/code`'s self-review and `/review`'s independent pass both missed it.

**File:** `tests/version-collision/run.sh`

**Implementation:**

1. Change the seed `ROADMAP.md` content (currently `printf '## v0.1: Foundation\n' > ROADMAP.md` in the `SEED` setup block) to list-form, matching dev-platform's real convention:

   ```bash
   printf -- '- **v0.1: Foundation** *(complete — 2026-01-01)* — initial phase.\n' > ROADMAP.md
   ```

2. Update every existing `run_check`/`run_claim` call's inline `ROADMAP.md` content (Checks 1-10) from heading-form to the equivalent list-form, e.g.:

   ```bash
   # before:
   run_check '## v0.1: Foundation
   ' "${WORK}"
   # after:
   run_check -- '- **v0.1: Foundation** *(complete — 2026-01-01)* — initial phase.
   ' "${WORK}"
   ```

   Apply the same transform to every inline `## v0.X: <Title>` string across Checks 1-10 (both the `run_check` ROADMAP.md content arguments AND the canned milestone-title fixture files `v03_titles`/`v02_diff_title`, which stay unchanged since milestone titles never had a markdown prefix — only the `ROADMAP.md`-content arguments need the form change). Keep every assertion's PASS/FAIL logic and expected messages identical — only the input `ROADMAP.md` shape changes, proving the SAME 10 behaviors now work against the format that was actually broken.

3. Add two NEW assertions (Check 11, Check 12) proving heading-form STILL works after the fix — dual-form support, not a swap:

   ```bash
   # Check 11: heading-form still works for check_version_collision.py (new version, clean)
   run_check '## v0.1: Foundation
   ## v0.2: Widgets
   ' "${WORK}" VERSION_GUARD_REPO_SLUG=owner/repo MOCK_MILESTONES_FILE="${empty_titles}"
   if [[ ${RC} -eq 0 ]] && echo "${OUT}" | grep -q "OK: 1 new version header(s), no collision detected"; then
       record_pass "version-collision: heading-form ROADMAP.md still detected (dual-form regression guard)"
   else
       record_fail "version-collision: heading-form regressed — rc=${RC}, out=${OUT:0:200}"
   fi

   # Check 12: heading-form still works for claim_roadmap_version.py
   run_claim "Widgets" VERSION_GUARD_REPO_SLUG=owner/repo MOCK_MILESTONES_FILE="${empty_titles}"
   if [[ ${RC} -eq 0 ]] && echo "${OUT}" | grep -q "Claimed v0.2"; then
       record_pass "claim-roadmap-version: heading-form ROADMAP.md still detected (dual-form regression guard)"
   else
       record_fail "claim-roadmap-version: heading-form regressed — rc=${RC}, out=${OUT:0:200}"
   fi
   ```

   Check 11/12 need their OWN heading-form `${WORK}` — since step 1 above switched the shared `${WORK}`'s origin to list-form, reuse the pattern from `run_check`'s existing `<work-dir>` parameter (already supports an arbitrary work dir) by building a second small clone, OR simplest: `run_check`'s content argument fully overwrites `ROADMAP.md` each call regardless of what the file currently holds — so Check 11 can just pass heading-form content directly to the (list-form-seeded) `${WORK}`; the ONLY thing that must stay list-form for a meaningful regression guard is `origin/main`'s own `ROADMAP.md` (set once at `SEED` time, step 1) — reused_versions/new_versions comparisons work correctly either way since `_versions_in()` now merges both forms. Confirm this reasoning by re-reading `check_version_collision.py`'s `main()`: `local_versions` comes from the WORKING TREE file (whatever `run_check` just wrote), `main_versions` comes from `origin/main` (fixed at `SEED` time) — mixing forms across the two is exactly what proves dual-form support, not a test bug.

**Acceptance Test:**

```bash
bash tests/version-collision/run.sh
# Expect 12 PASS, 0 FAIL (10 existing, now against list-form + 2 new dual-form guards)
```

---

## What NOT to Do

- **Do not add letter-suffix support** (`v<MAJOR>.<MINOR>[<letter>]`) in this spec. It's a real gap in `check_spec_taxonomy.sh`'s documented format that neither the original kermit-v3 scripts nor this fix address, but no live `ROADMAP.md` entry uses one — adding it now widens scope beyond the demonstrated bug. File a lesson or backlog note if it ever bites.
- **Do not touch `_MILESTONE_TITLE_RE` or `_MILESTONE_VERSION_RE`.** Those match GitHub milestone TITLES (plain strings, no markdown prefix ever) — completely unrelated to the `ROADMAP.md`-parsing bug this spec fixes. Touching them would be an unrelated, unrequested change.
- **Do not fix the `_gh_available()` `or`/`and` quirk flagged during v1.11's `/review`** as part of this spec. Different bug, different root cause, already consciously deferred with its own documented rationale — bundling it here would blur two independent fixes into one PR.
- **Do not retag or reopen v1.11's milestone/release.** v1.11 already shipped; this is a normal same-week follow-up patch (v1.12), not a correction to history.
- **Do not swap the existing heading-form assertions for list-form and call it done** — Change 4 explicitly requires BOTH: list-form as primary (closes the real gap), heading-form as an explicit added regression guard (proves dual-form, not single-form-swap).

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/claim_roadmap_version.py` | Modify | `_ROADMAP_VERSION_RE` matches both heading-form and list-form |
| `scripts/check_version_collision.py` | Modify | `_VERSION_HEADER_RE` split into heading + list regexes, merged in `_versions_in()` |
| `commands/plan.md` | Modify | Step 2 fallback wording corrected to describe both forms |
| `tests/version-collision/run.sh` | Modify | Primary fixture switched to list-form (dev-platform's real convention); 2 new dual-form regression-guard assertions |

## Implementation Order

1. Change 1 (`claim_roadmap_version.py` regex) — independent, do first.
2. Change 2 (`check_version_collision.py` regex) — independent of Change 1, the more consequential fix.
3. Change 3 (`commands/plan.md` prose) — independent, quick.
4. Change 4 (test suite) — depends on Changes 1-2 being correct; validates them.

## Verification Checklist

- [ ] `scripts/claim_roadmap_version.py`'s `_ROADMAP_VERSION_RE` matches both `## v<N>.<M>:` and `- **v<N>.<M>:`
- [ ] `scripts/check_version_collision.py`'s `_versions_in()` correctly extracts titles from both forms, verified against dev-platform's own real `ROADMAP.md` (finds >5 entries, not 0)
- [ ] `commands/plan.md` no longer implies ROADMAP.md fallback only recognizes heading-form
- [ ] `tests/version-collision/run.sh` passes 12/12 (10 existing re-pointed at list-form + 2 new dual-form guards)
- [ ] `./scripts/gate_fast.sh` passes (222 + 2 = 224 PASS expected)
- [ ] Live dogfood: `python3 scripts/check_version_collision.py .` against dev-platform's own repo with this spec's own `ROADMAP.md` entry present correctly reports "1 new version header(s)" instead of "no new headers" (proves the fix against the exact real-world case that was broken)
- [ ] No hardcoded settings; language architecture matrix not implicated (bugfix only, no new components)
