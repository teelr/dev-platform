#!/usr/bin/env bash
# PreToolUse — emits one `tool_use_start` JSONL event before each tool call.
# Pairs with post-tool-heartbeat.sh (tool_use_end) via tool_call_id so the
# aggregator can compute duration. Delegates to hooks/_emit_event.py.
# CRITICAL: must NEVER block a tool call; exits 0 on any error.
#
# Fallback strategy: silent on emitter failure (no fallback line). A
# fallback start with `tool_call_id="?"` would never pair with a real
# end event, producing two orphan rows instead of one. Silent failure
# leaves the end orphaned alone — cleaner for the aggregator's pairing
# logic. See monitoring/README.md > Fallback asymmetry.

set -uo pipefail   # NOT -e

LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${LOG}")"

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "${HOOK_DIR}/_emit_event.py" tool_use_start "${PWD}" >> "${LOG}" 2>/dev/null || true

exit 0
