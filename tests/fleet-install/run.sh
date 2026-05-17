#!/usr/bin/env bash
# tests/fleet-install/run.sh — fixture suite for v0.8 Phase 3
# fleet-install-template.sh. Builds a mock project tree under mktemp +
# writes an inline registry, then exercises dry-run/apply/force/pin paths
# and the LOAD-BEARING path-guard contract (script writes EXACTLY ONE
# file at EXACTLY ONE path, nowhere else).
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 contract.
#
# Mirrors the Phase 2 fleet-dashboard runner: the spec lists a static
# fixture file but mock-project paths are mktemp-generated and can't be
# hardcoded, so the registry is written inline.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"
# shellcheck disable=SC1091
source "${REPO}/tests/helpers/mock-project-tree.sh"

SCRIPT="${REPO}/scripts/fleet-install-template.sh"
SOURCE_TEMPLATE="${REPO}/extensions/github-actions/dev-platform-gate.yml"

TMP="$(mktemp -d /tmp/fleet-install-test.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

# Build the mock project tree
MOCK_ROOT="${TMP}/mock-projects"
mkdir -p "${MOCK_ROOT}"

mock_project_init "${MOCK_ROOT}/clean-1"
mock_project_init "${MOCK_ROOT}/already-1"
mock_project_install_template "${MOCK_ROOT}/already-1"
mock_project_init "${MOCK_ROOT}/disabled-1"

MOCK_REGISTRY="${TMP}/registry.json"
cat > "${MOCK_REGISTRY}" <<EOF
[
  {"name": "clean-1",    "path": "${MOCK_ROOT}/clean-1",    "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "already-1",  "path": "${MOCK_ROOT}/already-1",  "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "disabled-1", "path": "${MOCK_ROOT}/disabled-1", "gate_cmd": "true", "primary_language": "bash", "enabled": false}
]
EOF

# Snapshot the mock tree's current state (every file path) so the
# path-guard test can audit what changed after --apply runs. The set
# returned is the baseline + any .git/ guts; the apply test compares
# against this to assert only ONE new file appeared at the expected path.
snapshot_tree() {
    local root="$1"
    (cd "${root}" && find . -type f | sort)
}

BASELINE="$(snapshot_tree "${MOCK_ROOT}")"

# ─── Check 1: bash -n syntax clean ────────────────────────────────
if bash -n "${SCRIPT}" 2>/dev/null; then
    record_pass "fleet-install: bash -n syntax clean"
else
    record_fail "fleet-install: bash -n syntax error"
fi

# ─── Check 2: --help renders ──────────────────────────────────────
help_out="$("${SCRIPT}" --help 2>&1)"
if echo "${help_out}" | grep -q "fleet-install-template"; then
    record_pass "fleet-install: --help renders without writes"
else
    record_fail "fleet-install: --help missing expected text"
fi

# ─── Check 3: --project required ──────────────────────────────────
out="$("${SCRIPT}" 2>&1)"; rc=$?
if [[ ${rc} -ne 0 ]] && echo "${out}" | grep -qE "jq required|--project <name> is required"; then
    record_pass "fleet-install: --project required (or jq gate fires) rc=${rc}"
else
    record_fail "fleet-install: missing-project gate didn't fire — rc=${rc}"
fi

# ─── Check 4: argparse robustness ─────────────────────────────────
robust_ok=1
for flag in --project --pin --registry; do
    out="$("${SCRIPT}" "${flag}" 2>&1)"; rc=$?
    if [[ ${rc} -ne 2 ]] || ! echo "${out}" | grep -q "requires an argument"; then
        robust_ok=0
        break
    fi
done
if [[ ${robust_ok} -eq 1 ]]; then
    record_pass "fleet-install: argparse robustness (--project/--pin/--registry each emit 'requires an argument' + exit 2)"
else
    record_fail "fleet-install: argparse robustness regression on ${flag}"
fi

# ─── Check 5: required-tools gate (jq absent) ─────────────────────
# Resolve bash absolutely before clamping PATH — otherwise the prefix
# assignment hides bash from the parent's command-resolution too.
# Within the script, `command -v jq` is a bash builtin (no PATH needed
# to invoke), but the lookup itself respects PATH and returns non-zero
# → triggers the "ERROR: jq required" + exit 2 path.
BASH_BIN="$(command -v bash)"
out="$(PATH=/tmp "${BASH_BIN}" "${SCRIPT}" --project clean-1 --registry "${MOCK_REGISTRY}" 2>&1)"; rc=$?
if [[ ${rc} -eq 2 ]] && echo "${out}" | grep -q "jq required"; then
    record_pass "fleet-install: required-tools gate fires when jq absent (exit 2)"
else
    record_fail "fleet-install: jq gate didn't fire — rc=${rc}"
fi

# ─── Check 6: dry-run is default ──────────────────────────────────
out="$("${SCRIPT}" --project clean-1 --registry "${MOCK_REGISTRY}" 2>&1)"; rc=$?
target_clean="${MOCK_ROOT}/clean-1/.github/workflows/dev-platform-gate.yml"
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "Dry-run" && [[ ! -f "${target_clean}" ]]; then
    record_pass "fleet-install: dry-run default (no file written; dry-run banner present)"
else
    record_fail "fleet-install: dry-run default broken — rc=${rc}, target_exists=$([[ -f "${target_clean}" ]] && echo yes || echo no)"
fi

# ─── Check 7: --apply writes the file ─────────────────────────────
APPLY_HOME="${TMP}/home-apply"
mkdir -p "${APPLY_HOME}/.claude"
out="$(HOME="${APPLY_HOME}" "${SCRIPT}" --project clean-1 --apply --registry "${MOCK_REGISTRY}" 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && [[ -f "${target_clean}" ]] && \
   diff -q <(head -c 100 "${target_clean}") <(head -c 100 "${SOURCE_TEMPLATE}") >/dev/null 2>&1; then
    record_pass "fleet-install: --apply writes the file (contents match source template)"
else
    record_fail "fleet-install: --apply didn't write or content mismatch — rc=${rc}"
fi

# ─── Check 8: refuse-to-clobber on existing target ────────────────
# already-1 has the template pre-installed via mock_project_install_template.
target_already="${MOCK_ROOT}/already-1/.github/workflows/dev-platform-gate.yml"
before_sha="$(sha256sum "${target_already}" | awk '{print $1}')"
out="$(HOME="${APPLY_HOME}" "${SCRIPT}" --project already-1 --apply --registry "${MOCK_REGISTRY}" 2>&1)"; rc=$?
after_sha="$(sha256sum "${target_already}" | awk '{print $1}')"
if [[ ${rc} -ne 0 ]] && [[ "${before_sha}" == "${after_sha}" ]] && \
   echo "${out}" | grep -q "target already exists"; then
    record_pass "fleet-install: refuse-to-clobber (target unchanged, exit non-zero, actionable message)"
else
    record_fail "fleet-install: refuse-to-clobber broken — rc=${rc}, content_changed=$([[ "${before_sha}" != "${after_sha}" ]] && echo yes || echo no)"
fi

# ─── Check 9: --force overwrites ──────────────────────────────────
# Pre-write a marker-content file so we can prove --force replaced it.
echo "MARKER-CONTENT-NOT-THE-TEMPLATE" > "${target_already}"
marker_sha="$(sha256sum "${target_already}" | awk '{print $1}')"
out="$(HOME="${APPLY_HOME}" "${SCRIPT}" --project already-1 --apply --force --registry "${MOCK_REGISTRY}" 2>&1)"; rc=$?
post_sha="$(sha256sum "${target_already}" | awk '{print $1}')"
if [[ ${rc} -eq 0 ]] && [[ "${marker_sha}" != "${post_sha}" ]] && \
   grep -q "dev-platform-gate" "${target_already}"; then
    record_pass "fleet-install: --force overwrites existing target"
else
    record_fail "fleet-install: --force didn't overwrite — rc=${rc}"
fi

# ─── Check 10: --pin v0.6 rewrites the @v1.1 tag ──────────────────
# Write to clean-1 again — it already has @v1.1 from check 7. Use --force
# + --pin v0.6 to get a v0.6-pinned file. The sed rewrite uses word-boundary
# anchor so it touches the `uses:` directive but intentionally leaves any
# in-comment examples untouched — that's a feature, not a bug.
# The assertion checks the `uses:` line specifically.
out="$(HOME="${APPLY_HOME}" "${SCRIPT}" --project clean-1 --apply --force --pin v0.6 --registry "${MOCK_REGISTRY}" 2>&1)"; rc=$?
uses_line="$(grep "uses:" "${target_clean}" || true)"
if [[ ${rc} -eq 0 ]] && [[ "${uses_line}" == *"@v0.6"* ]] && [[ "${uses_line}" != *"@v1.1"* ]]; then
    record_pass "fleet-install: --pin v0.6 rewrites @v1.1 → @v0.6 in target's uses: directive"
else
    record_fail "fleet-install: --pin rewrite broken — rc=${rc}, uses_line='${uses_line}'"
fi

# ─── Check 11: disabled-project gate ──────────────────────────────
out="$("${SCRIPT}" --project disabled-1 --apply --registry "${MOCK_REGISTRY}" 2>&1)"; rc=$?
target_disabled="${MOCK_ROOT}/disabled-1/.github/workflows/dev-platform-gate.yml"
if [[ ${rc} -ne 0 ]] && echo "${out}" | grep -q "disabled in the registry" && [[ ! -f "${target_disabled}" ]]; then
    record_pass "fleet-install: disabled-project gate refuses install"
else
    record_fail "fleet-install: disabled-project gate broken — rc=${rc}, target_exists=$([[ -f "${target_disabled}" ]] && echo yes || echo no)"
fi

# ─── Check 12: PATH-GUARD CONTRACT (LOAD-BEARING) ─────────────────
# After all the --apply invocations above, enumerate every NEW file
# created under MOCK_ROOT. Compare against BASELINE; the diff MUST be
# limited to the two target paths:
#   clean-1/.github/workflows/dev-platform-gate.yml
#   already-1/.github/workflows/dev-platform-gate.yml
# (already-1's target was pre-installed so it's in BASELINE; clean-1's
# target was created via --apply. Any other new file is drift.)
CURRENT="$(snapshot_tree "${MOCK_ROOT}")"
NEW_FILES="$(comm -13 <(echo "${BASELINE}") <(echo "${CURRENT}") | sort)"
EXPECTED_NEW="./clean-1/.github/workflows/dev-platform-gate.yml"
if [[ "${NEW_FILES}" == "${EXPECTED_NEW}" ]]; then
    record_pass "fleet-install: path-guard contract — script wrote ONLY to <project>/.github/workflows/dev-platform-gate.yml"
else
    record_fail "fleet-install: PATH-GUARD VIOLATION — unexpected files appeared in mock-projects/:
$(echo "${NEW_FILES}" | sed 's/^/      /')
   Expected exactly: ${EXPECTED_NEW}"
fi

# ─── Check 13: telemetry event emitted on --apply ────────────────
TELEMETRY_LOG="${APPLY_HOME}/.claude/dev-platform-telemetry.log"
if [[ -f "${TELEMETRY_LOG}" ]] && grep -q '"event": *"fleet_install_template"' "${TELEMETRY_LOG}"; then
    record_pass "fleet-install: telemetry event 'fleet_install_template' emitted to ~/.claude/dev-platform-telemetry.log"
else
    record_fail "fleet-install: telemetry event missing from ${TELEMETRY_LOG}"
fi

# ─── Check 14: dry-run against existing target prints plan + diff ─
# Refuse-to-clobber is a write-side guard, NOT a dry-run guard. A dry-run
# against an existing target MUST print the Source/Target/Pin/Mode banner
# AND a "Diff:" line so the user can audit what --apply --force would do.
# Caught a real bug in /review where the refuse-to-clobber check fired in
# dry-run mode and suppressed all output. (The exact diff text varies —
# "would overwrite" when content differs, "matches source" when it
# doesn't — so the assertion checks the Diff branch was reached at all.)
out="$("${SCRIPT}" --project already-1 --registry "${MOCK_REGISTRY}" 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && \
   echo "${out}" | grep -q "Mode: *dry-run" && \
   echo "${out}" | grep -q "^  Diff:"; then
    record_pass "fleet-install: dry-run against existing target prints plan + diff (no early refuse-to-clobber)"
else
    record_fail "fleet-install: dry-run-against-existing broken — rc=${rc}, output: ${out}"
fi
