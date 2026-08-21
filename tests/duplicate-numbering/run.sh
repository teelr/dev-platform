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
