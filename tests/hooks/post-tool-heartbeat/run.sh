#!/usr/bin/env bash
# tests/hooks/post-tool-heartbeat/run.sh — fixture suite for post-tool-heartbeat.sh.
# For each fixture, pipes it into the hook script and asserts the appended
# log line is valid JSONL matching the v0.5 schema (event=tool_use_end).
#
# Updated for v0.5: the hook now emits JSONL (matches monitoring/schemas/event-v1.json)
# instead of the legacy `<ts> tool=<name>` text format. The aggregator still reads
# legacy lines, but new emissions are JSONL.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

LOG="${HOME}/.claude/dev-platform-telemetry.log"
HOOK="${REPO}/hooks/post-tool-heartbeat.sh"

# Each fixture → expected (tool, session_id, tool_call_id) tuple in the emitted
# JSONL event. valid.json carries all three fields and exercises full extraction;
# the other three lack the keys and must degrade to "?" across the board.
declare -A EXPECTED_TOOL=(
    ["valid.json"]="Bash"
    ["invalid.json"]="?"
    ["empty.txt"]="?"
    ["missing-tool-name.json"]="?"
)
declare -A EXPECTED_SESSION=(
    ["valid.json"]="test-session-123"
    ["invalid.json"]="?"
    ["empty.txt"]="?"
    ["missing-tool-name.json"]="?"
)
declare -A EXPECTED_TCID=(
    ["valid.json"]="toolu_test_42"
    ["invalid.json"]="?"
    ["empty.txt"]="?"
    ["missing-tool-name.json"]="?"
)

for fixture in valid.json invalid.json empty.txt missing-tool-name.json; do
    want_tool="${EXPECTED_TOOL[$fixture]}"
    want_session="${EXPECTED_SESSION[$fixture]}"
    want_tcid="${EXPECTED_TCID[$fixture]}"
    bash "${HOOK}" < "${HERE}/${fixture}" >/dev/null 2>&1
    rc=$?
    if [[ $rc -ne 0 ]]; then
        record_fail "heartbeat ${fixture} hook exited non-zero (${rc}) — must always exit 0"
        continue
    fi
    last_line="$(tail -1 "${LOG}" 2>/dev/null || echo '')"
    # Validate: line is valid JSON, v=1, event=tool_use_end, extract three fields.
    fields="$(python3 -c '
import sys, json
try:
    d = json.loads(sys.argv[1])
    v = d.get("v")
    ev = d.get("event")
    if v != 1:
        print("BAD_V:" + str(v))
    elif ev != "tool_use_end":
        print("BAD_EVENT:" + str(ev))
    else:
        # Tab-separated tool|session|tcid for the bash side to parse
        print(d.get("tool", "MISSING") + "\t" + d.get("session_id", "MISSING") + "\t" + d.get("tool_call_id", "MISSING"))
except Exception as e:
    print("PARSE_ERROR:" + str(e))
' "${last_line}" 2>&1)"

    # Detect parse-level failures up front
    if [[ "${fields}" == BAD_V:* || "${fields}" == BAD_EVENT:* || "${fields}" == PARSE_ERROR:* ]]; then
        record_fail "heartbeat ${fixture} schema invalid: ${fields} | line: ${last_line}"
        continue
    fi

    IFS=$'\t' read -r got_tool got_session got_tcid <<< "${fields}"

    if [[ "${got_tool}" == "${want_tool}" && "${got_session}" == "${want_session}" && "${got_tcid}" == "${want_tcid}" ]]; then
        record_pass "heartbeat ${fixture} → tool=${got_tool} session=${got_session} tcid=${got_tcid}"
    else
        record_fail "heartbeat ${fixture} mismatch — expected tool=${want_tool} session=${want_session} tcid=${want_tcid}; got tool=${got_tool} session=${got_session} tcid=${got_tcid}"
    fi
done
