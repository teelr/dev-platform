#!/usr/bin/env bash
# SessionStart — emits one `session_start` JSONL event per Claude Code
# session. Delegates the JSON shaping to hooks/_emit_event.py so all hooks
# share one project_for() and one schema.
# Failure-tolerant: exits 0 on any error path; never blocks a session.
#
# Fallback strategy: emit a degraded JSONL line on emitter failure so
# the aggregator still has a session_start marker (see monitoring/README.md
# > Fallback asymmetry).

set -uo pipefail   # NOT -e

LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${LOG}")"

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "${HOOK_DIR}/_emit_event.py" session_start "${PWD}" >> "${LOG}" 2>/dev/null || \
    echo "{\"v\":1,\"ts\":\"$(date -Iseconds)\",\"event\":\"session_start\",\"session_id\":\"?\",\"project\":\"?\",\"cwd\":\"?\"}" >> "${LOG}"

exit 0
