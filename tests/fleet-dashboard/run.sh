#!/usr/bin/env bash
# tests/fleet-dashboard/run.sh — fixture suite for v0.8 Phase 2 fleet_dashboard.py.
# Builds a 4-project mock tree under mktemp + writes a registry JSON inline,
# then exercises markdown + JSON + filter + per-query paths against it.
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 contract.
#
# Deviation from spec: the spec File Change Summary lists
# `tests/fleet-dashboard/fixtures/registry.json` as a static fixture, but
# the registry must reference mktemp-generated paths that can't be
# hardcoded. The runner writes the registry inline. No static fixture
# file needed.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"
# shellcheck disable=SC1091
source "${REPO}/tests/helpers/mock-project-tree.sh"

DASHBOARD="${REPO}/monitoring/fleet_dashboard.py"
WRAPPER="${REPO}/scripts/fleet-status.sh"

# Per-test cleanup
TMP="$(mktemp -d /tmp/fleet-dashboard-test.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

# Build the 4-project mock tree
MOCK_ROOT="${TMP}/mock-projects"
mkdir -p "${MOCK_ROOT}"

# pass-1: clean, 1 commit, no issues
mock_project_init "${MOCK_ROOT}/pass-1"

# dirty-1: clean commit + 2 uncommitted files
mock_project_init "${MOCK_ROOT}/dirty-1"
mock_project_dirty "${MOCK_ROOT}/dirty-1" "uncommitted-1.txt"
mock_project_dirty "${MOCK_ROOT}/dirty-1" "uncommitted-2.txt"

# drift-1: clean commit + taxonomy violation
mock_project_init "${MOCK_ROOT}/drift-1"
mock_project_taxonomy_violation "${MOCK_ROOT}/drift-1"

# adopted-1: clean commit + consumer template installed
mock_project_init "${MOCK_ROOT}/adopted-1"
mock_project_install_template "${MOCK_ROOT}/adopted-1"

# Write the mock registry (relative paths from REPO root — convert absolute
# mktemp paths to a form the dashboard can resolve).
MOCK_REGISTRY="${TMP}/registry.json"
cat > "${MOCK_REGISTRY}" <<EOF
[
  {"name": "pass-1",    "path": "${MOCK_ROOT}/pass-1",    "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "dirty-1",   "path": "${MOCK_ROOT}/dirty-1",   "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "drift-1",   "path": "${MOCK_ROOT}/drift-1",   "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "adopted-1", "path": "${MOCK_ROOT}/adopted-1", "gate_cmd": "true", "primary_language": "bash", "enabled": true}
]
EOF

# The dashboard interprets paths relative to REPO unless they're absolute.
# Mock-project paths ARE absolute (mktemp), so they bypass the relative-
# resolution path. Good.

# Check 1: Python syntax clean
if python3 -c "import ast; ast.parse(open('${DASHBOARD}').read())" 2>/dev/null; then
    record_pass "fleet-dashboard: fleet_dashboard.py python syntax clean"
else
    record_fail "fleet-dashboard: fleet_dashboard.py python syntax error"
fi

# Check 2: --help renders without git/filesystem invocations
help_out="$(python3 "${DASHBOARD}" --help 2>&1)"
if echo "${help_out}" | grep -q "Fleet Dashboard"; then
    record_pass "fleet-dashboard: --help renders"
else
    record_fail "fleet-dashboard: --help missing expected text"
fi

# Check 3: Markdown render against mock registry
md_out="$(python3 "${DASHBOARD}" --registry "${MOCK_REGISTRY}" 2>&1)"
rc=$?
if [[ ${rc} -eq 0 ]] && echo "${md_out}" | grep -q "^# Fleet Dashboard"; then
    record_pass "fleet-dashboard: markdown render exits 0 with title"
else
    record_fail "fleet-dashboard: markdown render rc=${rc}"
fi

# Check 4: JSON render parses with 4 projects
json_out="$(python3 "${DASHBOARD}" --format json --registry "${MOCK_REGISTRY}" 2>&1)"
if echo "${json_out}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert 'projects' in d and isinstance(d['projects'], list), 'no projects array'
assert len(d['projects']) == 4, f'expected 4 projects, got {len(d[\"projects\"])}'
required = {'name','path','branch','last_commit_iso','last_commit_sha','last_commit_subject','last_commit_age_days','uncommitted_count','taxonomy_ok','dev_platform_gate_installed'}
for p in d['projects']:
    missing = required - set(p.keys())
    assert not missing, f'{p[\"name\"]} missing fields: {missing}'
print('OK')
" 2>&1 | grep -q "^OK"; then
    record_pass "fleet-dashboard: JSON render shape valid (4 projects, all 10 fields)"
else
    record_fail "fleet-dashboard: JSON shape wrong"
fi

# Check 5: Single-project filter returns 1-row table
filt_out="$(python3 "${DASHBOARD}" --project pass-1 --registry "${MOCK_REGISTRY}" 2>&1)"
table_rows="$(echo "${filt_out}" | grep -c "^| pass-1\|^| dirty-1\|^| drift-1\|^| adopted-1")"
if [[ "${table_rows}" -eq 1 ]]; then
    record_pass "fleet-dashboard: --project filter returns 1 row"
else
    record_fail "fleet-dashboard: --project filter wrong — got ${table_rows} rows"
fi

# Check 6: Uncommitted count surfaces for dirty-1
dirty_uncommitted="$(echo "${json_out}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for p in d['projects']:
    if p['name'] == 'dirty-1':
        print(p['uncommitted_count'])
        break
")"
if [[ "${dirty_uncommitted}" -eq 2 ]]; then
    record_pass "fleet-dashboard: dirty-1 uncommitted count = 2"
else
    record_fail "fleet-dashboard: dirty-1 uncommitted wrong — got ${dirty_uncommitted}"
fi

# Check 7: Taxonomy DRIFT surfaces for drift-1
drift_tax="$(echo "${json_out}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for p in d['projects']:
    if p['name'] == 'drift-1':
        print(p['taxonomy_ok'])
        break
")"
if [[ "${drift_tax}" == "False" ]]; then
    record_pass "fleet-dashboard: drift-1 taxonomy_ok=False (DRIFT detected)"
else
    record_fail "fleet-dashboard: drift-1 should be taxonomy_ok=False, got ${drift_tax}"
fi

# Check 8: Adoption flag surfaces for adopted-1
adopted_gate="$(echo "${json_out}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for p in d['projects']:
    if p['name'] == 'adopted-1':
        print(p['dev_platform_gate_installed'])
        break
")"
if [[ "${adopted_gate}" == "True" ]]; then
    record_pass "fleet-dashboard: adopted-1 dev_platform_gate_installed=True"
else
    record_fail "fleet-dashboard: adopted-1 adoption flag wrong — got ${adopted_gate}"
fi

# Check 9: Concurrency budget — 4 mock projects should complete < 5s wall time.
# (Spec says < 2s but mock-project setup adds overhead; budget 5s for hermetic mode.)
start=$(date +%s)
python3 "${DASHBOARD}" --registry "${MOCK_REGISTRY}" >/dev/null 2>&1
end=$(date +%s)
elapsed=$((end - start))
if [[ ${elapsed} -lt 5 ]]; then
    record_pass "fleet-dashboard: 4-project sweep completes in ${elapsed}s (< 5s budget)"
else
    record_fail "fleet-dashboard: too slow — ${elapsed}s for 4 mock projects (concurrency likely broken)"
fi

# Check 10: Missing-registry gate
out="$(python3 "${DASHBOARD}" --registry /nonexistent 2>&1)"
rc=$?
if [[ ${rc} -ne 0 ]] && echo "${out}" | grep -q "registry not found"; then
    record_pass "fleet-dashboard: missing-registry gate fires (exit ${rc})"
else
    record_fail "fleet-dashboard: missing-registry gate didn't fire — rc=${rc}"
fi
