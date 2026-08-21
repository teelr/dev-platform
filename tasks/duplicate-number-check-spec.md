# v1.17: Duplicate Number Check

## Coding Specification for Implementation

## Design Philosophy

[teelr/dev-platform#75](https://github.com/teelr/dev-platform/issues/75) reports a real collision: kermit-v3 PR #481 (2026-08-21) needed to merge `main` after two other in-flight PRs (#478 and another) both filed a new row in `tasks/HARNESS_HANDOFF_QUEUE.md` claiming the same next-free number, **Ask #51** — for two unrelated harness gaps. Git merged both rows cleanly (different line positions, zero text conflict), leaving a silent semantic duplicate that nothing caught until a human happened to notice. The same day, two PRs also both claimed `tasks/lessons.md`'s **L60** — that one at least showed up as a real git conflict (both inserted at the same "last entry" anchor), but resolving it correctly (renumber the loser to L61, including every cross-reference) was a manual judgment call, not something tooling verified. Both numbering schemes are two-Roadmap-Phases-in-flight-at-once collisions — exactly the shape `check_version_collision.py` (v1.11/v1.12) already guards against for `ROADMAP.md` versions.

**Why this can't reuse `claim_roadmap_version.py`'s claim-ahead-of-time approach.** A Roadmap Phase version has a live external arbiter — a GitHub milestone — so `/plan` can atomically claim it before any file is even touched. A handoff-queue row or a lessons entry has no such arbiter: the number only exists as text inside one file, and the collision only becomes *real* at merge time, when two independently-authored branches both land. So the fix shape here is the simpler one the issue itself proposes: a mechanical **duplicate-number check** — grep the file for a repeated key, fail if any repeat — run at gate time (and therefore in CI on every PR), not a pre-claim script.

**Scope, per the Scope rule.** Both `tasks/HARNESS_HANDOFF_QUEUE.md`'s "Ask #" numbering and `tasks/lessons.md`'s "L#" numbering are conventions three Kermit-harness-consumer projects (kermit-v3, Keystone, kermit-pa) independently adopted — dev-platform doesn't own their files and this spec does not write into `projects/<name>/`. What dev-platform *does* ship: a reusable, generic checker + a documented adoption pattern (`docs/RULE_RATIONALE.md`, Kermit-Specific Rules section — this is squarely consumer-shaped, unlike the universal docs-only-diff skip, so it does NOT get a `CLAUDE.md` gate-tier mention; it gets one clause added to `CLAUDE.md`'s existing pointer-list at line 5, the same spot that already sends Kermit-project sessions to `docs/RULE_RATIONALE.md` for kwarg propagation / boundary sweeps / triage). Post-merge files handoff issues on the three consumer repos rather than touching their trees, mirroring v1.14's pattern exactly.

**The file shapes are NOT uniform — verified live, not assumed.** The issue itself flagged this as worth checking before assuming all three need an identical check, and it's true:

- **kermit-v3**: `tasks/HARNESS_HANDOFF_QUEUE.md` has **5** independently-numbered tables, each headed literally `| # | ... |` (Pending/Ask, Pending/Feature-path, Harness-primitive-gaps, Migrated, Pre-existing-legacy-debt). `tasks/lessons.md` uses `## L<N> — <title>` headers, not in file order (consolidated/renumbered over time).
- **Keystone**: same `tasks/lessons.md` `## L<N>` convention (up to L272 today). Its `HARNESS_HANDOFF_QUEUE.md` has **4** of the same `| # | ... |`-headed tables — but NOT kermit-v3's specific `| # | Date | Ask | Status |` table; its outbound-communiques table (`| Date | Communique | Asks covered | Status |`) has no `#` column at all and correctly falls outside this check.
- **kermit-pa**: same `## L<N>` lessons.md convention, but its `HARNESS_HANDOFF_QUEUE.md` has **zero** `#`-headed tables — a completely different shape (`| Date | Feature | Where it lives | Why harness-shaped | Migration plan |`), confirmed live by grepping the file. The queue-table check is a correct no-op there; the lessons check still applies.

This is why the checker (Change 1) is generic — "any table whose header row's first cell is literally `#`, checked for duplicates within that one table's data rows" — rather than hardcoding kermit-v3's specific column layout or a fixed table count. It naturally adapts to 5 tables, 4 tables, or 0 tables without per-project configuration, the same way `check_spec_taxonomy.sh`'s two independent scan passes each no-op cleanly when their target has nothing to check.

**Why the check must be table-SCOPED, not whole-file.** Verified live against kermit-v3's real, current `tasks/HARNESS_HANDOFF_QUEUE.md`: the raw first-column value `39` appears twice in the file today, and so does `37` — but each pair sits in two *different*, independently-numbered tables (e.g. Ask #39 in the Pending/Ask table is unrelated to gap #39 in the Pending/Feature-path table). A naive whole-file "grep for repeated `| N |`" would falsely flag both as violations on a perfectly healthy file. The checker must track a fresh "seen" set per table, reset at each new `| # | ... |` header row — verified by hand-simulating the exact algorithm against the live file before writing this spec (5 tables detected, 0 false violations). It must also NOT collapse an intentional variant like `46` vs. `46R` (a real row in kermit-v3's file — `46R` marks a documented regression follow-up, not a duplicate of `46`) — exact-string comparison of the trimmed first cell handles this correctly for free, no special-casing needed.

**Language:** bash, matching `check_spec_taxonomy.sh` exactly — same class of problem (line-oriented regex/state-tracking over a markdown file), same lift-check tier, zero network I/O, no new runtime dependency. See Language Decisions below.

**Branching:** single Phase, single PR — comparable diff size to v1.13/v1.14 (one new ~120-line script, one new ~90-line test suite + 6 small fixtures, a 3-line gate wiring change, two doc edits).

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/check_duplicate_numbering.sh` | Bash | Line-oriented text/regex scan over a markdown file, invoked from the existing bash `gate_fast.sh` orchestrator — identical shape to the existing `check_spec_taxonomy.sh`. No network I/O, no JSON, no case for Python's stdlib. |
| `tests/duplicate-numbering/run.sh` | Bash | Matches every other `tests/<suite>/run.sh` in this repo (see `tests/taxonomy/run.sh`, `tests/docs-only-skip/run.sh`). |

No network I/O, no LLM calls, no UI — squarely a bash scripting task, not a Language Matrix Go/Rust/Python candidate.

## Overview

1. **Phase 1 — Duplicate Number Check** (Changes 1–5): ship the generic table-scoped + lessons-header duplicate checker, prove it against the exact collision shapes verified live (in-table duplicate, cross-table reuse that must NOT flag, missing file, wrong-convention file), wire it into dev-platform's own `gate_fast.sh` as the reference implementation, and document the adoption pattern for the three consumer projects.

---

## Phase 1: Duplicate Number Check

### Change 1: `scripts/check_duplicate_numbering.sh` — the checker (new file)

**Problem:** Need a single, generic, offline script that (a) scans any markdown table headed literally `| # | ... |` for duplicate first-column values *within that one table* (queue-file shape), and (b) scans `## L<N> — <title>` headings for duplicate `<N>` *globally across the whole file* (lessons-file shape) — each pass skipping gracefully (not erroring) when its target file is absent or simply doesn't use the convention, since two of the three consumer projects don't share kermit-v3's exact queue-table shape.

**File:** `scripts/check_duplicate_numbering.sh` (new)

**Implementation:**

```bash
#!/usr/bin/env bash
# check_duplicate_numbering.sh
#
# Constitutional check for the shared "Ask #N" / "L#" numbering conventions
# used by Kermit-harness-consumer projects (kermit-v3, Keystone, kermit-pa)
# in their tasks/HARNESS_HANDOFF_QUEUE.md and tasks/lessons.md files. Two
# Roadmap Phases in flight at once can each independently pick the next
# free number for a new queue row or lessons entry; git merges the text
# cleanly (different line positions), leaving a silent duplicate nothing
# caught until a human noticed. See teelr/dev-platform#75.
#
# Two independent scan passes, each a graceful no-op (not an error) when its
# target file is absent or doesn't use the convention at all:
#
# (1) Handoff-queue tables: any markdown table whose header row's first
#     column is literally "#". A queue file legitimately has SEVERAL such
#     tables (Pending, Migrated, ...), each independently numbered — the
#     same value repeating across two DIFFERENT tables is fine and must
#     NOT be flagged; only a repeat within the SAME table's data rows is a
#     violation. Table scope resets at every new "| # | ... |" header row
#     and ends at the first line that doesn't start with "|".
#
# (2) Lessons headers: "## L<N> — <title>" headings, checked for duplicate
#     <N> globally across the whole file (no per-table scoping — lessons.md
#     is one running numbered list, not independently-numbered tables).
#
# Usage:
#   ./check_duplicate_numbering.sh                   # check ./tasks/
#   ./check_duplicate_numbering.sh /path/to/project   # check <path>/tasks/
#
# Override the default file paths (relative to the project root) if a
# project's layout differs from the kermit-v3/Keystone/kermit-pa convention:
#   HANDOFF_QUEUE_PATH="tasks/HARNESS_HANDOFF_QUEUE.md"
#   LESSONS_PATH="tasks/lessons.md"
#
# Exit codes:
#   0 — no duplicates found (includes "file absent" / "convention unused")
#   1 — at least one duplicate found

set -uo pipefail

PROJECT_ROOT="${1:-.}"
: "${HANDOFF_QUEUE_PATH:=tasks/HARNESS_HANDOFF_QUEUE.md}"
: "${LESSONS_PATH:=tasks/lessons.md}"

QUEUE_FILE="${PROJECT_ROOT}/${HANDOFF_QUEUE_PATH}"
LESSONS_FILE="${PROJECT_ROOT}/${LESSONS_PATH}"

found_violations=0

# ---------------------------------------------------------------------------
# Pass (1): handoff-queue tables — duplicate "#" column values within ONE table
# ---------------------------------------------------------------------------
check_queue_file() {
    local f="$1"
    if [[ ! -f "$f" ]]; then
        echo "check_duplicate_numbering: no ${HANDOFF_QUEUE_PATH} — skipping queue-table check"
        return 0
    fi

    local -A seen_line=()
    local in_table=0 table_idx=0 table_count=0 lineno=0 violations_here=0

    while IFS= read -r line; do
        lineno=$((lineno + 1))

        if [[ "$line" != \|* ]]; then
            in_table=0
            continue
        fi

        local rest="${line#|}"
        local first="${rest%%|*}"
        first="$(echo "$first" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        if [[ "$first" == "#" ]]; then
            table_idx=$((table_idx + 1))
            table_count=$((table_count + 1))
            in_table=1
            continue
        fi

        [[ "$in_table" -eq 1 ]] || continue
        [[ "$first" =~ ^:?-+:?$ ]] && continue   # separator row (---, :---, ---: , -)
        [[ -z "$first" ]] && continue

        local key="${table_idx}:${first}"
        if [[ -n "${seen_line[$key]:-}" ]]; then
            echo "  ${f#"$PROJECT_ROOT"/}:${lineno}: duplicate '#${first}' in table #${table_idx} (first seen at line ${seen_line[$key]})"
            violations_here=1
        else
            seen_line[$key]="$lineno"
        fi
    done < "$f"

    if [[ "$table_count" -eq 0 ]]; then
        echo "check_duplicate_numbering: ${HANDOFF_QUEUE_PATH} has no '#'-headed tables — skipping queue-table check"
        return 0
    fi

    if [[ "$violations_here" -eq 1 ]]; then
        echo "check_duplicate_numbering: duplicate row numbers in ${f#"$PROJECT_ROOT"/}"
        return 1
    fi

    echo "check_duplicate_numbering: ${HANDOFF_QUEUE_PATH} — ${table_count} table(s), no duplicate row numbers"
    return 0
}

if ! check_queue_file "$QUEUE_FILE"; then
    found_violations=1
fi

# ---------------------------------------------------------------------------
# Pass (2): lessons.md "## L<N> —" headers — duplicate <N> across the WHOLE file
# ---------------------------------------------------------------------------
check_lessons_file() {
    local f="$1"
    if [[ ! -f "$f" ]]; then
        echo "check_duplicate_numbering: no ${LESSONS_PATH} — skipping lessons-L# check"
        return 0
    fi

    local -A seen_line=()
    local lineno=0 header_count=0 violations_here=0

    while IFS= read -r line; do
        lineno=$((lineno + 1))
        if [[ "$line" =~ ^##[[:space:]]+L([0-9]+)([[:space:]]|$) ]]; then
            local key="${BASH_REMATCH[1]}"
            header_count=$((header_count + 1))
            if [[ -n "${seen_line[$key]:-}" ]]; then
                echo "  ${f#"$PROJECT_ROOT"/}:${lineno}: duplicate 'L${key}' header (first seen at line ${seen_line[$key]})"
                violations_here=1
            else
                seen_line[$key]="$lineno"
            fi
        fi
    done < "$f"

    if [[ "$header_count" -eq 0 ]]; then
        echo "check_duplicate_numbering: ${LESSONS_PATH} has no '## L<N>' headers — skipping lessons-L# check"
        return 0
    fi

    if [[ "$violations_here" -eq 1 ]]; then
        echo "check_duplicate_numbering: duplicate lesson numbers in ${f#"$PROJECT_ROOT"/}"
        return 1
    fi

    echo "check_duplicate_numbering: ${LESSONS_PATH} — ${header_count} L# header(s), no duplicates"
    return 0
}

if ! check_lessons_file "$LESSONS_FILE"; then
    found_violations=1
fi

if [[ "$found_violations" -ne 0 ]]; then
    echo ""
    echo "Fix: renumber the later-added row/entry to the next free number,"
    echo "  updating every cross-reference to the old number in the same commit."
    exit 1
fi

echo "check_duplicate_numbering: all checks clean"
exit 0
```

Note the known, deliberate limitation (document in the file header comment, already included above): a table interrupted mid-body by a non-`|`-starting line (e.g. a blockquote spliced between data rows) ends that table's scope early — any rows after the interruption are silently unscanned rather than falsely flagged. This is the same "conservative by construction — never guess" posture as `scripts/lib/docs_only_diff.sh`; it has not been observed in any of the three consumer projects' real files (verified by inspection during planning).

**Acceptance Test:**

```bash
bash -n scripts/check_duplicate_numbering.sh   # syntax check
./scripts/check_duplicate_numbering.sh .       # dev-platform has neither file — expect clean skip, exit 0
```

---

### Change 2: `tests/duplicate-numbering/` — fixture suite (new)

**Problem:** The checker's correctness hinges on exactly the distinctions verified during planning — in-table duplicate vs. cross-table reuse, L# convention present vs. absent, missing files, path overrides — each needs its own fixture and assertion, not just a single happy-path smoke test (per the "assert on the SPECIFIC failure cause" and "test the cross product" lessons in `tasks/lessons.md`).

**Files:** `tests/duplicate-numbering/run.sh` + `tests/duplicate-numbering/fixtures/*.md` (all new)

**Implementation:**

`tests/duplicate-numbering/fixtures/clean-queue.md`:

```markdown
# Test Queue

## Pending

| # | Date | Ask | Status |
| --- | --- | --- | --- |
| 1 | 2026-01-01 | First ask | Open |
| 2 | 2026-01-02 | Second ask | Open |
```

`tests/duplicate-numbering/fixtures/dup-queue.md`:

```markdown
# Test Queue

## Pending

| # | Date | Ask | Status |
| --- | --- | --- | --- |
| 1 | 2026-01-01 | First ask | Open |
| 2 | 2026-01-02 | Second ask | Open |
| 2 | 2026-01-03 | Third ask — wrongly reused #2 | Open |
```

`tests/duplicate-numbering/fixtures/cross-table-queue.md` (the exact "must NOT flag" shape verified against kermit-v3's real file — same number, two independently-numbered tables):

```markdown
# Test Queue

## Pending

| # | Date | Ask | Status |
| --- | --- | --- | --- |
| 1 | 2026-01-01 | First ask | Open |
| 2 | 2026-01-02 | Second ask | Open |

## Harness primitive gaps

| # | Date raised | Primitive | Status |
| --- | --- | --- | --- |
| 1 | 2026-01-05 | Independently-numbered gap | Open |
| 2 | 2026-01-06 | Another independently-numbered gap | Open |
```

`tests/duplicate-numbering/fixtures/clean-lessons.md`:

```markdown
# Lessons

## L1 — first lesson

Some text.

## L2 — second lesson

Some text.
```

`tests/duplicate-numbering/fixtures/dup-lessons.md`:

```markdown
# Lessons

## L1 — first lesson

Some text.

## L2 — second lesson

Some text.

## L2 — third lesson, wrongly reused L2

Some text.
```

`tests/duplicate-numbering/fixtures/non-l-lessons.md` (dev-platform's OWN `tasks/lessons.md` shape — a date table, zero L# headers — must skip cleanly, not error):

```markdown
# Lessons Learned

## Active Lessons

| Date | Lesson | Project | Status |
| ---- | ------ | ------- | ------ |
| 2026-01-01 | Some lesson text | test-project | active |
```

`tests/duplicate-numbering/run.sh`:

```bash
#!/usr/bin/env bash
# tests/duplicate-numbering/run.sh — self-test for
# scripts/check_duplicate_numbering.sh. Each fixture gets its own throwaway
# tasks/ dir. The cross-table fixture is the load-bearing regression guard:
# it proves the checker distinguishes "duplicate WITHIN one table" (real
# bug) from "same number reused across two independently-numbered tables"
# (legitimate — verified against kermit-v3's real file during planning).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

CHECKER="${REPO}/scripts/check_duplicate_numbering.sh"

run_fixture() {
    local target_name="$1" fixture="$2" expected_exit="$3" description="$4" expected_match="${5:-}"
    local tmp
    tmp="$(mktemp -d)"
    trap "rm -rf '${tmp}'" RETURN

    mkdir -p "${tmp}/tasks"
    cp "${HERE}/fixtures/${fixture}" "${tmp}/tasks/${target_name}"

    local output
    output="$(bash "${CHECKER}" "${tmp}" 2>&1)"
    local actual_exit=$?

    if [[ ${actual_exit} -ne ${expected_exit} ]]; then
        record_fail "duplicate-numbering: ${description} (expected exit ${expected_exit}, got ${actual_exit})"
        return
    fi
    if [[ -n "${expected_match}" ]] && ! grep -qF "${expected_match}" <<<"${output}"; then
        record_fail "duplicate-numbering: ${description} (exit OK but output missing '${expected_match}')"
        return
    fi
    record_pass "duplicate-numbering: ${description} (exit ${expected_exit})"
}

# Queue-table checks
run_fixture "HARNESS_HANDOFF_QUEUE.md" "clean-queue.md"       0 "single clean table passes"
run_fixture "HARNESS_HANDOFF_QUEUE.md" "dup-queue.md"         1 "duplicate '#2' within one table detected" "duplicate '#2'"
run_fixture "HARNESS_HANDOFF_QUEUE.md" "cross-table-queue.md" 0 "same number reused across two DIFFERENT tables is NOT flagged"

# Lessons L# checks
run_fixture "lessons.md" "clean-lessons.md" 0 "sequential L# headers pass"
run_fixture "lessons.md" "dup-lessons.md"   1 "duplicate L2 header detected" "duplicate 'L2'"
run_fixture "lessons.md" "non-l-lessons.md" 0 "date-table lessons.md (no L# convention) skips cleanly"

# Missing-files case: neither file present at all
tmp="$(mktemp -d)"
mkdir -p "${tmp}/tasks"
output="$(bash "${CHECKER}" "${tmp}" 2>&1)"
actual_exit=$?
rm -rf "${tmp}"
if [[ ${actual_exit} -eq 0 ]]; then
    record_pass "duplicate-numbering: neither file present -> clean skip (exit 0)"
else
    record_fail "duplicate-numbering: neither file present -> clean skip (expected exit 0, got ${actual_exit})"
fi

# HANDOFF_QUEUE_PATH / LESSONS_PATH override -- custom project layout. Proves
# the override is genuinely read, not silently ignored: points at a
# known-duplicate file at a NON-default path, and a NON-existent lessons
# path, so only a correctly-wired override produces exit 1 here.
tmp="$(mktemp -d)"
mkdir -p "${tmp}/docs"
cp "${HERE}/fixtures/dup-queue.md" "${tmp}/docs/queue.md"
output="$(HANDOFF_QUEUE_PATH="docs/queue.md" LESSONS_PATH="docs/nonexistent-lessons.md" bash "${CHECKER}" "${tmp}" 2>&1)"
actual_exit=$?
rm -rf "${tmp}"
if [[ ${actual_exit} -eq 1 ]]; then
    record_pass "duplicate-numbering: HANDOFF_QUEUE_PATH override reads the custom path"
else
    record_fail "duplicate-numbering: HANDOFF_QUEUE_PATH override reads the custom path (expected exit 1, got ${actual_exit})"
fi

echo ""
echo "duplicate-numbering: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL, ${SKIP_COUNT} SKIP"
[[ "${FAIL_COUNT}" -eq 0 ]]
```

**Acceptance Test:**

```bash
bash tests/duplicate-numbering/run.sh   # expect 8 PASS, 0 FAIL
```

---

### Change 3: `scripts/gate_fast.sh` — wire in as a lift check

**Problem:** The checker needs to actually run on every `/gate fast` (and therefore every CI run) to catch a collision before merge, not just exist as a standalone script. dev-platform's own repo has neither target file, so this wiring proves the reference-implementation pattern (per the Scope rule) rather than protecting dev-platform's own content.

**File:** `scripts/gate_fast.sh`, immediately after the existing "Taxonomy enforcement" lift-check block (~line 36-41).

**Implementation:**

Insert immediately after the existing block:

```bash
if (cd "${REPO}" && bash scripts/check_spec_taxonomy.sh >/dev/null 2>&1); then
    record_pass "spec taxonomy"
else
    record_fail "spec taxonomy (check_spec_taxonomy.sh exit 1)"
fi
```

add:

```bash
# Duplicate-number check (Kermit-consumer handoff-queue "Ask #" rows +
# lessons.md "L#" headers). dev-platform itself has neither convention, so
# this is a graceful no-op here — the reference implementation for the
# three consumer projects that DO use it (see docs/RULE_RATIONALE.md).
if (cd "${REPO}" && bash scripts/check_duplicate_numbering.sh >/dev/null 2>&1); then
    record_pass "duplicate numbering (handoff-queue / lessons)"
else
    record_fail "duplicate numbering (check_duplicate_numbering.sh exit 1)"
fi
```

**Acceptance Test:**

```bash
./scripts/gate_fast.sh 2>&1 | grep "duplicate numbering"   # expect: PASS  duplicate numbering (handoff-queue / lessons)
```

---

### Change 4: `docs/RULE_RATIONALE.md` — new "Duplicate Numbering Check" section

**Problem:** The pattern needs a documented adoption guide the three consumer projects' own sessions can port from in one read — same shape as the "Gate-Fast Docs-Only Diff Skip" section, but placed under "Kermit-Specific Rules" since this pattern (unlike the docs-only-diff skip) is not universal to every project's gate — it only matters to Kermit-harness consumers using this specific queue/lessons convention.

**File:** `docs/RULE_RATIONALE.md`, appended at the end of the file (after the existing "Architectural Triage — Harness vs Consumer" section, which is what defines the handoff-queue file this check operates on).

**Implementation:**

Append:

```markdown

## Duplicate Numbering Check — Handoff-Queue "Ask #" / Lessons "L#"

Two Kermit-harness-consumer conventions have no live external arbiter the way a Roadmap Phase version does (`check_version_collision.py` can ask GitHub whether a milestone number is taken; these can't ask anything): `tasks/HARNESS_HANDOFF_QUEUE.md`'s "Ask #" row numbers, and `tasks/lessons.md`'s "L#" entry headers. Two Roadmap Phases in flight at once can each independently pick the next free number; git merges the text cleanly (different line positions — sometimes not even a real conflict), leaving a silent duplicate nothing catches until a human notices. Live incident: kermit-v3 PR #481 (2026-08-21) hit both — a queue row collision on Ask #51 that merged with zero text conflict, and an L60 collision that at least showed up as a real git conflict. [teelr/dev-platform#75](https://github.com/teelr/dev-platform/issues/75).

**Unlike the version-collision guard, this can't claim ahead of time.** The number only exists as text inside one file; the collision only becomes real at merge time. So the fix is the simpler shape the issue itself proposed: a mechanical duplicate-number check run at gate time (and therefore in CI on every PR), not a pre-claim script.

**The three consumer projects do NOT share one file shape — verified live, not assumed:**

- **kermit-v3**: 5 independently-numbered `| # | ... |`-headed tables in `HARNESS_HANDOFF_QUEUE.md`; `## L<N> —` headers in `lessons.md` (not in file order — consolidated/renumbered over time).
- **Keystone**: same `## L<N>` lessons convention; 4 of the same `| # | ... |`-headed queue tables, but not kermit-v3's specific Ask table — its outbound-communiques table has no `#` column and correctly falls outside the check.
- **kermit-pa**: same `## L<N>` lessons convention, but its queue file has **zero** `#`-headed tables at all (`| Date | Feature | Where it lives | Why harness-shaped | Migration plan |` — a different shape entirely). The queue-table check is a correct no-op there; the lessons check still applies.

**The pattern:** `scripts/check_duplicate_numbering.sh` runs two independent passes, each a graceful no-op (not an error) when its target file is absent or simply doesn't use the convention:

1. **Queue tables** — any markdown table whose header row's first cell is literally `#`. Duplicate first-column values are flagged only within the SAME table's data rows; the identical value reused across two DIFFERENT tables is legitimate and must NOT be flagged. Verified live against kermit-v3's real, current file: raw values `39` and `37` each appear twice in the file today, in two different independently-numbered tables — a naive whole-file grep would falsely flag both. Table scope resets at each new `| # | ... |` header row.
2. **Lessons headers** — `## L<N> — <title>`, checked for duplicate `<N>` globally across the whole file (lessons.md is one running numbered list, not independently-scoped tables).

Exact-string comparison of the trimmed first cell also correctly leaves intentional variants alone — kermit-v3's real `46` vs. `46R` (a documented regression follow-up, not a duplicate) never collide, with no special-casing needed.

**Adoption in a consumer project:** copy `scripts/check_duplicate_numbering.sh` into your own `scripts/`, call it from your own `gate_fast.sh` the same way dev-platform's own gate does (`bash scripts/check_duplicate_numbering.sh`, `record_pass`/`record_fail` on its exit code). Override `HANDOFF_QUEUE_PATH`/`LESSONS_PATH` before calling it if your project's paths differ from the shared `tasks/HARNESS_HANDOFF_QUEUE.md` / `tasks/lessons.md` convention. Same "no runtime distribution mechanism for `gate_fast.sh` internals" reasoning as the docs-only-diff skip (see above) — this ships as a script to copy in, not one consumers source at runtime.

**Known limitation, by design:** a table interrupted mid-body by a non-`|`-starting line (e.g. a blockquote spliced between data rows) ends that table's scope early; rows after the interruption go unscanned rather than falsely flagged. Not observed in any of the three consumer projects' real files as of this writing — conservative-by-construction, same posture as `scripts/lib/docs_only_diff.sh`.
```

**Acceptance Test:**

```bash
grep -n "Duplicate Numbering Check" docs/RULE_RATIONALE.md   # expect 1 match (the heading)
```

---

### Change 5: `CLAUDE.md` — extend the existing `RULE_RATIONALE.md` pointer-list

**Problem:** `CLAUDE.md` line 5 already tells Kermit-project sessions what topics live in `docs/RULE_RATIONALE.md` ("kwarg propagation, boundary sweeps, consumer-side schema deps, harness-vs-consumer triage, load-tier gate coverage") — this new topic needs to join that list so a future session knows to look. This is NOT a Gate Tiers mention (unlike the docs-only-diff skip) — that check is universal to every project's gate; this one is Kermit-consumer-specific, same class as `check_version_collision.py` (which gets no `CLAUDE.md` mention at all). A one-clause addition to the existing pointer-list is the right-sized edit.

**File:** `CLAUDE.md`, line 5.

**Implementation:**

Change:

```markdown
**Project-specific deep-dive rules and incident rationale:** `/home/rich/dev/docs/RULE_RATIONALE.md`. Read when working in Kermit/PA/ATLAS/Keystone (Kermit-specific rules: kwarg propagation, boundary sweeps, consumer-side schema deps, harness-vs-consumer triage, load-tier gate coverage), or when a rule's reasoning is unclear.
```

to:

```markdown
**Project-specific deep-dive rules and incident rationale:** `/home/rich/dev/docs/RULE_RATIONALE.md`. Read when working in Kermit/PA/ATLAS/Keystone (Kermit-specific rules: kwarg propagation, boundary sweeps, consumer-side schema deps, harness-vs-consumer triage, load-tier gate coverage, duplicate handoff-queue/lessons numbering), or when a rule's reasoning is unclear.
```

**Acceptance Test:**

```bash
grep -n "duplicate handoff-queue" CLAUDE.md   # expect 1 match
```

---

## What NOT to Do

- **Do not write into any of the three consumer projects' repos** (`projects/kermit-v3/`, `projects/keystone/`, `projects/kermit-pa/`). This spec ships the checker + doc pattern from dev-platform; adoption is each project's own session, coordinated via the Post-merge handoff issues below — never a direct commit from this session.
- **Do not hardcode kermit-v3's 5-table count, its specific `| # | Date | Ask | Status |` column layout, or any consumer's exact file structure into the checker.** The whole point (proven by the three projects' genuinely different shapes) is a generic "any `#`-headed table" / "any `## L<N>`" scan that adapts without per-project configuration.
- **Do not do a whole-file duplicate scan for the queue-table check.** That would false-positive on kermit-v3's real file today (`39` and `37` each legitimately appear in two different tables) — table-scoping is load-bearing, not a nice-to-have; the `cross-table-queue.md` fixture is the regression guard proving it.
- **Do not treat a letter-suffixed variant (`46R`) as a duplicate of its base number (`46`).** They're different strings by design (a documented regression follow-up), and exact-string comparison already gets this right — don't add normalization logic that would strip the suffix and collapse them.
- **Do not make the checker error/exit nonzero when a target file is simply absent or doesn't use the convention.** kermit-pa's queue file legitimately has zero `#`-headed tables; dev-platform's own `lessons.md` legitimately has zero `## L<N>` headers. Both are "nothing to check here," not violations — same posture as `check_spec_taxonomy.sh`'s no-`tasks/`-dir skip.
- **Do not add a `CLAUDE.md` "Gate Tiers" mention like the docs-only-diff skip got.** This check is Kermit-consumer-specific, not universal — it belongs in `docs/RULE_RATIONALE.md`'s Kermit-Specific Rules section, with only a pointer-list mention in `CLAUDE.md`, matching how `check_version_collision.py` is documented (not mentioned in `CLAUDE.md` prose at all).

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/check_duplicate_numbering.sh` | New | Table-scoped queue-row + global lessons-header duplicate checker |
| `tests/duplicate-numbering/run.sh` | New | 8-assertion unit suite |
| `tests/duplicate-numbering/fixtures/*.md` | New | 6 fixtures covering clean/duplicate/cross-table/no-convention shapes |
| `scripts/gate_fast.sh` | Modify | Wire in as a new lift check, mirroring `check_spec_taxonomy.sh`'s wiring |
| `docs/RULE_RATIONALE.md` | Modify | New "Duplicate Numbering Check" section under Kermit-Specific Rules |
| `CLAUDE.md` | Modify | One-clause addition to the existing `RULE_RATIONALE.md` pointer-list (line 5) |

## Implementation Order

1. Change 1 (`scripts/check_duplicate_numbering.sh`) — no dependents, do first.
2. Change 2 (`tests/duplicate-numbering/`) — depends on Change 1; prove the checker correct (especially the cross-table non-flagging case) before wiring it into the live gate.
3. Change 3 (`scripts/gate_fast.sh` wiring) — depends on Change 1, validated in practice by Change 2 already passing.
4. Change 4 (`docs/RULE_RATIONALE.md`) — depends on Changes 1-3 existing so the write-up is accurate.
5. Change 5 (`CLAUDE.md`) — depends on Change 4 existing (the doc it points to).

## Post-merge (coordination — NOT dev-platform code)

1. **Close the issue.** Comment on [teelr/dev-platform#75](https://github.com/teelr/dev-platform/issues/75) summarizing what shipped (link this spec + the merged PR + the new `docs/RULE_RATIONALE.md` section) and note the resolved design question (generic table-scoped + global-header checker, verified against all three consumers' real file shapes rather than assumed uniform). Close the issue.
2. **File the handoff issues** — title `Port duplicate-number check (Ask#/L#) from dev-platform`, body linking to `docs/RULE_RATIONALE.md`'s "Duplicate Numbering Check" section and to `scripts/check_duplicate_numbering.sh` as the file to copy in:
   - `gh issue create --repo teelr/kermit-v3 ...` (source of the report — gets the full checker, both passes apply)
   - `gh issue create --repo teelr/keystone ...` (both passes apply — 4 queue tables + L# lessons)
   - `gh issue create --repo teelr/kermit-pa ...` — note explicitly in the issue body that only the lessons-L# pass applies today (its queue file has no `#`-headed tables); still worth wiring in case its shape changes later.
3. **Standard Roadmap-Phase completion.** This spec is v1.17's only Phase — its merge completes the Roadmap Phase. Mark `v1.17` complete in `ROADMAP.md` + `planning.md` (today's date + status), close milestone #28 (`gh api -X PATCH repos/teelr/dev-platform/milestones/28 -f state=closed`), and verify with `./scripts/check-phase-milestones.sh`.

## Verification Checklist

- [ ] `scripts/check_duplicate_numbering.sh` exists, `bash -n` clean, exits 0 against dev-platform's own repo (neither target file present)
- [ ] `bash tests/duplicate-numbering/run.sh` → 8 PASS, 0 FAIL
- [ ] `cross-table-queue.md` fixture passes (exit 0) — the load-bearing proof that same-number-different-table is NOT flagged
- [ ] `dup-queue.md` and `dup-lessons.md` fixtures fail (exit 1) with the specific duplicate value named in the output, not just a bare nonzero exit
- [ ] `non-l-lessons.md` fixture (dev-platform's own lessons.md shape) passes cleanly — zero `## L<N>` headers is "nothing to check," not a violation
- [ ] `HANDOFF_QUEUE_PATH`/`LESSONS_PATH` overrides genuinely change what's read (proven by the override fixture using a file that would otherwise not be found)
- [ ] `scripts/gate_fast.sh` reports `PASS  duplicate numbering (handoff-queue / lessons)` on a full run
- [ ] `docs/RULE_RATIONALE.md` has the new section under Kermit-Specific Rules, including the "verified live, not assumed" per-project shape breakdown
- [ ] `CLAUDE.md` line 5's pointer-list includes "duplicate handoff-queue/lessons numbering"
- [ ] No file written under `projects/<name>/` in this diff
- [ ] Language architecture matrix followed (bash only, matches existing `gate_fast.sh`/test-suite convention)
- [ ] `/security-review` — N/A (no auth/credentials/external input/new endpoints; a local text-file duplicate scanner). Skip unless `/code` surfaces something unexpected.
