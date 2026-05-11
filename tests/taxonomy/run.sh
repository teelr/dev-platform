#!/usr/bin/env bash
# tests/taxonomy/run.sh — self-test for scripts/check_spec_taxonomy.sh.
# Each fixture gets its own throwaway tasks/ dir to isolate from the real
# repo's tasks/. Asserts the checker exits 0 (clean) or 1 (violation found)
# correctly per fixture.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

CHECKER="${REPO}/scripts/check_spec_taxonomy.sh"

run_fixture() {
    local fixture="$1"
    local expected_exit="$2"
    local description="$3"

    local tmp
    tmp="$(mktemp -d)"
    trap "rm -rf '${tmp}'" RETURN

    mkdir -p "${tmp}/tasks"
    # The checker scans tasks/*-spec.md; ensure the fixture name matches.
    local base
    base="$(basename "${fixture}" .md)"
    cp "${HERE}/${fixture}" "${tmp}/tasks/${base}-spec.md"

    (cd "${tmp}" && bash "${CHECKER}" >/dev/null 2>&1)
    local actual_exit=$?

    if [[ ${actual_exit} -eq ${expected_exit} ]]; then
        record_pass "taxonomy: ${description} (exit ${expected_exit})"
    else
        record_fail "taxonomy: ${description} (expected exit ${expected_exit}, got ${actual_exit})"
    fi
}

run_fixture "conformant-spec.md"   0 "conformant spec passes"
run_fixture "bad-spec-sprint.md"   1 "Sprint killed-term under Phase detected"
run_fixture "bad-spec-step.md"     1 "Step killed-term under Phase detected"
run_fixture "legitimate-step.md"   0 "Step under non-Phase parent legitimately allowed"
