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

# Roadmap-level fixtures (v0.7 Phase 1, Change 2). Each fixture is placed at
# <tmp>/ROADMAP.md (not under tasks/) because that's where the new Roadmap
# scan pass looks. Parallel pattern to run_fixture but for ROADMAP.md.
#
# Optional 4th arg: a substring that MUST appear in checker output. Lets us
# assert that the violation was detected on the SPECIFIC killed-prefix line,
# not on a valid line via a regex regression. Without this, a future change
# that broke the regex to match `v0.1:` would still produce exit 1 and pass
# the test for the wrong reason.
run_roadmap_fixture() {
    local fixture="$1"
    local expected_exit="$2"
    local description="$3"
    local expected_match="${4:-}"

    local tmp
    tmp="$(mktemp -d)"
    trap "rm -rf '${tmp}'" RETURN

    cp "${HERE}/fixtures/${fixture}" "${tmp}/ROADMAP.md"
    # Stub tasks/ so the existing spec-structural scan doesn't fail with no-files
    mkdir -p "${tmp}/tasks"
    echo "# stub" > "${tmp}/tasks/stub-spec.md"

    local output
    output="$(cd "${tmp}" && bash "${CHECKER}" 2>&1)"
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

run_roadmap_fixture "conformant-roadmap.md"      0 "ROADMAP with valid v<N>.<N>: entries passes"
run_roadmap_fixture "bad-roadmap-sprint.md"      1 "ROADMAP with Sprint X: killed prefix detected"            "Sprint K:"
run_roadmap_fixture "bad-roadmap-rprefix.md"     1 "ROADMAP with legacy R<N>: killed prefix detected"         "R7:"
run_roadmap_fixture "bad-roadmap-multi.md"       1 "ROADMAP with both Sprint X: AND R<N>: violations detected" "Sprint K:"
