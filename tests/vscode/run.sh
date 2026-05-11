#!/usr/bin/env bash
# tests/vscode/run.sh — fixture suite for v0.6 VSCode coverage.
# Validates the tracked extensions list format and confirms install.sh
# gracefully skips when the `code` CLI is unavailable.
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 (R3) auto-discovery
# contract — adding tests/<suite>/*.sh is enough; no orchestrator edit.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

LIVE_FILE="${REPO}/extensions/vscode/server-extensions.json"

# Check 1: live tracked file is valid JSON array of strings
if jq -e 'type == "array" and all(type == "string")' "${LIVE_FILE}" >/dev/null 2>&1; then
    n="$(jq length "${LIVE_FILE}")"
    record_pass "vscode: server-extensions.json is JSON array of strings (${n} entries)"
else
    record_fail "vscode: server-extensions.json is not a JSON array of strings"
fi

# Check 2: every entry matches publisher.name extension-ID convention
if jq -e 'all(test("^[a-z0-9][a-z0-9_-]*\\.[a-z0-9_-]+$"))' "${LIVE_FILE}" >/dev/null 2>&1; then
    record_pass "vscode: every entry matches publisher.name convention"
else
    record_fail "vscode: some entry violates publisher.name convention"
fi

# Check 3: fixture valid-list.json parses as 3-entry array of strings
if jq -e 'type == "array" and all(type == "string") and length == 3' \
        "${HERE}/fixtures/valid-list.json" >/dev/null 2>&1; then
    record_pass "vscode: valid-list fixture parses as 3-entry array"
else
    record_fail "vscode: valid-list fixture shape wrong"
fi

# Check 4: fixture empty-list.json is a valid empty array
if jq -e 'type == "array" and length == 0' \
        "${HERE}/fixtures/empty-list.json" >/dev/null 2>&1; then
    record_pass "vscode: empty-list fixture is empty array"
else
    record_fail "vscode: empty-list fixture shape wrong"
fi

# Check 5: install.sh skips gracefully when `code` CLI is absent.
# Two `code` binaries can exist on this system (vscode-server + native VS Code),
# so PATH stripping alone isn't enough. Build a sandboxed bin dir with just the
# core utilities install.sh needs (bash, dirname, pwd, jq, grep, etc.), without
# any `code` symlink. install_vscode's `command -v code` then fails and the
# function returns 0 gracefully.
SANDBOX_BIN="$(mktemp -d /tmp/vt-sandbox.XXXXXX)"
for cmd in bash dirname pwd jq grep cat mkdir test rm sed; do
    if path="$(command -v "${cmd}" 2>/dev/null)"; then
        ln -s "${path}" "${SANDBOX_BIN}/${cmd}" 2>/dev/null || true
    fi
done
if PATH="${SANDBOX_BIN}" bash "${REPO}/scripts/install.sh" vscode 2>&1 | \
        grep -q "code.*CLI not on PATH"; then
    record_pass "vscode: install.sh skips gracefully when 'code' CLI is absent"
else
    record_fail "vscode: install.sh did not skip gracefully when 'code' missing"
fi
rm -rf "${SANDBOX_BIN}"

# Check 6: scripts/sync-vscode.sh syntax clean
if bash -n "${REPO}/scripts/sync-vscode.sh"; then
    record_pass "vscode: sync-vscode.sh bash syntax clean"
else
    record_fail "vscode: sync-vscode.sh bash syntax error"
fi

# --- Capture/deploy round-trip via mock `code` (closes the /review #3 gap) ---
#
# Mock `code` binary lives at tests/vscode/fixtures/mock-bin/code. Setup:
#   - MOCK_STATE_FILE holds the "installed extensions" — what `code --list-extensions` returns
#   - sync-vscode.sh runs with --file pointing at a temp tracked file
#   - PATH prefixes the mock bin so `command -v code` finds it first
#
# Cleanup is handled by trap to guarantee tmpfile removal even on partial failure.

MOCK_BIN="${HERE}/fixtures/mock-bin"
ROUND_TRIP_TMP="$(mktemp -d /tmp/vscode-rt.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${ROUND_TRIP_TMP}'" EXIT

# Check 7: capture mode writes a JSON array from mock `code` state
mock_state="${ROUND_TRIP_TMP}/installed-1.txt"
tracked="${ROUND_TRIP_TMP}/tracked-1.json"
printf "a.one\nb.two\nc.three\n" > "${mock_state}"
if PATH="${MOCK_BIN}:${PATH}" MOCK_STATE_FILE="${mock_state}" \
        bash "${REPO}/scripts/sync-vscode.sh" capture --file "${tracked}" >/dev/null 2>&1; then
    actual_count=$(jq length "${tracked}")
    if [[ ${actual_count} -eq 3 ]] && \
       jq -e '. == ["a.one","b.two","c.three"]' "${tracked}" >/dev/null 2>&1; then
        record_pass "vscode: capture writes JSON array from mock state (3 entries)"
    else
        record_fail "vscode: capture wrote wrong content — got $(cat "${tracked}")"
    fi
else
    record_fail "vscode: capture mode invocation failed"
fi

# Check 8: deploy mode installs every entry from tracked file
mock_state="${ROUND_TRIP_TMP}/installed-2.txt"
tracked="${ROUND_TRIP_TMP}/tracked-2.json"
: > "${mock_state}"  # start empty
echo '["x.alpha","y.beta","z.gamma"]' > "${tracked}"
if PATH="${MOCK_BIN}:${PATH}" MOCK_STATE_FILE="${mock_state}" \
        bash "${REPO}/scripts/sync-vscode.sh" deploy --file "${tracked}" >/dev/null 2>&1; then
    installed_count=$(wc -l < "${mock_state}")
    if [[ ${installed_count} -eq 3 ]] && \
       grep -qxF "x.alpha" "${mock_state}" && \
       grep -qxF "y.beta" "${mock_state}" && \
       grep -qxF "z.gamma" "${mock_state}"; then
        record_pass "vscode: deploy installs every tracked entry (3/3 into mock state)"
    else
        record_fail "vscode: deploy missing entries — installed: $(tr '\n' ' ' < "${mock_state}")"
    fi
else
    record_fail "vscode: deploy mode invocation failed"
fi

# Check 9: diff mode reports no drift when tracked matches mock state
mock_state="${ROUND_TRIP_TMP}/installed-3.txt"
tracked="${ROUND_TRIP_TMP}/tracked-3.json"
printf "d.one\ne.two\n" > "${mock_state}"
echo '["d.one","e.two"]' > "${tracked}"
out="$(PATH="${MOCK_BIN}:${PATH}" MOCK_STATE_FILE="${mock_state}" \
        bash "${REPO}/scripts/sync-vscode.sh" diff --file "${tracked}" 2>&1)"
rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "no drift"; then
    record_pass "vscode: diff reports no drift when tracked matches mock state"
else
    record_fail "vscode: diff false drift — rc=${rc}, out=${out:0:200}"
fi

# Check 10: diff mode reports drift (exit 1) when tracked doesn't match
mock_state="${ROUND_TRIP_TMP}/installed-4.txt"
tracked="${ROUND_TRIP_TMP}/tracked-4.json"
printf "f.one\n" > "${mock_state}"
echo '["g.two"]' > "${tracked}"   # tracked has g.two, but mock state has f.one
out="$(PATH="${MOCK_BIN}:${PATH}" MOCK_STATE_FILE="${mock_state}" \
        bash "${REPO}/scripts/sync-vscode.sh" diff --file "${tracked}" 2>&1)"
rc=$?
if [[ ${rc} -eq 1 ]] && echo "${out}" | grep -q "DRIFT detected"; then
    record_pass "vscode: diff correctly reports drift (exit 1) when state diverges"
else
    record_fail "vscode: diff missed drift — rc=${rc}, out=${out:0:200}"
fi
