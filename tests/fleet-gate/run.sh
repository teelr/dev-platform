#!/usr/bin/env bash
# tests/fleet-gate/run.sh — fixture suite for v0.8 Phase 1 fleet-gate.sh.
# Exercises parse / parallel-spawn / timeout / aggregation / telemetry paths
# against a mock project tree under fixtures/projects/.
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 contract.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

SCRIPT="${REPO}/scripts/fleet-gate.sh"
REGISTRY_GOOD="${HERE}/fixtures/registry-good.json"
REGISTRY_MIXED="${HERE}/fixtures/registry-mixed.json"

# Per-test cleanup
TMP="$(mktemp -d /tmp/fleet-gate-test.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

# Check 1: bash -n syntax clean
if bash -n "${SCRIPT}"; then
    record_pass "fleet-gate: fleet-gate.sh bash syntax clean"
else
    record_fail "fleet-gate: fleet-gate.sh bash syntax error"
fi

# Check 2: --help renders without launching gates
help_out="$(bash "${SCRIPT}" --help 2>&1)"
if echo "${help_out}" | grep -q "read-only fleet sweep"; then
    record_pass "fleet-gate: --help renders"
else
    record_fail "fleet-gate: --help missing expected text"
fi

# Check 3: Required-tools gate — jq missing → "jq required" + exit 2.
SANDBOX_BIN="$(mktemp -d /tmp/fg-sandbox.XXXXXX)"
for cmd in bash dirname pwd grep cat mkdir test rm sed date python3 timeout; do
    if path="$(command -v "${cmd}" 2>/dev/null)"; then
        ln -s "${path}" "${SANDBOX_BIN}/${cmd}" 2>/dev/null || true
    fi
done
out="$(PATH="${SANDBOX_BIN}" bash "${SCRIPT}" 2>&1)"
rc=$?
if [[ ${rc} -eq 2 ]] && echo "${out}" | grep -q "jq required"; then
    record_pass "fleet-gate: required-tools gate fires when jq absent (exit ${rc})"
else
    record_fail "fleet-gate: jq-absent gate didn't fire — rc=${rc}, out=${out:0:200}"
fi
rm -rf "${SANDBOX_BIN}"

# Check 4: Single-project against registry-good → exit 0, PASS in output.
out="$(bash "${SCRIPT}" --project pass-1 --registry "${REGISTRY_GOOD}" --timeout 10 2>&1)"
rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "| pass-1.*| PASS"; then
    record_pass "fleet-gate: single-project sweep against registry-good → PASS exit 0"
else
    record_fail "fleet-gate: single-project sweep failed — rc=${rc}"
fi

# Check 5: Mixed sweep with --timeout 2 → exit 1 (some FAIL/TIMEOUT).
out="$(bash "${SCRIPT}" --registry "${REGISTRY_MIXED}" --timeout 2 --parallel 4 2>&1)"
rc=$?
if [[ ${rc} -eq 1 ]]; then
    record_pass "fleet-gate: mixed sweep exits non-zero on FAIL/TIMEOUT (rc=${rc})"
else
    record_fail "fleet-gate: mixed sweep exit wrong — rc=${rc}"
fi

# Save mixed-sweep output for the next several checks
mixed_out="${out}"

# Check 6: Mixed sweep summary line — 1 PASS + 1 FAIL + 1 TIMEOUT + 0 SKIP
# (disabled-1 is filtered out, not SKIP — SKIP is for MISSING paths)
if echo "${mixed_out}" | grep -qE "^1 PASS  1 FAIL  1 TIMEOUT  0 SKIP"; then
    record_pass "fleet-gate: mixed sweep summary counts (1P/1F/1T/0S)"
else
    record_fail "fleet-gate: mixed summary wrong — $(echo "${mixed_out}" | grep "PASS.*FAIL")"
fi

# Check 7: disabled-1 NOT in output (enabled:false → not included by default)
if ! echo "${mixed_out}" | grep -q "disabled-1"; then
    record_pass "fleet-gate: disabled-1 (enabled:false) skipped from default sweep"
else
    record_fail "fleet-gate: disabled-1 leaked into sweep"
fi

# Check 8: fail-1 log path referenced in the "Failing logs:" section
if echo "${mixed_out}" | grep -qE "Failing logs:|fail-1:.*\.log"; then
    record_pass "fleet-gate: failing-project log paths referenced in output"
else
    record_fail "fleet-gate: failing log paths missing"
fi

# Check 9: Telemetry event emitted on a sweep. Redirect HOME so the script
# writes to a tmpfile we can inspect.
TELEMETRY_HOME="${TMP}/home"
mkdir -p "${TELEMETRY_HOME}/.claude"
HOME="${TELEMETRY_HOME}" bash "${SCRIPT}" --project pass-1 --registry "${REGISTRY_GOOD}" --timeout 10 >/dev/null 2>&1
if [[ -f "${TELEMETRY_HOME}/.claude/dev-platform-telemetry.log" ]] && \
   grep -q '"event": "fleet_gate_run"' "${TELEMETRY_HOME}/.claude/dev-platform-telemetry.log"; then
    record_pass "fleet-gate: fleet_gate_run telemetry event emitted"
else
    record_fail "fleet-gate: telemetry event not emitted — $(cat "${TELEMETRY_HOME}/.claude/dev-platform-telemetry.log" 2>/dev/null | head -1)"
fi

# Check 10: --all flag includes disabled entries
out="$(bash "${SCRIPT}" --registry "${REGISTRY_MIXED}" --all --timeout 2 --parallel 4 2>&1)"
if echo "${out}" | grep -q "disabled-1"; then
    record_pass "fleet-gate: --all flag includes disabled:false entries"
else
    record_fail "fleet-gate: --all flag didn't include disabled-1"
fi
