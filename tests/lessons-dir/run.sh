#!/usr/bin/env bash
# tests/lessons-dir/run.sh — regression suite for scripts/migrate-lessons.sh.
#
# Sourced contract: uses record_pass/record_fail from tests/helpers/assert.sh;
# never exit-s (the orchestrator owns the exit code).
#
# Everything runs against fixture tables via LESSONS_FILE/LESSONS_DIR — never
# against the repo's real tasks/lessons/. The migration's two failure modes are
# both SILENT once the source table is deleted: a mangled pipe-bearing row, and
# a row dropped for not matching the pattern. Both are covered here.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
MIGRATE="${REPO}/scripts/migrate-lessons.sh"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

TMP="$(mktemp -d /tmp/r3-lessons.XXX)"
trap 'rm -rf "${TMP}"' EXIT

# --- 1. syntax ----------------------------------------------------------------
if bash -n "${MIGRATE}" 2>/dev/null; then
    record_pass "lessons-dir: migrate-lessons.sh bash syntax clean"
else
    record_fail "lessons-dir: migrate-lessons.sh bash syntax error"
fi

# --- fixture table ------------------------------------------------------------
# Row 2 carries literal pipes inside backticks — the shape that breaks a naive
# `awk -F'|'` split. Rows 3 and 4 share a date and their first 8 words (so they
# force a filename collision) but differ afterwards, so each body is still
# unique — otherwise the "verbatim, exactly once" check below could not tell a
# genuine duplicate from two legitimately identical lessons.
GOOD="${TMP}/good.md"
cat > "${GOOD}" <<'TABLE'
# Lessons Learned

## Active Lessons

| Date | Lesson | Project | Status |
| ---- | ------ | ------- | ------ |
| 2026-01-01 | Plain lesson with no special characters at all. | dev-platform | active |
| 2026-01-02 | Never use `\|\| true` in an assignment, and avoid `cmd \| head` in a pipeline. | dev-platform | active |
| 2026-01-03 | Duplicate opening words here for collision testing purposes only. First variant. | dev-platform | active |
| 2026-01-03 | Duplicate opening words here for collision testing purposes only. Second variant. | dev-platform | active |
TABLE
# The fixture is written with escaped pipes so the heredoc stays readable;
# unescape them so the file contains REAL pipes, which is the case under test.
sed -i 's/\\|/|/g' "${GOOD}"

OUT="${TMP}/out"

# --- 2. dry run writes nothing ------------------------------------------------
out="$(LESSONS_FILE="${GOOD}" LESSONS_DIR="${OUT}" bash "${MIGRATE}" 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && grep -q "DRY RUN — 4 row" <<<"${out}" && [[ ! -d "${OUT}" ]]; then
    record_pass "lessons-dir: dry run reports the row count and writes nothing"
else
    record_fail "lessons-dir: dry run (rc=${rc}, dir exists: $([[ -d ${OUT} ]] && echo yes || echo no), out: ${out})"
fi

# --- 3. --apply writes one file per row ---------------------------------------
out="$(LESSONS_FILE="${GOOD}" LESSONS_DIR="${OUT}" bash "${MIGRATE}" --apply 2>&1)"; rc=$?
count="$(ls -1 "${OUT}"/*.md 2>/dev/null | wc -l)"
if [[ ${rc} -eq 0 && "${count}" -eq 4 ]]; then
    record_pass "lessons-dir: --apply writes one file per row"
else
    record_fail "lessons-dir: --apply (rc=${rc}, files=${count}, out: ${out})"
fi

# --- 4. PIPE REGRESSION: embedded pipes survive verbatim ----------------------
# The whole reason this migration cannot split rows on "|".
if grep -rq -- '`|| true`' "${OUT}" && grep -rq -- '`cmd | head`' "${OUT}"; then
    record_pass "lessons-dir: pipe-bearing lesson keeps its | characters"
else
    record_fail "lessons-dir: pipes mangled — $(grep -rh 'true' "${OUT}" 2>&1 | head -1)"
fi

# --- 5. text preservation: every lesson body appears verbatim, exactly once ---
missing=0; dupes=0
while IFS= read -r body; do
    [[ -z "${body}" ]] && continue
    hits="$(grep -rFl -- "${body}" "${OUT}" 2>/dev/null | wc -l)"
    [[ "${hits}" -eq 0 ]] && missing=$((missing + 1))
    [[ "${hits}" -gt 1 ]] && dupes=$((dupes + 1))
done < <(sed -n 's/^| 2026-[0-9][0-9]-[0-9][0-9] | \(.*\) | dev-platform | active |$/\1/p' "${GOOD}")
if [[ ${missing} -eq 0 && ${dupes} -eq 0 ]]; then
    record_pass "lessons-dir: every lesson body is preserved verbatim, exactly once"
else
    record_fail "lessons-dir: text preservation (missing=${missing}, duplicated=${dupes})"
fi

# --- 6. filename collision produces two distinct files, neither overwritten ---
same_date="$(ls -1 "${OUT}" | grep -c '^2026-01-03-')"
if [[ "${same_date}" -eq 2 ]]; then
    record_pass "lessons-dir: same-date same-opening-words rows get distinct filenames"
else
    record_fail "lessons-dir: collision handling (got ${same_date} files for 2026-01-03)"
fi

# --- 7. idempotence: re-applying does not duplicate or corrupt ----------------
LESSONS_FILE="${GOOD}" LESSONS_DIR="${OUT}" bash "${MIGRATE}" --apply >/dev/null 2>&1
count2="$(ls -1 "${OUT}"/*.md 2>/dev/null | wc -l)"
if [[ "${count2}" -eq 4 ]]; then
    record_pass "lessons-dir: re-running --apply is idempotent"
else
    record_fail "lessons-dir: idempotence (files=${count2}, expected 4)"
fi

# --- 8. ABORT REGRESSION: a malformed row stops the run, writes nothing -------
# A silently skipped row is undetectable once the source table is deleted.
BAD="${TMP}/bad.md"
cat > "${BAD}" <<'TABLE'
| Date | Lesson | Project | Status |
| ---- | ------ | ------- | ------ |
| 2026-01-01 | Fine row. | dev-platform | active |
| 2026-01-02 | Missing the trailing columns
TABLE
BADOUT="${TMP}/badout"
out="$(LESSONS_FILE="${BAD}" LESSONS_DIR="${BADOUT}" bash "${MIGRATE}" --apply 2>&1)"; rc=$?
if [[ ${rc} -eq 1 ]] && grep -q "UNPARSEABLE" <<<"${out}" \
    && grep -q "nothing written" <<<"${out}" && [[ ! -d "${BADOUT}" ]]; then
    record_pass "lessons-dir: a malformed row aborts and writes nothing"
else
    record_fail "lessons-dir: malformed-row abort (rc=${rc}, dir: $([[ -d ${BADOUT} ]] && echo created || echo absent), out: ${out})"
fi

# --- 9. missing source file is an error, not a silent success ----------------
out="$(LESSONS_FILE="${TMP}/nope.md" LESSONS_DIR="${TMP}/nowhere" bash "${MIGRATE}" --apply 2>&1)"; rc=$?
if [[ ${rc} -eq 1 ]] && grep -q "nothing to migrate" <<<"${out}"; then
    record_pass "lessons-dir: a missing source table exits 1, not 0"
else
    record_fail "lessons-dir: missing source (rc=${rc}, out: ${out})"
fi
