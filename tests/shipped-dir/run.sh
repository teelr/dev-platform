#!/usr/bin/env bash
# tests/shipped-dir/run.sh — regression suite for scripts/migrate-shipped.sh.
#
# Sourced contract: record_pass/record_fail from tests/helpers/assert.sh; never
# exit-s. Everything runs against fixture planning files via PLANNING_FILE/
# SHIPPED_DIR — never against the repo's real planning.md or tasks/shipped/.
#
# The migration's failure modes are silent once the section is deleted: a
# dropped bullet, a mis-dated file, a phase bullet filed as a chore. All
# covered here, plus the v1.23 pipe regression carried forward.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
MIGRATE="${REPO}/scripts/migrate-shipped.sh"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

TMP="$(mktemp -d /tmp/r3-shipped.XXX)"
trap 'rm -rf "${TMP}"' EXIT

# --- 1. syntax ----------------------------------------------------------------
if bash -n "${MIGRATE}" 2>/dev/null; then
    record_pass "shipped-dir: migrate-shipped.sh bash syntax clean"
else
    record_fail "shipped-dir: migrate-shipped.sh bash syntax error"
fi

# --- fixture ------------------------------------------------------------------
# Phase bullet 2 carries backticked pipes (the v1.23 regression). The two
# sections around Recently shipped must never be migrated. Bodies are unique so
# the verbatim-exactly-once check can distinguish duplicates.
GOOD="${TMP}/planning.md"
cat > "${GOOD}" <<'FIX'
# Fixture Planning Snapshot

## Current state

- **Active spec:** must never become a file.

## Recently shipped

Hashes intentionally omitted — git log is the authoritative record.

- v1.2 Second Phase, **closes v1.2** (2026-02-02, `tasks/b-spec.md`): uses `\|\| true` and `cmd \| head` in its prose.
- v1.1 First Phase, **closes v1.1** (2026-01-01, `tasks/a-spec.md`): plain narrative body.
- Chore alpha fix (2026-03-03, PR #9): a chore with no version number.
- Chore beta fix (2026-04-04): another chore, different date.

## In flight

- Must never become a file either.
FIX
sed -i 's/\\|/|/g' "${GOOD}"
OUT="${TMP}/out"

# --- 2. dry run writes nothing, reports both counts ----------------------------
out="$(PLANNING_FILE="${GOOD}" SHIPPED_DIR="${OUT}" bash "${MIGRATE}" 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && grep -q "2 phase + 2 chore" <<<"${out}" && [[ ! -d "${OUT}" ]]; then
    record_pass "shipped-dir: dry run reports phase/chore counts and writes nothing"
else
    record_fail "shipped-dir: dry run (rc=${rc}, out: ${out})"
fi

# --- 3. --apply: one file per bullet, correct filename shapes ------------------
out="$(PLANNING_FILE="${GOOD}" SHIPPED_DIR="${OUT}" bash "${MIGRATE}" --apply 2>&1)"; rc=$?
count="$(ls -1 "${OUT}"/*.md 2>/dev/null | wc -l)"
if [[ ${rc} -eq 0 && "${count}" -eq 4 ]]; then
    record_pass "shipped-dir: --apply writes one file per bullet"
else
    record_fail "shipped-dir: --apply (rc=${rc}, files=${count}, out: ${out})"
fi

if ls "${OUT}" | grep -q "^2026-02-02-v1.2-" && ls "${OUT}" | grep -q "^2026-01-01-v1.1-"; then
    record_pass "shipped-dir: phase files named <date>-v<X.Y>-<slug>.md"
else
    record_fail "shipped-dir: phase filenames ($(ls "${OUT}"))"
fi

if ls "${OUT}" | grep -q "^2026-03-03-chore-alpha" && ls "${OUT}" | grep -q "^2026-04-04-chore-beta"; then
    record_pass "shipped-dir: chore files named <date>-<slug>.md with the parenthetical date"
else
    record_fail "shipped-dir: chore filenames ($(ls "${OUT}"))"
fi

# --- 4. pipe regression --------------------------------------------------------
if grep -rq -- '`|| true`' "${OUT}" && grep -rq -- '`cmd | head`' "${OUT}"; then
    record_pass "shipped-dir: pipe-bearing bullet round-trips verbatim"
else
    record_fail "shipped-dir: pipes mangled"
fi

# --- 5. every body verbatim, exactly once --------------------------------------
missing=0; dupes=0
while IFS= read -r body; do
    [[ -z "${body}" ]] && continue
    hits="$(grep -rFl -- "${body}" "${OUT}" 2>/dev/null | wc -l)"
    [[ "${hits}" -eq 0 ]] && missing=$((missing + 1))
    [[ "${hits}" -gt 1 ]] && dupes=$((dupes + 1))
done < <(awk '/^## Recently shipped/,/^## In flight/' "${GOOD}" | sed -n 's/^- //p')
if [[ ${missing} -eq 0 && ${dupes} -eq 0 ]]; then
    record_pass "shipped-dir: every bullet body preserved verbatim, exactly once"
else
    record_fail "shipped-dir: preservation (missing=${missing}, duplicated=${dupes})"
fi

# --- 6. surrounding sections never migrated ------------------------------------
if ! grep -rq "must never become a file" "${OUT}"; then
    record_pass "shipped-dir: content outside Recently shipped is not migrated"
else
    record_fail "shipped-dir: out-of-section content leaked into ${OUT}"
fi

# --- 7. idempotence -------------------------------------------------------------
PLANNING_FILE="${GOOD}" SHIPPED_DIR="${OUT}" bash "${MIGRATE}" --apply >/dev/null 2>&1
count2="$(ls -1 "${OUT}"/*.md 2>/dev/null | wc -l)"
if [[ "${count2}" -eq 4 ]]; then
    record_pass "shipped-dir: re-running --apply is idempotent"
else
    record_fail "shipped-dir: idempotence (files=${count2}, expected 4)"
fi

# --- 8. a second non-bullet line aborts, writing nothing ------------------------
BAD="${TMP}/bad.md"
cat > "${BAD}" <<'FIX'
## Recently shipped

Hashes intentionally omitted — the known preamble.

Some stray second prose line that is not a bullet.

- v1.1 Fine Phase (2026-01-01): ok.
FIX
BADOUT="${TMP}/badout"
out="$(PLANNING_FILE="${BAD}" SHIPPED_DIR="${BADOUT}" bash "${MIGRATE}" --apply 2>&1)"; rc=$?
if [[ ${rc} -eq 1 ]] && grep -q "UNPARSEABLE" <<<"${out}" \
    && grep -q "nothing written" <<<"${out}" && [[ ! -d "${BADOUT}" ]]; then
    record_pass "shipped-dir: a second non-bullet line aborts and writes nothing"
else
    record_fail "shipped-dir: stray-prose abort (rc=${rc}, out: ${out})"
fi

# --- 9. a dateless bullet aborts ------------------------------------------------
NODATE="${TMP}/nodate.md"
cat > "${NODATE}" <<'FIX'
## Recently shipped

- v1.1 Phase with no date anywhere in the bullet at all.
FIX
NODATEOUT="${TMP}/nodateout"
out="$(PLANNING_FILE="${NODATE}" SHIPPED_DIR="${NODATEOUT}" bash "${MIGRATE}" --apply 2>&1)"; rc=$?
if [[ ${rc} -eq 1 ]] && grep -q "no YYYY-MM-DD date" <<<"${out}" && [[ ! -d "${NODATEOUT}" ]]; then
    record_pass "shipped-dir: a dateless bullet aborts and writes nothing"
else
    record_fail "shipped-dir: dateless abort (rc=${rc}, out: ${out})"
fi

# --- 10. missing section is an error, not a silent success ---------------------
NOSEC="${TMP}/nosec.md"
printf '# Just a title\n\n## Current state\n\n- nothing here\n' > "${NOSEC}"
out="$(PLANNING_FILE="${NOSEC}" SHIPPED_DIR="${TMP}/nowhere" bash "${MIGRATE}" --apply 2>&1)"; rc=$?
if [[ ${rc} -eq 1 ]] && grep -q "no '## Recently shipped'" <<<"${out}"; then
    record_pass "shipped-dir: a missing section exits 1, not 0"
else
    record_fail "shipped-dir: missing-section path (rc=${rc}, out: ${out})"
fi
