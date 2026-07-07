#!/usr/bin/env bash
# tests/phase-milestones/run.sh — offline fixture suite for v1.10's
# scripts/check-phase-milestones.sh detector.
#
# Uses a mock `gh` (fixtures/mock-bin/gh) driven by MOCK_MILESTONES_FILE so the
# detector's flag rule and exit codes are exercised without any GitHub call.
# Every invocation passes --repo owner/repo so no real git origin is read.
#
# Auto-discovered by scripts/gate_fast.sh (tests/<suite>/run.sh, excluding
# fixtures/ — so the mock `gh` is never run as a test runner).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

SCRIPT="${REPO}/scripts/check-phase-milestones.sh"
MOCK_BIN="${HERE}/fixtures/mock-bin"

TMP="$(mktemp -d /tmp/phase-ms.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

# --- Canned milestone response files -----------------------------------------

# Flagged: open milestone with all attached issues/PRs closed.
flagged_json="${TMP}/flagged.json"
cat > "${flagged_json}" <<'JSON'
[
  {"number": 3, "title": "v0.3: Scaffolding", "state": "open",
   "open_issues": 0, "closed_issues": 3,
   "html_url": "https://github.com/owner/repo/milestone/3"}
]
JSON

# Clean: every milestone still has open work.
clean_json="${TMP}/clean.json"
cat > "${clean_json}" <<'JSON'
[
  {"number": 4, "title": "v0.4: Testing", "state": "open",
   "open_issues": 2, "closed_issues": 1,
   "html_url": "https://github.com/owner/repo/milestone/4"}
]
JSON

# Empty/not-started: open milestone with no attached issues at all. Must NOT be
# flagged — it is indistinguishable from a future phase not yet begun.
empty_json="${TMP}/empty.json"
cat > "${empty_json}" <<'JSON'
[
  {"number": 5, "title": "v0.5: Monitoring", "state": "open",
   "open_issues": 0, "closed_issues": 0,
   "html_url": "https://github.com/owner/repo/milestone/5"}
]
JSON

run_detector() {
    # run_detector <milestones-file> [extra-args...] → sets OUT and RC
    local ms_file="$1"; shift
    OUT="$(PATH="${MOCK_BIN}:${PATH}" MOCK_MILESTONES_FILE="${ms_file}" \
            bash "${SCRIPT}" --repo owner/repo "$@" 2>&1)"
    RC=$?
}

# Check 1: flagged milestone → default output names it, exit 1
run_detector "${flagged_json}"
if [[ ${RC} -eq 1 ]] && echo "${OUT}" | grep -q "OPEN-BUT-COMPLETE" \
        && echo "${OUT}" | grep -q "v0.3: Scaffolding"; then
    record_pass "phase-milestones: flags open-but-complete milestone (exit 1)"
else
    record_fail "phase-milestones: missed flagged milestone — rc=${RC}, out=${OUT:0:200}"
fi

# Check 2: same case with --json → non-empty array containing the number, exit 1
run_detector "${flagged_json}" --json
if [[ ${RC} -eq 1 ]] && echo "${OUT}" | jq -e 'length == 1 and .[0].number == 3' >/dev/null 2>&1; then
    record_pass "phase-milestones: --json emits flagged array (exit 1)"
else
    record_fail "phase-milestones: --json wrong — rc=${RC}, out=${OUT:0:200}"
fi

# Check 3: clean state → no findings, exit 0
run_detector "${clean_json}"
if [[ ${RC} -eq 0 ]] && echo "${OUT}" | grep -q "No open-but-complete milestones"; then
    record_pass "phase-milestones: clean state reports none (exit 0)"
else
    record_fail "phase-milestones: false positive on clean state — rc=${RC}, out=${OUT:0:200}"
fi

# Check 4: false-positive guard — empty/not-started milestone NOT flagged, exit 0
run_detector "${empty_json}"
if [[ ${RC} -eq 0 ]] && echo "${OUT}" | grep -q "No open-but-complete milestones"; then
    record_pass "phase-milestones: empty milestone (0 closed) not flagged (exit 0)"
else
    record_fail "phase-milestones: empty milestone wrongly flagged — rc=${RC}, out=${OUT:0:200}"
fi

# Check 5: --json on clean state → empty array, exit 0
run_detector "${clean_json}" --json
if [[ ${RC} -eq 0 ]] && echo "${OUT}" | jq -e 'length == 0' >/dev/null 2>&1; then
    record_pass "phase-milestones: --json clean emits empty array (exit 0)"
else
    record_fail "phase-milestones: --json clean wrong — rc=${RC}, out=${OUT:0:200}"
fi

# Check 6: --help → exit 0, usage printed, no gh call (MOCK_MILESTONES_FILE unset)
help_out="$(PATH="${MOCK_BIN}:${PATH}" bash "${SCRIPT}" --help 2>&1)"
help_rc=$?
if [[ ${help_rc} -eq 0 ]] && echo "${help_out}" | grep -q "check-phase-milestones.sh"; then
    record_pass "phase-milestones: --help prints usage, exit 0, no gh call"
else
    record_fail "phase-milestones: --help wrong — rc=${help_rc}, out=${help_out:0:200}"
fi

# Check 7: unknown arg → exit 2
bad_out="$(PATH="${MOCK_BIN}:${PATH}" bash "${SCRIPT}" --nonsense 2>&1)"
bad_rc=$?
if [[ ${bad_rc} -eq 2 ]]; then
    record_pass "phase-milestones: unknown arg exits 2"
else
    record_fail "phase-milestones: unknown arg wrong exit — rc=${bad_rc}"
fi

# Check 8: fetch failure (mock gh exits nonzero) → detector exits 2, not 0/1
fail_out="$(PATH="${MOCK_BIN}:${PATH}" MOCK_MILESTONES_FILE="${flagged_json}" MOCK_FAIL=1 \
        bash "${SCRIPT}" --repo owner/repo 2>&1)"
fail_rc=$?
if [[ ${fail_rc} -eq 2 ]] && echo "${fail_out}" | grep -q "failed to fetch milestones"; then
    record_pass "phase-milestones: gh fetch failure exits 2 (not 'clean')"
else
    record_fail "phase-milestones: fetch failure mishandled — rc=${fail_rc}, out=${fail_out:0:200}"
fi
