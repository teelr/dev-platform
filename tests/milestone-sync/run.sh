#!/usr/bin/env bash
# tests/milestone-sync/run.sh — fixture suite for v0.7 Phase 4 sync-milestones.sh.
# Exercises parse / state-mapping / SKIP / UPDATE / LOCKED / dry-run / apply paths
# against canned fixtures via the mock `gh` binary at fixtures/mock-bin/gh.
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 auto-discovery contract.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

SCRIPT="${REPO}/scripts/sync-milestones.sh"
SAMPLE_ROADMAP="${HERE}/fixtures/sample-roadmap.md"
EMPTY_MILESTONES="${HERE}/fixtures/empty-milestones.json"
EXISTING_MILESTONES="${HERE}/fixtures/existing-milestones.json"
MOCK_BIN="${HERE}/fixtures/mock-bin"

# Per-test cleanup via trap.
ROUND_TRIP_TMP="$(mktemp -d /tmp/milestone-sync-rt.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${ROUND_TRIP_TMP}'" EXIT

# Check 1: bash -n syntax clean
if bash -n "${SCRIPT}"; then
    record_pass "milestone-sync: sync-milestones.sh bash syntax clean"
else
    record_fail "milestone-sync: sync-milestones.sh bash syntax error"
fi

# Check 2: --help renders without API calls
help_out="$(bash "${SCRIPT}" --help 2>&1)"
if echo "${help_out}" | grep -q "sync ROADMAP.md entries"; then
    record_pass "milestone-sync: --help renders"
else
    record_fail "milestone-sync: --help missing expected text"
fi

# Check 3: Required-tools gate — gh CLI missing → "gh CLI required" + exit 1.
# Build a sandboxed bin dir with core utilities but no `gh` (mirrors v0.6's
# tests/vscode/run.sh sandbox pattern for the `code` CLI absence test).
SANDBOX_BIN="$(mktemp -d /tmp/ms-sandbox.XXXXXX)"
for cmd in bash dirname pwd jq grep awk cat mkdir test rm sed; do
    if path="$(command -v "${cmd}" 2>/dev/null)"; then
        ln -s "${path}" "${SANDBOX_BIN}/${cmd}" 2>/dev/null || true
    fi
done
out="$(PATH="${SANDBOX_BIN}" bash "${SCRIPT}" 2>&1)"
rc=$?
if [[ ${rc} -ne 0 ]] && echo "${out}" | grep -q "gh CLI required"; then
    record_pass "milestone-sync: required-tools gate fires when gh absent (exit ${rc})"
else
    record_fail "milestone-sync: gh-absent gate didn't fire — rc=${rc}, out=${out:0:200}"
fi
rm -rf "${SANDBOX_BIN}"

# Check 4: Missing-ROADMAP gate — --file /nonexistent → "ROADMAP.md not found" + exit 1
out="$(bash "${SCRIPT}" --file /nonexistent 2>&1)"
rc=$?
if [[ ${rc} -ne 0 ]] && echo "${out}" | grep -q "ROADMAP.md not found"; then
    record_pass "milestone-sync: missing-ROADMAP gate fires (exit ${rc})"
else
    record_fail "milestone-sync: missing-ROADMAP gate didn't fire — rc=${rc}, out=${out:0:200}"
fi

# ----- Dry-run with empty mock milestones (everything should CREATE) -----
mock_milestones_5="${ROUND_TRIP_TMP}/milestones-5.json"
calls_5="${ROUND_TRIP_TMP}/calls-5.log"
cp "${EMPTY_MILESTONES}" "${mock_milestones_5}"

out_5="$(PATH="${MOCK_BIN}:${PATH}" \
    MOCK_MILESTONES_FILE="${mock_milestones_5}" \
    MOCK_API_CALLS_FILE="${calls_5}" \
    bash "${SCRIPT}" --file "${SAMPLE_ROADMAP}" 2>&1)"
rc_5=$?

# Check 5: parser detects all 4 entries from sample-roadmap (CREATE x 4 in dry-run)
create_count=$(echo "${out_5}" | grep -c "^  CREATE: ")
if [[ ${rc_5} -eq 0 && ${create_count} -eq 4 ]]; then
    record_pass "milestone-sync: parses 4 entries from sample-roadmap (v0.1 + v0.5 + v0.7 + v0.4a)"
else
    record_fail "milestone-sync: expected 4 CREATE lines, got ${create_count} (rc=${rc_5})"
fi

# Check 11: dry-run produces zero write-side calls
if [[ ! -s "${calls_5}" ]]; then
    record_pass "milestone-sync: dry-run makes zero write-side API calls"
else
    record_fail "milestone-sync: dry-run leaked write calls — $(cat "${calls_5}")"
fi

# ----- Apply with empty mock milestones (4 POST calls expected) -----
mock_milestones_12="${ROUND_TRIP_TMP}/milestones-12.json"
calls_12="${ROUND_TRIP_TMP}/calls-12.log"
cp "${EMPTY_MILESTONES}" "${mock_milestones_12}"

PATH="${MOCK_BIN}:${PATH}" \
    MOCK_MILESTONES_FILE="${mock_milestones_12}" \
    MOCK_API_CALLS_FILE="${calls_12}" \
    bash "${SCRIPT}" --apply --file "${SAMPLE_ROADMAP}" >/dev/null 2>&1

# Check 12: --apply against empty fires 4 POST calls
post_count=$(grep -c "^POST " "${calls_12}" 2>/dev/null || echo 0)
if [[ ${post_count} -eq 4 ]]; then
    record_pass "milestone-sync: --apply fires 4 POST calls into empty mock"
else
    record_fail "milestone-sync: --apply POST count wrong — got ${post_count}, want 4"
fi

# Check 6: state=closed for v0.1 (complete → closed)
if grep -E "^POST .*milestones .*title=v0\.1: Foundation" "${calls_12}" | grep -q "state=closed"; then
    record_pass "milestone-sync: v0.1 (complete) → POST state=closed"
else
    record_fail "milestone-sync: v0.1 state not closed — $(grep "v0.1" "${calls_12}")"
fi

# Check 7: state=open for v0.7 (planned → open)
if grep -E "^POST .*milestones .*title=v0\.7: Team Enablement" "${calls_12}" | grep -q "state=open"; then
    record_pass "milestone-sync: v0.7 (planned) → POST state=open"
else
    record_fail "milestone-sync: v0.7 state not open — $(grep "v0.7" "${calls_12}")"
fi

# ----- Dry-run against existing-milestones — SKIP / UPDATE / LOCKED -----
mock_milestones_x="${ROUND_TRIP_TMP}/milestones-x.json"
calls_x="${ROUND_TRIP_TMP}/calls-x.log"
cp "${EXISTING_MILESTONES}" "${mock_milestones_x}"

out_x="$(PATH="${MOCK_BIN}:${PATH}" \
    MOCK_MILESTONES_FILE="${mock_milestones_x}" \
    MOCK_API_CALLS_FILE="${calls_x}" \
    bash "${SCRIPT}" --file "${SAMPLE_ROADMAP}" 2>&1)"

# Check 8: SKIP for v0.5 (existing description matches ROADMAP parse)
if echo "${out_x}" | grep -qE "^  SKIP \(in sync\): v0\.5: Monitoring"; then
    record_pass "milestone-sync: v0.5 with matching description → SKIP"
else
    record_fail "milestone-sync: v0.5 not SKIPped — $(echo "${out_x}" | grep "v0.5")"
fi

# Check 9: UPDATE for v0.7 (existing description "OUTDATED")
if echo "${out_x}" | grep -qE "^  UPDATE \(state=open\): v0\.7: Team Enablement"; then
    record_pass "milestone-sync: v0.7 with description drift → UPDATE"
else
    record_fail "milestone-sync: v0.7 not UPDATEd — $(echo "${out_x}" | grep "v0.7")"
fi

# Check 10: LOCKED for v0.1 (existing state=closed; description drift irrelevant)
if echo "${out_x}" | grep -qE "^  LOCKED \(already closed\): v0\.1: Foundation"; then
    record_pass "milestone-sync: v0.1 (closed) → LOCKED regardless of description drift"
else
    record_fail "milestone-sync: v0.1 not LOCKED — $(echo "${out_x}" | grep "v0.1")"
fi
