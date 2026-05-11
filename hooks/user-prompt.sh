#!/usr/bin/env bash
# UserPromptSubmit — emits `user_prompt` JSONL events for slash-command
# invocations only. Delegates to hooks/_emit_event.py which handles the
# slash-command regex + privacy logic. Free-text prompts produce no event.
# Failure-tolerant: exits 0 on any error path; never blocks a session.
#
# Fallback strategy: silent on emitter failure (no fallback line). We can't
# tell whether a failed-parse payload was a slash command or free text;
# emitting a degraded `user_prompt` would leak the existence of an unparsed
# user message. See monitoring/README.md > Fallback asymmetry.

set -uo pipefail   # NOT -e

LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${LOG}")"

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "${HOOK_DIR}/_emit_event.py" user_prompt "${PWD}" >> "${LOG}" 2>/dev/null || true

exit 0
