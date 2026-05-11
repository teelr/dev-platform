#!/usr/bin/env bash
# PostToolUse heartbeat — emits one `tool_use_end` JSONL event per tool
# call. Pairs with pre-tool-use.sh (tool_use_start) via tool_call_id.
# Delegates to hooks/_emit_event.py so all hooks share one project_for()
# and one schema.
# Failure-tolerant: exits 0 on any error path; never blocks a session.
#
# Fallback strategy: emit a degraded JSONL line on emitter failure so
# the aggregator still records the tool call's occurrence (even if
# unpaired). See monitoring/README.md > Fallback asymmetry.

set -uo pipefail   # NOT -e

LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${LOG}")"

python3 /home/rich/.claude/hooks/_emit_event.py tool_use_end "${PWD}" >> "${LOG}" 2>/dev/null || \
    echo "{\"v\":1,\"ts\":\"$(date -Iseconds)\",\"event\":\"tool_use_end\",\"session_id\":\"?\",\"project\":\"?\",\"tool\":\"?\",\"tool_call_id\":\"?\"}" >> "${LOG}"

exit 0
