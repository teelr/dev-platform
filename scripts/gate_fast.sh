#!/usr/bin/env bash
# scripts/gate_fast.sh — dev-platform constitutional gate. Runs lift checks
# (taxonomy enforcement, bash syntax, JSON validity, secrets scan, live
# ~/.claude/ verify) plus all per-suite test runners under tests/. Aggregates
# PASS/FAIL/SKIP and exits non-zero on any FAIL.
#
# Usage: ./scripts/gate_fast.sh
# Runtime: ~15s

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Shared count file so subshell runners feed their PASS/FAIL/SKIP into the
# orchestrator's totals. Assert helpers append to this when set.
export _GATE_COUNTS_FILE
_GATE_COUNTS_FILE="$(mktemp /tmp/gate-counts.XXXXXX)"
trap "rm -f '${_GATE_COUNTS_FILE}'" EXIT

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

START=$(date +%s)
echo "=== gate fast ==="
echo ""
echo "--- lift checks ---"

# Taxonomy enforcement
if (cd "${REPO}" && bash scripts/check_spec_taxonomy.sh >/dev/null 2>&1); then
    record_pass "spec taxonomy"
else
    record_fail "spec taxonomy (check_spec_taxonomy.sh exit 1)"
fi

# Bash syntax — all .sh files under scripts/, hooks/, scaffolding/*/scripts/, tests/
syntax_pass=0
syntax_fail=0
while IFS= read -r -d '' f; do
    if bash -n "${f}" 2>/dev/null; then
        syntax_pass=$((syntax_pass + 1))
    else
        syntax_fail=$((syntax_fail + 1))
        record_fail "bash syntax: ${f#${REPO}/}"
    fi
done < <(find \
    "${REPO}/scripts" \
    "${REPO}/hooks" \
    "${REPO}/scaffolding"/*/scripts \
    "${REPO}/tests" \
    -type f -name "*.sh" -print0 2>/dev/null)
[[ ${syntax_fail} -eq 0 ]] && record_pass "bash syntax (${syntax_pass} scripts)"

# JSON validity — all .json files under settings/, scaffolding/
json_pass=0
json_fail=0
while IFS= read -r -d '' f; do
    if python3 -c "import json; json.load(open('${f}'))" 2>/dev/null; then
        json_pass=$((json_pass + 1))
    else
        json_fail=$((json_fail + 1))
        record_fail "JSON validity: ${f#${REPO}/}"
    fi
done < <(find "${REPO}/settings" "${REPO}/scaffolding" -type f -name "*.json" -print0 2>/dev/null)
[[ ${json_fail} -eq 0 ]] && record_pass "JSON validity (${json_pass} files)"

# Secrets scan — literal passwords in tracked settings.json
if grep -qE 'PGPASSWORD=[a-z]' "${REPO}/settings/settings.json" 2>/dev/null; then
    record_fail "secrets: literal password in tracked settings.json"
else
    record_pass "secrets scan (no literal pwds in tracked file)"
fi

# Live ~/.claude/ verify — checks that the deployed symlinks under ~/.claude/
# match the tracked source. This is a developer-environment integrity check
# meaningful only where the repo has been deployed (via scripts/install.sh).
# On a fresh CI runner ~/.claude/ doesn't exist, so the check has nothing to
# verify and we record SKIP rather than FAIL. The CI environment runs all
# OTHER lift checks + every test suite — only the live-deploy check is
# environment-dependent.
if [[ ! -d "${HOME}/.claude" ]]; then
    record_skip "live ~/.claude/ verify (no ~/.claude/ — likely CI runner)"
elif bash "${REPO}/scripts/verify.sh" >/dev/null 2>&1; then
    record_pass "live ~/.claude/ verify"
else
    record_fail "live ~/.claude/ verify (drift — run scripts/verify.sh for details)"
fi

# Per-suite test runners. Auto-discovery: every subdirectory of tests/
# (except tests/helpers/) is a suite. Within each suite, every executable
# *.sh file is a runner. New suites land automatically without editing
# this orchestrator — matching the contract documented in tests/README.md.
echo ""
echo "--- test suites ---"

for suite_dir in "${REPO}/tests"/*/; do
    suite_dir="${suite_dir%/}"
    suite_name="$(basename "${suite_dir}")"
    # Skip the shared helpers/ dir — it's not a suite.
    [[ "${suite_name}" == "helpers" ]] && continue

    # Find every executable *.sh under this suite, any depth (run.sh inside
    # per-fixture subdirs like hooks/post-tool-heartbeat/ is supported).
    # Exclude fixtures/ — runnable fixtures (mock binaries, mock project
    # gates) live there and are NOT test runners. The contract: test runners
    # live at tests/<suite>/*.sh or tests/<suite>/<test>/*.sh, NEVER under
    # tests/<suite>/fixtures/. Added v0.8 Phase 1 when fleet-gate's mock-
    # project tree introduced runnable gate.sh files under fixtures/.
    found_any=0
    while IFS= read -r runner; do
        found_any=1
        echo "  suite: ${runner#${REPO}/}"
        if [[ -x "${runner}" ]]; then
            bash "${runner}" || true   # PASS/FAIL captured via assert.sh helpers
        else
            record_fail "${suite_name}: ${runner#${REPO}/} not executable"
        fi
    done < <(find "${suite_dir}" -type f -name "*.sh" \
                ! -path "*/fixtures/*" \
                2>/dev/null)
    [[ ${found_any} -eq 0 ]] && record_skip "${suite_name} (no *.sh runners found)"
done

# Summary — aggregate from the shared count file so subshell runners
# contribute to the totals (their in-subshell counters don't propagate
# back to this script's scope).
echo ""
echo "=== summary ==="
END=$(date +%s)

total_pass=$(grep -c "^PASS$" "${_GATE_COUNTS_FILE}" 2>/dev/null); total_pass=${total_pass:-0}
total_fail=$(grep -c "^FAIL$" "${_GATE_COUNTS_FILE}" 2>/dev/null); total_fail=${total_fail:-0}
total_skip=$(grep -c "^SKIP$" "${_GATE_COUNTS_FILE}" 2>/dev/null); total_skip=${total_skip:-0}

echo "  ${total_pass} PASS  ${total_fail} FAIL  ${total_skip} SKIP  ($((END - START))s)"

# Emit gate_run telemetry event (v0.5 Phase 2, Change 7). Failure-tolerant:
# Python failure is silent; the gate's exit code is determined ONLY by
# total_fail above, never by the emission.
_GATE_LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${_GATE_LOG}")" 2>/dev/null || true
_GATE_OUTCOME="pass"
[[ ${total_fail} -gt 0 ]] && _GATE_OUTCOME="fail"
python3 - "${PWD}" "${_GATE_OUTCOME}" "${total_pass}" "${total_fail}" "$((END - START))" >> "${_GATE_LOG}" 2>/dev/null <<'PY' || true
import sys, json
from datetime import datetime, timezone

cwd, outcome, p, f, d = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])

def project_for(cwd):
    if cwd.startswith("/home/rich/dev/projects/"):
        parts = cwd.split("/")
        if len(parts) >= 6 and parts[5]:
            return parts[5]
    if cwd == "/home/rich/dev" or cwd.startswith("/home/rich/dev/"):
        return "dev-platform"
    return "other"

event = {
    "v": 1,
    "ts": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
    "event": "gate_run",
    "session_id": "gate",
    "project": project_for(cwd),
    "outcome": outcome,
    "pass_count": p,
    "fail_count": f,
    "duration_s": d,
}
print(json.dumps(event))
PY

if [[ ${total_fail} -gt 0 ]]; then
    echo ""
    echo "GATE FAST: FAIL"
    exit 1
fi
echo "GATE FAST: PASS"
