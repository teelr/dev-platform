#!/usr/bin/env bash
# PostToolUse heartbeat — emits one `tool_use_end` JSONL event per tool call.
# Pairs with pre-tool-use.sh (tool_use_start) via tool_call_id so the aggregator
# can compute duration. Trivially safe: exits 0 on any error path; never blocks
# a Claude Code session.
#
# Schema: monitoring/schemas/event-v1.json (event=tool_use_end).
# Reads Claude Code's PostToolUse JSON from stdin; derives project from PWD.

set -uo pipefail   # NOT -e: failures must not bubble up

LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${LOG}")"

event_json="$(cat 2>/dev/null || echo '{}')"

# Single Python invocation: parse stdin, derive project from PWD, emit JSONL.
# Fallback echo on any Python failure guarantees a log line + exit 0.
python3 - "${PWD}" "${event_json}" >> "${LOG}" 2>/dev/null <<'PY' || \
    echo "{\"v\":1,\"ts\":\"$(date -Iseconds)\",\"event\":\"tool_use_end\",\"session_id\":\"?\",\"project\":\"?\",\"tool\":\"?\",\"tool_call_id\":\"?\"}" >> "${LOG}"
import sys, json
from datetime import datetime, timezone

cwd = sys.argv[1]
raw = sys.argv[2]


def project_for(cwd):
    if cwd.startswith("/home/rich/dev/projects/"):
        parts = cwd.split("/")
        if len(parts) >= 6:
            return parts[5]
    if cwd == "/home/rich/dev" or cwd.startswith("/home/rich/dev/"):
        return "dev-platform"
    return "other"


try:
    payload = json.loads(raw)
except Exception:
    payload = {}

event = {
    "v": 1,
    "ts": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
    "event": "tool_use_end",
    "session_id": payload.get("session_id", "?"),
    "project": project_for(cwd),
    "tool": payload.get("tool_name", "?"),
    "tool_call_id": payload.get("tool_use_id", "?"),
}
print(json.dumps(event))
PY

exit 0
