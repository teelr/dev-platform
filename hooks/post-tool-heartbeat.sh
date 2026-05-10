#!/usr/bin/env bash
# PostToolUse heartbeat — appends one telemetry line per tool call to a log
# file. Foundation for R2 Monitoring (gate-pass rate, /code retry count,
# /review catch rate aggregation). Trivially safe: writes to log, exits 0,
# never blocks. Reads Claude Code's PostToolUse event JSON from stdin and
# extracts the tool name; degrades gracefully to 'tool=?' on parse failure.

set -euo pipefail

LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${LOG}")"

# Read event payload (best-effort; never error)
event_json="$(cat 2>/dev/null || echo '{}')"

# Extract tool name from PostToolUse payload (degrade gracefully if shape differs)
tool_name="$(echo "${event_json}" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get("tool_name", "?"))
except Exception:
    print("?")
' 2>/dev/null || echo "?")"

# One-line entry: ISO-8601 timestamp + tool name
echo "$(date -Iseconds) tool=${tool_name}" >> "${LOG}"

exit 0
