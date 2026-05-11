#!/usr/bin/env python3
"""Centralized telemetry event emitter for dev-platform hooks.

Reads a JSON payload from stdin, derives project from the CWD argument,
emits one JSONL event matching monitoring/schemas/event-v1.json on stdout.

Usage:
    python3 _emit_event.py <event_type> <cwd>

Event types:
    session_start    - Captures cwd field in the event
    user_prompt      - Reads stdin payload's prompt; emits only if slash command
    tool_use_start   - Pairs with tool_use_end via tool_call_id
    tool_use_end     - Pairs with tool_use_start

Exits 0 on successful emission. Exits 0 silently (no output) when:
    - user_prompt receives a non-slash-command prompt
    - user_prompt's prompt field is not a string
Exits 1 on argument or event_type errors (caller's `|| true` or fallback
echo handles it; this script never crashes a Claude Code session).

Design note: the bash wrappers (hooks/*.sh) decide whether to emit a
fallback line on this script's failure. session-start.sh and
post-tool-heartbeat.sh do; user-prompt.sh and pre-tool-use.sh do not.
See monitoring/README.md > Fallback asymmetry for rationale.
"""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone


def project_for(cwd: str) -> str:
    """Derive project tag from cwd.

    /home/rich/dev or descendants (NOT under projects/) -> "dev-platform"
    /home/rich/dev/projects/<name>/...                  -> "<name>"
    everything else                                     -> "other"
    """
    if cwd.startswith("/home/rich/dev/projects/"):
        parts = cwd.split("/")
        if len(parts) >= 6 and parts[5]:
            return parts[5]
    if cwd == "/home/rich/dev" or cwd.startswith("/home/rich/dev/"):
        return "dev-platform"
    return "other"


SLASH_COMMAND_RE = re.compile(r"^(/[a-zA-Z][a-zA-Z0-9_-]*)\s*(.*)$")


def build_event(event_type: str, cwd: str, payload: dict) -> dict | None:
    """Return the event dict for emission, or None if this hook should
    silently emit nothing (e.g., user_prompt for a non-slash-command).
    """
    base = {
        "v": 1,
        "ts": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "event": event_type,
        "session_id": payload.get("session_id", "?"),
        "project": project_for(cwd),
    }

    if event_type == "session_start":
        base["cwd"] = cwd
        return base

    if event_type == "user_prompt":
        prompt_raw = payload.get("prompt", "")
        # Defensive: non-string prompt field would crash .strip(); skip silently.
        if not isinstance(prompt_raw, str):
            return None
        m = SLASH_COMMAND_RE.match(prompt_raw.strip())
        if not m:
            # Not a slash command; emit nothing (free-text bodies stay private).
            return None
        base["command"] = m.group(1)
        base["args"] = m.group(2)
        return base

    if event_type in ("tool_use_start", "tool_use_end"):
        base["tool"] = payload.get("tool_name", "?")
        base["tool_call_id"] = payload.get("tool_use_id", "?")
        return base

    # Unknown event type; the caller's || fallback handles this.
    return None


def main() -> int:
    if len(sys.argv) < 3:
        return 1

    event_type = sys.argv[1]
    cwd = sys.argv[2]

    try:
        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip() else {}
    except Exception:
        payload = {}

    event = build_event(event_type, cwd, payload)
    if event is None:
        return 0  # Silent success (intentional: e.g., non-slash user_prompt)

    print(json.dumps(event))
    return 0


if __name__ == "__main__":
    sys.exit(main())
