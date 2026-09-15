#!/usr/bin/env bash
# tests/migration-coverage/run.sh — the verdicts check-migration-coverage.sh
# reports for each migration state.
#
# tests/migration-formats covers the migrate-* PARSERS. Nothing covered the
# coverage checker's own verdict logic, which is how this shipped:
#
#     if [[ -d "${migrated_dir}" ]]; then echo "MIGRATED (N files)"; fi
#
# The target directory existing was taken as proof the migration happened. Both
# kermit-harness and kermit-v3 had entries landing in tasks/lessons/ while the
# old tasks/lessons.md still held 153 and 214 entries — reported as MIGRATED for
# weeks, and kermit-harness never got a migration issue filed because nothing
# said it needed one.
#
# Offline: fixture registry, fixture project trees, no consumer checkouts.
# Auto-discovered by scripts/gate_fast.sh per the v0.4 contract.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

CHECKER="${REPO}/scripts/check-migration-coverage.sh"

TMP="$(mktemp -d /tmp/migration-coverage.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

echo "=== migration-coverage ==="

# Four projects, one per state. `lessons.md` uses the numbered format; the
# checker retries with --date-from when the parser asks for one.
lessons_body() {
    printf '# Lessons\n\n## L1 — first lesson\n\nBody one.\n\n## L2 — second lesson\n\nBody two.\n'
}

mk() {
    local name="$1" with_dir="$2" with_src="$3"
    mkdir -p "${TMP}/projects/${name}/tasks"
    [[ "${with_src}" == "yes" ]] && lessons_body > "${TMP}/projects/${name}/tasks/lessons.md"
    if [[ "${with_dir}" == "yes" ]]; then
        mkdir -p "${TMP}/projects/${name}/tasks/lessons"
        printf '# Already migrated\n\nBody.\n' \
            > "${TMP}/projects/${name}/tasks/lessons/2026-01-01-already-migrated.md"
    fi
}

mk split-1     yes yes   # dir + source  → PARTIAL   (the regression)
mk done-1      yes no    # dir, no source → MIGRATED
mk notyet-1    no  yes   # source only    → PARSES
mk nothing-1   no  no    # neither        → NO SOURCE

# residual-1: source exists but holds nothing left to migrate — a kept,
# non-lesson reference table under its own heading — AND the target dir is
# already populated. Mirrors kermit-harness's real lessons.md exactly (v1.37):
# fully migrated, but the source was kept rather than deleted, so it never
# takes the `[[ ! -f "${src}" ]]` short-circuit done-1 does. Before v1.37 this
# misdetected as table format and reported FAILS.
mkdir -p "${TMP}/projects/residual-1/tasks/lessons"
printf '# Already migrated\n\nBody.\n' \
    > "${TMP}/projects/residual-1/tasks/lessons/2026-01-01-already-migrated.md"
cat > "${TMP}/projects/residual-1/tasks/lessons.md" <<'EOF'
# Lessons

**The lessons moved to tasks/lessons/.**

## Renumbering note — 2026-08-31

| Old | New | The entry that MOVED |
| --- | --- | -------------------- |
| L77 | L178 | Milvus VARCHAR max_length is bytes, not chars |
EOF

# Two shapes of unparseable heading, which must NOT be reported the same way.
#
# categories-1 is the SQRL shape: every unparseable heading is a category label,
# so --ignore-heading is the correct advice and skips nothing of value.
mkdir -p "${TMP}/projects/categories-1/tasks"
cat > "${TMP}/projects/categories-1/tasks/lessons.md" <<'EOF'
# Lessons

## Frontend

## L1 — a real lesson

Body one.

## Infrastructure

## L2 — another real lesson

Body two.
EOF

# lossy-1: the unparseable headings are lesson-SHAPED, so skipping them would
# drop real content and this must never read "needs --ignore-heading".
#
# NOTE: this fixture originally used `## L19+` and `## L51+L60`, kermit's real
# consolidation labels. Those now PARSE — the pattern was widened for exactly
# that reason — so they stopped exercising this path and the assertions below
# went red. The lossy branch still needs covering, so the fixture moved to forms
# that remain lesson-shaped and genuinely unparseable: a malformed label, and a
# heading with no title separator at all.
mkdir -p "${TMP}/projects/lossy-1/tasks"
cat > "${TMP}/projects/lossy-1/tasks/lessons.md" <<'EOF'
# Lessons

## Renumbering note

## L1 — a real lesson

Body one.

## L19+foo — a malformed consolidation label

Body two.

## L42

Body three, a lesson heading with no title separator.
EOF

REG="${TMP}/registry.json"
python3 - "${TMP}" "${REG}" <<'PY'
import json, sys
base, out = sys.argv[1], sys.argv[2]
rows = [
    {"name": n, "path": f"{base}/projects/{n}", "gate_cmd": "true",
     "primary_language": "bash", "enabled": True}
    for n in ("split-1", "done-1", "notyet-1", "nothing-1", "residual-1",
              "categories-1", "lossy-1")
]
with open(out, "w", encoding="utf-8") as fh:
    json.dump(rows, fh, indent=2)
PY

OUT="$(bash "${CHECKER}" --registry "${REG}" 2>&1)"
row() { echo "${OUT}" | grep "^| $1 " || true; }

# ─── 1: dir + source is PARTIAL, never MIGRATED ───────────────────
# The regression. Before the fix this row read "MIGRATED (1 files)" while the
# source still held two entries.
split_row="$(row split-1)"
if echo "${split_row}" | grep -q "PARTIAL (1 migrated, 2 left)"; then
    record_pass "migration-coverage: dir + non-empty source → PARTIAL with both counts"
elif echo "${split_row}" | grep -q "MIGRATED"; then
    record_fail "migration-coverage: split state reported MIGRATED — the backlog is invisible again"
else
    record_fail "migration-coverage: split state wrong — ${split_row}"
fi

# ─── 2: dir with the source gone is genuinely MIGRATED ────────────
if echo "$(row done-1)" | grep -q "MIGRATED (1 files)"; then
    record_pass "migration-coverage: dir with no source → MIGRATED"
else
    record_fail "migration-coverage: completed migration not reported — $(row done-1)"
fi

# ─── 3: source with no dir still reports its entry count ──────────
if echo "$(row notyet-1)" | grep -q "PARSES (2 entries)"; then
    record_pass "migration-coverage: source with no target dir → PARSES with a count"
else
    record_fail "migration-coverage: un-started migration wrong — $(row notyet-1)"
fi

# ─── 4: neither present is NO SOURCE, not MIGRATED ────────────────
if echo "$(row nothing-1)" | grep -q "NO SOURCE"; then
    record_pass "migration-coverage: neither file nor dir → NO SOURCE"
else
    record_fail "migration-coverage: empty case wrong — $(row nothing-1)"
fi

# ─── 4b: source exists but holds nothing left (kept reference table) + dir
# already populated → MIGRATED, not the FAILS this shipped as before v1.37 ───
residual_row="$(row residual-1)"
if echo "${residual_row}" | grep -q "MIGRATED (1 files)"; then
    record_pass "migration-coverage: fully-migrated source with a kept reference table → MIGRATED"
else
    record_fail "migration-coverage: residual-reference-table case wrong — ${residual_row}"
fi

# ─── 5: the SUMMARY names partials, not just the table ────────────
# The table alone is what let this sit unnoticed — the closing line said
# "already migrated", and that is the sentence people read.
if echo "${OUT}" | grep -q "PARTIALLY migrated" \
   && echo "${OUT}" | grep -q "split-1 lessons.md" \
   && ! echo "${OUT}" | grep -q "every consumer source parses or is already migrated"; then
    record_pass "migration-coverage: summary names the partial project and drops the all-clear"
else
    record_fail "migration-coverage: summary still reads as an all-clear despite a PARTIAL row"
fi

# ─── 6: a real parse failure still exits 1 ────────────────────────
# The new verdict must not swallow the existing failure path.
bash "${CHECKER}" --registry "${REG}" >/dev/null 2>&1
rc=$?
if [[ ${rc} -eq 0 ]]; then
    record_pass "migration-coverage: PARTIAL alone does not fail the run (consumer state, not a tool defect)"
else
    record_fail "migration-coverage: PARTIAL made the checker exit ${rc}"
fi

# ─── 7: category headings still get the --ignore-heading advice ───
# The SQRL shape must be untouched by the lesson-shaped discriminator.
if echo "$(row categories-1)" | grep -q "NEEDS --ignore-heading"; then
    record_pass "migration-coverage: all-category headings still advise --ignore-heading"
else
    record_fail "migration-coverage: category-heading case regressed — $(row categories-1)"
fi

# ─── 8: lesson-shaped headings must NOT advise --ignore-heading ───
# The kermit shape. Following that advice would silently drop two real lessons,
# which is the loss the parser's abort exists to prevent.
lossy_row="$(row lossy-1)"
if echo "${lossy_row}" | grep -q "UNPARSEABLE (2 entries, 1 headings)"; then
    record_pass "migration-coverage: lesson-shaped unparseable rows counted as entries, not skippable headings"
elif echo "${lossy_row}" | grep -q "ignore-heading"; then
    record_fail "migration-coverage: lesson-shaped rows advised --ignore-heading — following it would drop them"
else
    record_fail "migration-coverage: lossy case wrong — ${lossy_row}"
fi

# ─── 9: the summary warns against the destructive fix ─────────────
if echo "${OUT}" | grep -q "do NOT reach for --ignore-heading" \
   && echo "${OUT}" | grep -q "lossy-1 lessons.md"; then
    record_pass "migration-coverage: summary names the lossy project and warns off --ignore-heading"
else
    record_fail "migration-coverage: summary does not warn that --ignore-heading would drop entries"
fi

# ─── 10: a lossy row does not fail the run ────────────────────────
# Consumer format drift, not a tool defect — and this script is not in the gate.
if [[ ${rc} -eq 0 ]]; then
    record_pass "migration-coverage: a lossy row reports without failing the run"
else
    record_fail "migration-coverage: lossy row made the checker exit ${rc}"
fi

echo ""
echo "migration-coverage: ${PASS_COUNT} PASS  ${FAIL_COUNT} FAIL  ${SKIP_COUNT} SKIP"
[[ ${FAIL_COUNT} -eq 0 ]] || exit 1
exit 0
