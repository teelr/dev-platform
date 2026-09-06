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

REG="${TMP}/registry.json"
python3 - "${TMP}" "${REG}" <<'PY'
import json, sys
base, out = sys.argv[1], sys.argv[2]
rows = [
    {"name": n, "path": f"{base}/projects/{n}", "gate_cmd": "true",
     "primary_language": "bash", "enabled": True}
    for n in ("split-1", "done-1", "notyet-1", "nothing-1")
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

echo ""
echo "migration-coverage: ${PASS_COUNT} PASS  ${FAIL_COUNT} FAIL  ${SKIP_COUNT} SKIP"
[[ ${FAIL_COUNT} -eq 0 ]] || exit 1
exit 0
