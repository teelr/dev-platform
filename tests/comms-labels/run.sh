#!/usr/bin/env bash
# tests/comms-labels/run.sh — fixture suite for scripts/setup-consumer-labels.sh
# (v1.5 cross-repo comms migration).
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 auto-discovery contract.
# Runs fully offline against a mock `gh` binary at fixtures/mock-bin/gh and a
# mock registry written under mktemp — never touches a real GitHub repo.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

SCRIPT="${REPO}/scripts/setup-consumer-labels.sh"
MOCK_BIN="${HERE}/fixtures/mock-bin"

TMP="$(mktemp -d /tmp/comms-labels.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

# Mock registry: two consumers on the same upstream repo (to prove dedup) plus
# one on a different repo (to prove --repo filtering).
MOCK_REGISTRY="${TMP}/comms-consumers.json"
cat > "${MOCK_REGISTRY}" <<'JSON'
[
  {"consumer": "pa", "path": "projects/pa", "dep_slug": "harness", "upstream_repo": "teelr/kermit-harness", "label": "consumer:pa", "active": true},
  {"consumer": "keystone", "path": "projects/keystone", "dep_slug": "harness", "upstream_repo": "teelr/kermit-harness", "label": "consumer:keystone", "active": true},
  {"consumer": "other", "path": "projects/other", "dep_slug": "widget", "upstream_repo": "teelr/other-dep", "label": "consumer:other", "active": true}
]
JSON

# Check 1: bash syntax clean
if bash -n "${SCRIPT}"; then
    record_pass "comms-labels: setup-consumer-labels.sh syntax clean"
else
    record_fail "comms-labels: setup-consumer-labels.sh syntax error"
fi

# Check 2: --help renders
out="$("${SCRIPT}" --help 2>&1)"
if echo "${out}" | grep -q "setup-consumer-labels"; then
    record_pass "comms-labels: --help renders usage"
else
    record_fail "comms-labels: --help missing"
fi

# Check 3: dry-run (default) prints all 3 labels and calls gh 0 times
gh_log="${TMP}/gh-dryrun.log"
: > "${gh_log}"
out="$(PATH="${MOCK_BIN}:${PATH}" MOCK_GH_LOG="${gh_log}" \
        "${SCRIPT}" --registry "${MOCK_REGISTRY}" 2>&1)"
if echo "${out}" | grep -q "consumer:pa" \
        && echo "${out}" | grep -q "consumer:keystone" \
        && echo "${out}" | grep -q "consumer:other" \
        && [[ ! -s "${gh_log}" ]]; then
    record_pass "comms-labels: dry-run lists 3 labels, runs gh 0 times"
else
    record_fail "comms-labels: dry-run wrong — gh_log lines=$(wc -l < "${gh_log}"), out=${out:0:200}"
fi

# Check 4: --apply calls `gh label create` once per unique label, each --force
gh_log="${TMP}/gh-apply.log"
: > "${gh_log}"
PATH="${MOCK_BIN}:${PATH}" MOCK_GH_LOG="${gh_log}" \
        "${SCRIPT}" --apply --registry "${MOCK_REGISTRY}" >/dev/null 2>&1
create_lines="$(grep -c "label create" "${gh_log}" 2>/dev/null)"
force_lines="$(grep -c -- "--force" "${gh_log}" 2>/dev/null)"
if [[ "${create_lines}" -eq 3 && "${force_lines}" -eq 3 ]]; then
    record_pass "comms-labels: --apply runs 3 'gh label create --force' calls"
else
    record_fail "comms-labels: --apply wrong — create=${create_lines}, force=${force_lines}"
fi

# Check 5: --repo filters to a single upstream repo
gh_log="${TMP}/gh-filter.log"
: > "${gh_log}"
PATH="${MOCK_BIN}:${PATH}" MOCK_GH_LOG="${gh_log}" \
        "${SCRIPT}" --apply --repo teelr/kermit-harness --registry "${MOCK_REGISTRY}" >/dev/null 2>&1
total="$(grep -c "label create" "${gh_log}" 2>/dev/null)"
harness="$(grep -c "teelr/kermit-harness" "${gh_log}" 2>/dev/null)"
other="$(grep -c "teelr/other-dep" "${gh_log}" 2>/dev/null)"
if [[ "${total}" -eq 2 && "${harness}" -eq 2 && "${other}" -eq 0 ]]; then
    record_pass "comms-labels: --repo filters to the named upstream repo (2 calls, none to other-dep)"
else
    record_fail "comms-labels: --repo filter wrong — total=${total}, harness=${harness}, other=${other}"
fi

# Check 6: gh label create failure is accounted (exit 1 under --apply)
gh_log="${TMP}/gh-fail.log"
: > "${gh_log}"
PATH="${MOCK_BIN}:${PATH}" MOCK_GH_LOG="${gh_log}" MOCK_GH_FAIL=1 \
        "${SCRIPT}" --apply --registry "${MOCK_REGISTRY}" >/dev/null 2>&1
rc=$?
if [[ ${rc} -eq 1 ]]; then
    record_pass "comms-labels: --apply exits 1 when a gh label create fails"
else
    record_fail "comms-labels: --apply should exit 1 on gh failure, got ${rc}"
fi

exit $(( FAIL_COUNT > 0 ? 1 : 0 ))
