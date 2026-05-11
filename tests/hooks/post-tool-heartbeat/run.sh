#!/usr/bin/env bash
# tests/hooks/post-tool-heartbeat/run.sh — fixture suite for post-tool-heartbeat.sh.
# For each fixture, pipes it into the hook script and asserts the appended
# log line matches the expected pattern.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

LOG="${HOME}/.claude/dev-platform-telemetry.log"
HOOK="${REPO}/hooks/post-tool-heartbeat.sh"

# Each fixture → expected log-line regex (anchored to end of line)
declare -A CASES=(
    ["valid.json"]="tool=Bash$"
    ["invalid.json"]="tool=\?$"
    ["empty.txt"]="tool=\?$"
    ["missing-tool-name.json"]="tool=\?$"
)

for fixture in valid.json invalid.json empty.txt missing-tool-name.json; do
    expected="${CASES[$fixture]}"
    bash "${HOOK}" < "${HERE}/${fixture}" >/dev/null 2>&1
    last_line="$(tail -1 "${LOG}" 2>/dev/null || echo '')"
    if [[ "${last_line}" =~ ${expected} ]]; then
        record_pass "heartbeat ${fixture} → matches /${expected}/"
    else
        record_fail "heartbeat ${fixture} expected /${expected}/, got: ${last_line}"
    fi
done
