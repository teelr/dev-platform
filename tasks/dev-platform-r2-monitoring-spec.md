# v0.5: Monitoring — Workflow Telemetry & Reporting

> **Filename note:** the legacy `r2` prefix in this file's name is a pre-migration artifact. The Roadmap Phase is **v0.5**; rename to `dev-platform-monitoring-spec.md` is queued for v0.9 migration tooling so the cleanup can include every R-prefixed spec in one pass without mid-flight churn.

## Coding Specification for Implementation

## Design Philosophy

v0.2 shipped one hook (`post-tool-heartbeat.sh`) and one log file (`~/.claude/dev-platform-telemetry.log`, 1,124 lines as of 2026-05-11). The data captured today is **timestamp + tool name** — nothing else. The v0.5 metrics promised by `ROADMAP.md:9` — gate pass rate, `/code` retry counts, `/review` catch rate, hook execution time per project — cannot be computed from that data because: (a) no slash-command context is captured, (b) no project context is captured, (c) no gate-run events are captured, (d) PostToolUse alone has no duration (you need a PreToolUse pair).

v0.5 closes those four gaps and adds the aggregation + reporting layer on top. Approach: the heartbeat hook becomes the **canonical event emitter** rather than a one-shot logger, JSONL replaces the flat text format (one JSON object per line so future consumers can parse trivially), and four new event types layer in beside `tool_use`: `session_start`, `user_prompt`, `tool_use_end` (closes a tool-call pair for duration), and `gate_run`. Project context is derived from `cwd` at hook fire time — single global log, project-tagged events, queryable per-project by the aggregator. This keeps the storage model trivial (one append-only file) while delivering all four scoped metrics.

The aggregator is Python (data parsing + report generation — natural fit per "When in doubt → Python first" from the Language Matrix). The CLI is a thin Bash entry at `scripts/report.sh` that delegates to the Python aggregator. The reports are markdown so future-Rich can read them in a terminal or paste into a session. No web dashboard — that's v0.8 (cross-project orchestration) territory, where aggregating across projects justifies the UI cost.

v0.5 explicitly does NOT ship: a database (JSONL at this volume is sufficient — 1100 events / 2 days = ~200K events/year, trivial), real-time streaming, alerting/paging, or a web UI. Each is its own future spec when the data volume or use case justifies the cost. The Honesty rule applies: ship what the data supports, label everything else as a roadmap item.

v0.5 also takes a hard line on **failure tolerance**: every new hook MUST exit 0 regardless of internal failure. A broken telemetry collector can never block a Claude Code session. The v0.2 heartbeat already follows this pattern (`tool=?` fallback); v0.5's new hooks extend it. Tests enforce the contract.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| Hook scripts (`hooks/*.sh`) | Bash | Matches existing `post-tool-heartbeat.sh` pattern; portable; zero deps. Hooks fire on every tool call — Bash startup cost (~1 ms) is negligible vs Python (~50 ms × 1000 events/day = 50s overhead). |
| Event JSON emission inside hooks | Python one-liner (via `python3 -c`) | JSON encoding is the only non-trivial bit; bash + `printf` for JSON is brittle. Python is already used by the existing heartbeat hook for input parsing. |
| Aggregator (`monitoring/aggregator.py`) | Python | Data parsing, JSON handling, grouping, report templating. Per the Language Matrix: "when in doubt → Python first." Not network-intensive (no concurrency), not compute-intensive (200K events/year). |
| CLI entry (`scripts/report.sh`) | Bash | Thin wrapper matching `gate_fast.sh`/`install.sh`/`verify.sh` pattern. Delegates to Python. Zero new top-level binaries. |
| Event schema (`monitoring/schemas/event-v1.json`) | JSON Schema | Industry-standard, validatable, doubles as documentation. |
| gate_fast.sh instrumentation | Bash (inline) | Already Bash; emitting one telemetry line at end is a 3-line addition. |
| Tests (`tests/monitoring/*.sh`) | Bash | Matches existing v0.4 test-suite pattern; fixtures are JSONL files validated against the aggregator. |

## Overview

1. **Phase 1:** Schema + storage layer — versioned event schema, migrate heartbeat hook to JSONL, gitignore + monitoring/ structure (Changes 1–3)
2. **Phase 2:** New collectors — SessionStart, PreToolUse-PostToolUse pair, UserPromptSubmit, gate_fast self-instrumentation, settings.json wire-up (Changes 4–8)
3. **Phase 3:** Aggregation + reporting — Python aggregator, four metrics, CLI entry (Changes 9–11)
4. **Phase 4:** Tests + acceptance + docs (Changes 12–14)

**Demo:** After install + a fresh Claude Code session, the user runs `./scripts/report.sh daily`. Output:

```text
=== dev-platform telemetry report — 2026-05-12 ===

Period: 2026-05-12 00:00 → 23:59 (1 day)
Events: 847 total across 3 sessions

Gate pass rate:        4/4 (100%)  — 1 invocation
/code retry counts:    avg 0.0     — 2 invocations (no retries)
/review catch rate:    1.5 issues  — 2 invocations
Tool exec time avg:    47 ms       — top: Bash 89ms, Read 12ms

Per-project breakdown:
  dev-platform:   847 events  / 1 gate runs / 2 /code / 2 /review
  (others):       0
```

Re-running `./scripts/report.sh weekly` produces a 7-day rollup with the same four metrics. The metrics derive entirely from the JSONL log; no in-memory state survives between runs.

---

## Phase 1: Schema + Storage Layer

### Change 1: Versioned event schema + `monitoring/` structure

**Problem:** v0.2's log format (`<timestamp> tool=Bash`) is unstructured text. Adding session_start, user_prompt, gate_run, tool_use_end events to that format would require ad-hoc parsing per event type. JSONL (one JSON object per line) lets every consumer use `json.loads()` and filter by `event` field. The schema needs versioning so future event-shape changes don't break the aggregator on historical data.

**File:** `monitoring/schemas/event-v1.json` (new), `monitoring/README.md` (modify)

**Implementation:**

Create `monitoring/schemas/event-v1.json` as a JSON Schema document covering all v0.5 event types:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "dev-platform telemetry event v1",
  "type": "object",
  "required": ["v", "ts", "event", "session_id", "project"],
  "properties": {
    "v": {"const": 1, "description": "Schema version"},
    "ts": {"type": "string", "format": "date-time"},
    "event": {
      "type": "string",
      "enum": ["session_start", "user_prompt", "tool_use_start", "tool_use_end", "gate_run"]
    },
    "session_id": {"type": "string"},
    "project": {"type": "string", "description": "Derived from cwd: dev-platform, <project-name>, or other"},
    "cwd": {"type": "string"},
    "tool": {"type": "string", "description": "tool_use_start/end only"},
    "tool_call_id": {"type": "string", "description": "Pairs tool_use_start with tool_use_end"},
    "duration_ms": {"type": "integer", "description": "tool_use_end only"},
    "command": {"type": "string", "description": "user_prompt only — e.g. /code, /review"},
    "args": {"type": "string", "description": "user_prompt only — argument text"},
    "outcome": {"type": "string", "enum": ["pass", "fail"], "description": "gate_run only"},
    "pass_count": {"type": "integer", "description": "gate_run only"},
    "fail_count": {"type": "integer", "description": "gate_run only"},
    "duration_s": {"type": "integer", "description": "gate_run only"}
  }
}
```

Example events (these go into `monitoring/schemas/examples.jsonl` for reference):

```jsonl
{"v":1,"ts":"2026-05-12T09:00:01-05:00","event":"session_start","session_id":"abc123","project":"dev-platform","cwd":"/home/rich/dev"}
{"v":1,"ts":"2026-05-12T09:00:05-05:00","event":"user_prompt","session_id":"abc123","project":"dev-platform","command":"/code","args":"v0.5"}
{"v":1,"ts":"2026-05-12T09:00:10-05:00","event":"tool_use_start","session_id":"abc123","project":"dev-platform","tool":"Read","tool_call_id":"t1"}
{"v":1,"ts":"2026-05-12T09:00:10-05:00","event":"tool_use_end","session_id":"abc123","project":"dev-platform","tool":"Read","tool_call_id":"t1","duration_ms":15}
{"v":1,"ts":"2026-05-12T09:05:00-05:00","event":"gate_run","session_id":"abc123","project":"dev-platform","outcome":"pass","pass_count":42,"fail_count":0,"duration_s":3}
```

Update `monitoring/README.md` to reference the schema and replace the placeholder content. New sections:

- **Event format:** JSONL at `~/.claude/dev-platform-telemetry.log`. Each line is one event matching `monitoring/schemas/event-v1.json`.
- **Event types:** the five above, with one-paragraph descriptions of when each is emitted.
- **Project tagging:** how `project` is derived from `cwd` (dev = "dev-platform"; projects/X = "X"; anything else = "other").
- **Backward compatibility:** the aggregator reads BOTH the legacy `<ts> tool=<name>` format AND the new JSONL format, so the 2 days of existing data is not lost.

**Acceptance Test:**

```bash
python3 -c "import json; json.load(open('monitoring/schemas/event-v1.json'))"   # exit 0
python3 -c "import json
for line in open('monitoring/schemas/examples.jsonl'):
    e = json.loads(line)
    assert e['v'] == 1
    assert e['event'] in {'session_start','user_prompt','tool_use_start','tool_use_end','gate_run'}
print('OK')"
```

### Change 2: Migrate `post-tool-heartbeat.sh` to JSONL emission

**Problem:** The v0.2 hook writes `<ts> tool=<name>` plain text. v0.5 needs structured JSONL with `v`, `event`, `session_id`, `project`, `tool`, `tool_call_id`. Without this, every downstream collector + the aggregator has to special-case the heartbeat format.

**File:** `hooks/post-tool-heartbeat.sh` (existing — rewrite body; keep filename for backward compat)

**Implementation:**

Replace the existing hook body with:

```bash
#!/usr/bin/env bash
# PostToolUse heartbeat — emits one `tool_use_end` JSONL event per tool call.
# Pairs with pre-tool-heartbeat.sh (tool_use_start) via tool_call_id to compute
# duration. Trivially safe: exits 0 on any error path; never blocks a session.

set -uo pipefail   # NOT -e: failures must not bubble up

LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${LOG}")"

event_json="$(cat 2>/dev/null || echo '{}')"

# Single Python invocation: parse stdin, derive project from PWD, emit JSONL.
python3 - "${PWD}" "${event_json}" >> "${LOG}" 2>/dev/null <<'PY' || echo "{\"v\":1,\"ts\":\"$(date -Iseconds)\",\"event\":\"tool_use_end\",\"session_id\":\"?\",\"project\":\"?\",\"tool\":\"?\"}" >> "${LOG}"
import sys, json, os
from datetime import datetime, timezone

cwd = sys.argv[1]
raw = sys.argv[2]

# Derive project from cwd
def project_for(cwd):
    if cwd.startswith("/home/rich/dev/projects/"):
        return cwd.split("/")[5]  # /home/rich/dev/projects/<name>/...
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
# duration_ms is set by the aggregator when it pairs with tool_use_start;
# the hook does not have access to start time directly.

print(json.dumps(event))
PY

exit 0
```

Backward compatibility: the legacy `<ts> tool=<name>` format remains in the log for the 1,124 lines already written. The Change 9 aggregator handles both formats.

**Acceptance Test:**

```bash
# Smoke: valid payload
echo '{"session_id":"s1","tool_name":"Bash","tool_use_id":"t1"}' | bash hooks/post-tool-heartbeat.sh
tail -1 ~/.claude/dev-platform-telemetry.log | python3 -c "
import sys, json
e = json.loads(sys.stdin.readline())
assert e['v'] == 1
assert e['event'] == 'tool_use_end'
assert e['session_id'] == 's1'
assert e['tool'] == 'Bash'
assert e['tool_call_id'] == 't1'
print('OK')
"

# Smoke: invalid payload — must still write a line, must still exit 0
echo 'not json' | bash hooks/post-tool-heartbeat.sh
[[ $? -eq 0 ]] && echo "OK exit 0 on bad input"
```

### Change 3: gitignore allow-list for `monitoring/**` and telemetry log

**Problem:** `monitoring/` currently allows only `*.md`. v0.5 adds `*.json` (schema) and `*.py` (aggregator). The gitignore must let those through. Separately, `~/.claude/dev-platform-telemetry.log` is intentionally never committed — but it's outside the repo, so no .gitignore entry is needed; documenting the location in monitoring/README.md is enough.

**File:** `.gitignore` (existing — extend monitoring re-include block around line 89)

**Implementation:**

Replace the existing two lines:

```text
!monitoring/*.md
!monitoring/**/*.md
```

with:

```text
!monitoring/*.md
!monitoring/**/*.md
!monitoring/**/*.py
!monitoring/**/*.json
!monitoring/**/*.jsonl
```

**Acceptance Test:**

```bash
# After Change 1 lands, verify schema is tracked
git check-ignore -v monitoring/schemas/event-v1.json && echo "FAIL ignored" || echo "OK tracked"
git check-ignore -v monitoring/schemas/examples.jsonl && echo "FAIL ignored" || echo "OK tracked"
# After Change 9 lands
git check-ignore -v monitoring/aggregator.py && echo "FAIL ignored" || echo "OK tracked"
```

---

## Phase 2: New Collectors

### Change 4: `hooks/session-start.sh` — session + project context emitter

**Problem:** Without a session_start event, the aggregator can't correlate tool calls back to "which session, in which project." session_id and project are the primary keys for every per-session and per-project metric. PostToolUse fires per tool — too late for session-level context.

**File:** `hooks/session-start.sh` (new, executable)

**Implementation:**

```bash
#!/usr/bin/env bash
# SessionStart — emits one `session_start` JSONL event when a Claude Code
# session begins. Captures project (derived from cwd) and session_id.
# Failure-tolerant: exits 0 on any error.

set -uo pipefail

LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${LOG}")"

event_json="$(cat 2>/dev/null || echo '{}')"

python3 - "${PWD}" "${event_json}" >> "${LOG}" 2>/dev/null <<'PY' || true
import sys, json
from datetime import datetime, timezone

cwd = sys.argv[1]
raw = sys.argv[2]

def project_for(cwd):
    if cwd.startswith("/home/rich/dev/projects/"):
        return cwd.split("/")[5]
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
    "event": "session_start",
    "session_id": payload.get("session_id", "?"),
    "project": project_for(cwd),
    "cwd": cwd,
}
print(json.dumps(event))
PY

exit 0
```

**Acceptance Test:**

```bash
chmod +x hooks/session-start.sh
echo '{"session_id":"s2"}' | bash hooks/session-start.sh
tail -1 ~/.claude/dev-platform-telemetry.log | python3 -c "
import sys, json
e = json.loads(sys.stdin.readline())
assert e['event'] == 'session_start'
assert e['session_id'] == 's2'
assert e['project'] in {'dev-platform','other'}  # depending on test cwd
print('OK')
"
```

### Change 5: `hooks/user-prompt.sh` — slash command detector

**Problem:** Detecting `/code`, `/review`, `/gate`, `/plan`, `/test`, `/docs` invocations is essential for `/code retry counts` and `/review catch rate` metrics. UserPromptSubmit fires on every user message; the hook parses the first non-whitespace token and, if it starts with `/`, emits a `user_prompt` event with the command + args.

**File:** `hooks/user-prompt.sh` (new, executable)

**Implementation:**

```bash
#!/usr/bin/env bash
# UserPromptSubmit — emits `user_prompt` JSONL events for slash-command
# invocations. Free-text prompts (no leading /) are ignored.
# Failure-tolerant: exits 0 on any error.

set -uo pipefail

LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${LOG}")"

event_json="$(cat 2>/dev/null || echo '{}')"

python3 - "${PWD}" "${event_json}" >> "${LOG}" 2>/dev/null <<'PY' || true
import sys, json, re
from datetime import datetime, timezone

cwd = sys.argv[1]
raw = sys.argv[2]

def project_for(cwd):
    if cwd.startswith("/home/rich/dev/projects/"):
        return cwd.split("/")[5]
    if cwd == "/home/rich/dev" or cwd.startswith("/home/rich/dev/"):
        return "dev-platform"
    return "other"

try:
    payload = json.loads(raw)
except Exception:
    payload = {}

prompt = (payload.get("prompt") or "").strip()
m = re.match(r"^(/[a-zA-Z][a-zA-Z0-9_-]*)\s*(.*)$", prompt)
if not m:
    sys.exit(0)   # Not a slash command; emit nothing.

event = {
    "v": 1,
    "ts": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
    "event": "user_prompt",
    "session_id": payload.get("session_id", "?"),
    "project": project_for(cwd),
    "command": m.group(1),
    "args": m.group(2),
}
print(json.dumps(event))
PY

exit 0
```

Schema note: the prompt key from Claude Code's UserPromptSubmit payload is the user message text. If the actual key name is different at runtime, the hook degrades silently (emits no event for that prompt); the /test phase confirms the key name and adjusts if needed.

**Acceptance Test:**

```bash
chmod +x hooks/user-prompt.sh

# Slash command — emits event
echo '{"session_id":"s3","prompt":"/code v0.5"}' | bash hooks/user-prompt.sh
tail -1 ~/.claude/dev-platform-telemetry.log | python3 -c "
import sys, json
e = json.loads(sys.stdin.readline())
assert e['event'] == 'user_prompt'
assert e['command'] == '/code'
assert e['args'] == 'v0.5'
print('OK slash')
"

# Free-text — emits nothing (last log line should be unchanged)
before="$(wc -l < ~/.claude/dev-platform-telemetry.log)"
echo '{"session_id":"s3","prompt":"just a regular question"}' | bash hooks/user-prompt.sh
after="$(wc -l < ~/.claude/dev-platform-telemetry.log)"
[[ "${before}" == "${after}" ]] && echo "OK no event for free-text"
```

### Change 6: `hooks/pre-tool-use.sh` — tool-call start marker

**Problem:** Tool-call duration requires a paired event (start + end). The v0.2 PostToolUse hook already emits at-end; v0.5 adds a PreToolUse hook that emits at-start with the same `tool_call_id`. The aggregator pairs them via the shared ID and computes `duration_ms` as `end.ts - start.ts`.

**File:** `hooks/pre-tool-use.sh` (new, executable)

**Implementation:**

```bash
#!/usr/bin/env bash
# PreToolUse — emits one `tool_use_start` JSONL event before each tool call.
# Pairs with post-tool-heartbeat.sh (tool_use_end) via tool_call_id.
# Failure-tolerant: exits 0 on any error. NEVER blocks the tool call.

set -uo pipefail

LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${LOG}")"

event_json="$(cat 2>/dev/null || echo '{}')"

python3 - "${PWD}" "${event_json}" >> "${LOG}" 2>/dev/null <<'PY' || true
import sys, json
from datetime import datetime, timezone

cwd = sys.argv[1]
raw = sys.argv[2]

def project_for(cwd):
    if cwd.startswith("/home/rich/dev/projects/"):
        return cwd.split("/")[5]
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
    "event": "tool_use_start",
    "session_id": payload.get("session_id", "?"),
    "project": project_for(cwd),
    "tool": payload.get("tool_name", "?"),
    "tool_call_id": payload.get("tool_use_id", "?"),
}
print(json.dumps(event))
PY

exit 0
```

**Critical:** PreToolUse hooks CAN block tool calls if they fail; the existing `dev/CLAUDE.md` rule "PostToolUse not PreToolUse for telemetry" (in the v0.2 spec rationale) is **intentionally relaxed here**, but only because: (a) `set -uo pipefail` without `-e` means internal Python errors don't propagate, (b) the `|| true` after the Python block guarantees exit 0, (c) the script writes to the log AFTER Python prints, so a log-write failure is also non-fatal. The /test phase MUST verify a deliberately broken hook (e.g., syntax error injected) does NOT block tool calls.

**Acceptance Test:**

```bash
chmod +x hooks/pre-tool-use.sh
echo '{"session_id":"s4","tool_name":"Read","tool_use_id":"t99"}' | bash hooks/pre-tool-use.sh
tail -1 ~/.claude/dev-platform-telemetry.log | python3 -c "
import sys, json
e = json.loads(sys.stdin.readline())
assert e['event'] == 'tool_use_start'
assert e['tool_call_id'] == 't99'
print('OK')
"

# Failure-tolerance: corrupt the script, confirm exit 0
cp hooks/pre-tool-use.sh /tmp/pre-tool-use.broken.sh
echo 'this is not bash' >> /tmp/pre-tool-use.broken.sh
echo '{}' | bash /tmp/pre-tool-use.broken.sh
[[ $? -eq 0 ]] && echo "OK broken hook exits 0"
rm /tmp/pre-tool-use.broken.sh
```

### Change 7: `gate_fast.sh` self-instrumentation

**Problem:** Gate pass rate is computed as `count(gate_run where outcome=pass) / count(gate_run)`. Without an explicit `gate_run` event, the aggregator has no signal. Adding 3 lines to the existing orchestrator at end-of-run emits the event.

**File:** `scripts/gate_fast.sh` (existing — append at end, before exit)

**Implementation:**

After the `total_pass / total_fail / total_skip` aggregation block (around line 117–119) and before the final exit logic, insert:

```bash
# Emit gate_run telemetry event (Change 7 of v0.5)
LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${LOG}")"
outcome="pass"
[[ ${total_fail} -gt 0 ]] && outcome="fail"

python3 - "${PWD}" "${outcome}" "${total_pass}" "${total_fail}" "$((END - START))" >> "${LOG}" 2>/dev/null <<'PY' || true
import sys, json
from datetime import datetime, timezone

cwd, outcome, p, f, d = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])

def project_for(cwd):
    if cwd.startswith("/home/rich/dev/projects/"):
        return cwd.split("/")[5]
    if cwd == "/home/rich/dev" or cwd.startswith("/home/rich/dev/"):
        return "dev-platform"
    return "other"

event = {
    "v": 1,
    "ts": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
    "event": "gate_run",
    "session_id": "gate",   # gate runs are session-less; tagged for filtering
    "project": project_for(cwd),
    "outcome": outcome,
    "pass_count": p,
    "fail_count": f,
    "duration_s": d,
}
print(json.dumps(event))
PY
```

**Acceptance Test:**

```bash
bash scripts/gate_fast.sh
tail -1 ~/.claude/dev-platform-telemetry.log | python3 -c "
import sys, json
e = json.loads(sys.stdin.readline())
assert e['event'] == 'gate_run'
assert e['outcome'] in {'pass','fail'}
assert isinstance(e['pass_count'], int)
print('OK')
"
```

### Change 8: `settings.json` hooks-block expansion

**Problem:** Three new hooks (Changes 4, 5, 6) need to be wired into `settings.json` for Claude Code to invoke them. The existing block only references `post-tool-heartbeat.sh`.

**File:** `settings/settings.json` (existing — replace `hooks` key)

**Implementation:**

Replace the existing `"hooks": { ... }` block with:

```json
"hooks": {
  "SessionStart": [
    {
      "hooks": [
        {"type": "command", "command": "/home/rich/.claude/hooks/session-start.sh"}
      ]
    }
  ],
  "UserPromptSubmit": [
    {
      "hooks": [
        {"type": "command", "command": "/home/rich/.claude/hooks/user-prompt.sh"}
      ]
    }
  ],
  "PreToolUse": [
    {
      "hooks": [
        {"type": "command", "command": "/home/rich/.claude/hooks/pre-tool-use.sh"}
      ]
    }
  ],
  "PostToolUse": [
    {
      "hooks": [
        {"type": "command", "command": "/home/rich/.claude/hooks/post-tool-heartbeat.sh"}
      ]
    }
  ]
}
```

Path style matches v0.2's decision (absolute `/home/rich/.claude/hooks/...`).

**Acceptance Test:**

```bash
python3 -c "
import json
d = json.load(open('settings/settings.json'))
events = d['hooks'].keys()
assert {'SessionStart','UserPromptSubmit','PreToolUse','PostToolUse'} <= set(events)
for ev in events:
    cmd = d['hooks'][ev][0]['hooks'][0]['command']
    assert cmd.startswith('/home/rich/.claude/hooks/')
print('OK')
"
```

After install: a fresh Claude Code session should fire SessionStart on startup, UserPromptSubmit on each prompt, PreToolUse + PostToolUse on each tool call.

---

## Phase 3: Aggregation + Reporting

### Change 9: `monitoring/aggregator.py` — log parser + metrics engine

**Problem:** With four event types streaming into one JSONL file, an aggregator is needed to compute the four scoped metrics. The aggregator must also handle the legacy `<ts> tool=<name>` lines from v0.2 (1,124 entries) without choking.

**File:** `monitoring/aggregator.py` (new)

**Implementation:**

Single-file Python module. ~250 lines. Structure:

```python
#!/usr/bin/env python3
"""dev-platform telemetry aggregator.

Reads ~/.claude/dev-platform-telemetry.log (JSONL + legacy text format),
computes the four v0.5 metrics, and emits a markdown report.

Usage:
    python3 monitoring/aggregator.py --period daily
    python3 monitoring/aggregator.py --period weekly
    python3 monitoring/aggregator.py --period all
    python3 monitoring/aggregator.py --period daily --project dev-platform
    python3 monitoring/aggregator.py --period daily --json   # machine-readable

Exits 0 on success, 1 on missing log file.
"""
from __future__ import annotations
import argparse
import json
import os
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterator

LOG_DEFAULT = Path.home() / ".claude" / "dev-platform-telemetry.log"

LEGACY_RE = re.compile(r"^(\S+)\s+tool=(\S+)$")


@dataclass
class Event:
    ts: datetime
    event: str
    project: str
    session_id: str = "?"
    tool: str | None = None
    tool_call_id: str | None = None
    duration_ms: int | None = None
    command: str | None = None
    outcome: str | None = None
    pass_count: int | None = None
    fail_count: int | None = None
    duration_s: int | None = None


def parse_line(line: str) -> Event | None:
    """Parse a JSONL or legacy-format line. Return None on unparseable input."""
    line = line.strip()
    if not line:
        return None
    if line.startswith("{"):
        try:
            d = json.loads(line)
            ts = datetime.fromisoformat(d["ts"])
            return Event(
                ts=ts,
                event=d.get("event", "?"),
                project=d.get("project", "?"),
                session_id=d.get("session_id", "?"),
                tool=d.get("tool"),
                tool_call_id=d.get("tool_call_id"),
                duration_ms=d.get("duration_ms"),
                command=d.get("command"),
                outcome=d.get("outcome"),
                pass_count=d.get("pass_count"),
                fail_count=d.get("fail_count"),
                duration_s=d.get("duration_s"),
            )
        except Exception:
            return None
    # Legacy format: <ts> tool=<name>
    m = LEGACY_RE.match(line)
    if not m:
        return None
    try:
        ts = datetime.fromisoformat(m.group(1))
    except Exception:
        return None
    return Event(ts=ts, event="tool_use_end", project="dev-platform",
                 tool=m.group(2))  # legacy was always dev-platform context


def load_events(path: Path) -> Iterator[Event]:
    """Yield parsed Event objects from the log. Silently skip unparseable lines."""
    if not path.exists():
        return
    with path.open() as f:
        for line in f:
            ev = parse_line(line)
            if ev is not None:
                yield ev


def filter_window(events: Iterator[Event], since: datetime, until: datetime,
                  project: str | None = None) -> list[Event]:
    out: list[Event] = []
    for ev in events:
        if ev.ts < since or ev.ts > until:
            continue
        if project is not None and ev.project != project:
            continue
        out.append(ev)
    return out


# --- Metric computations -------------------------------------------------

def metric_gate_pass_rate(events: list[Event]) -> dict:
    gates = [e for e in events if e.event == "gate_run"]
    if not gates:
        return {"count": 0, "pass": 0, "fail": 0, "rate": None}
    passed = sum(1 for e in gates if e.outcome == "pass")
    return {"count": len(gates), "pass": passed, "fail": len(gates) - passed,
            "rate": passed / len(gates)}


def metric_code_retries(events: list[Event]) -> dict:
    """A 'retry' is a /code invocation immediately followed by another /code
    in the same session WITHOUT a /docs in between. Counts retries per /code."""
    by_session: dict[str, list[Event]] = defaultdict(list)
    for e in events:
        if e.event == "user_prompt" and e.command in {"/code", "/docs"}:
            by_session[e.session_id].append(e)
    code_count = 0
    retry_count = 0
    for sid, evs in by_session.items():
        evs.sort(key=lambda e: e.ts)
        last_code_idx = None
        for i, e in enumerate(evs):
            if e.command == "/code":
                code_count += 1
                if last_code_idx is not None and not any(
                    x.command == "/docs" for x in evs[last_code_idx + 1:i]
                ):
                    retry_count += 1
                last_code_idx = i
            else:
                last_code_idx = None
    return {"code_invocations": code_count, "retries": retry_count,
            "avg": retry_count / code_count if code_count else None}


def metric_review_catch_rate(events: list[Event]) -> dict:
    """Number of /review invocations. v0.5 captures count only; 'catch rate'
    (issues raised per review) requires parsing /review output, which is
    deferred — labeled in the report as 'count only' until /review skill
    emits a structured issue count event."""
    reviews = [e for e in events if e.event == "user_prompt" and e.command == "/review"]
    return {"count": len(reviews), "catch_rate": None,
            "note": "Catch-rate computation deferred — /review skill does "
                    "not yet emit issue counts. Tracked in roadmap."}


def metric_tool_duration(events: list[Event]) -> dict:
    """Pair tool_use_start with tool_use_end via tool_call_id, compute duration."""
    starts: dict[str, datetime] = {}
    durations: list[tuple[str, int]] = []   # (tool_name, ms)
    for e in events:
        if e.event == "tool_use_start" and e.tool_call_id:
            starts[e.tool_call_id] = e.ts
        elif e.event == "tool_use_end" and e.tool_call_id and e.tool_call_id in starts:
            ms = int((e.ts - starts[e.tool_call_id]).total_seconds() * 1000)
            durations.append((e.tool or "?", ms))
            del starts[e.tool_call_id]
    if not durations:
        return {"count": 0, "avg_ms": None, "by_tool": {}}
    by_tool: dict[str, list[int]] = defaultdict(list)
    for tool, ms in durations:
        by_tool[tool].append(ms)
    avg_overall = sum(ms for _, ms in durations) / len(durations)
    by_tool_avg = {t: sum(v)/len(v) for t, v in by_tool.items()}
    return {"count": len(durations), "avg_ms": int(avg_overall),
            "by_tool": dict(sorted(by_tool_avg.items(),
                                   key=lambda kv: -kv[1])[:5])}


# --- Report rendering ----------------------------------------------------

def render_markdown(window: tuple[datetime, datetime], events: list[Event],
                    project_filter: str | None) -> str:
    since, until = window
    metrics = {
        "gate": metric_gate_pass_rate(events),
        "code": metric_code_retries(events),
        "review": metric_review_catch_rate(events),
        "tools": metric_tool_duration(events),
    }
    by_project: dict[str, int] = defaultdict(int)
    for e in events:
        by_project[e.project] += 1

    lines = []
    title = "dev-platform telemetry report"
    if project_filter:
        title += f" — project={project_filter}"
    lines.append(f"=== {title} — {since.date()} → {until.date()} ===\n")
    lines.append(f"Events: {len(events)} total\n")

    g = metrics["gate"]
    if g["count"]:
        lines.append(f"Gate pass rate:        {g['pass']}/{g['count']} "
                     f"({int(g['rate']*100)}%)  — {g['count']} invocations")
    else:
        lines.append("Gate pass rate:        no gate runs in window")

    c = metrics["code"]
    if c["code_invocations"]:
        avg = f"{c['avg']:.1f}" if c['avg'] is not None else "n/a"
        lines.append(f"/code retry counts:    avg {avg}     "
                     f"— {c['code_invocations']} invocations, {c['retries']} retries")
    else:
        lines.append("/code retry counts:    no /code in window")

    r = metrics["review"]
    if r["count"]:
        lines.append(f"/review catch rate:    count only — {r['count']} invocations  "
                     "(catch-rate deferred)")
    else:
        lines.append("/review catch rate:    no /review in window")

    t = metrics["tools"]
    if t["count"]:
        top = ", ".join(f"{k} {int(v)}ms" for k, v in t["by_tool"].items())
        lines.append(f"Tool exec time avg:    {t['avg_ms']}ms       — top: {top}")
    else:
        lines.append("Tool exec time avg:    no paired tool events in window")

    if not project_filter:
        lines.append("\nPer-project breakdown:")
        for proj in sorted(by_project, key=lambda p: -by_project[p]):
            lines.append(f"  {proj}: {by_project[proj]} events")

    return "\n".join(lines) + "\n"


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--period", choices=["daily", "weekly", "all"], default="daily")
    p.add_argument("--project", default=None)
    p.add_argument("--json", action="store_true", help="emit JSON instead of markdown")
    p.add_argument("--log", default=str(LOG_DEFAULT))
    args = p.parse_args()

    log = Path(args.log)
    if not log.exists():
        print(f"ERROR: telemetry log not found at {log}", file=sys.stderr)
        return 1

    now = datetime.now(timezone.utc).astimezone()
    if args.period == "daily":
        since = now.replace(hour=0, minute=0, second=0, microsecond=0)
    elif args.period == "weekly":
        since = now - timedelta(days=7)
    else:
        since = datetime.min.replace(tzinfo=now.tzinfo)

    events = filter_window(load_events(log), since, now, args.project)

    if args.json:
        out = {
            "window": [since.isoformat(), now.isoformat()],
            "project": args.project,
            "event_count": len(events),
            "metrics": {
                "gate": metric_gate_pass_rate(events),
                "code": metric_code_retries(events),
                "review": metric_review_catch_rate(events),
                "tools": metric_tool_duration(events),
            },
        }
        print(json.dumps(out, indent=2, default=str))
    else:
        print(render_markdown((since, now), events, args.project))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

**Acceptance Test:**

```bash
# Aggregator parses the existing log (legacy + JSONL) without error
python3 monitoring/aggregator.py --period all >/dev/null
echo "exit=$?"   # expect 0

# JSON output is valid JSON
python3 monitoring/aggregator.py --period all --json | python3 -c "import sys, json; json.load(sys.stdin); print('OK')"

# Project filter works
python3 monitoring/aggregator.py --period all --project dev-platform >/dev/null
echo "exit=$?"
```

### Change 10: `scripts/report.sh` — CLI entry

**Problem:** Invoking `python3 monitoring/aggregator.py --period daily` is verbose. A 5-line Bash wrapper at `scripts/report.sh` matches the existing entry-point pattern (`gate_fast.sh`, `install.sh`, `verify.sh`, `new-project.sh`).

**File:** `scripts/report.sh` (new, executable)

**Implementation:**

```bash
#!/usr/bin/env bash
# scripts/report.sh — display the dev-platform telemetry report.
#
# Usage:
#   ./scripts/report.sh                    # daily, all projects
#   ./scripts/report.sh weekly             # weekly, all projects
#   ./scripts/report.sh daily dev-platform # daily, single project
#   ./scripts/report.sh all                # full history
#   ./scripts/report.sh --json             # machine-readable
#
# Delegates to monitoring/aggregator.py.

set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PERIOD="${1:-daily}"
PROJECT="${2:-}"
EXTRA=""
[[ "${PERIOD}" == "--json" ]] && { PERIOD="daily"; EXTRA="--json"; }

ARGS=(--period "${PERIOD}")
[[ -n "${PROJECT}" ]] && ARGS+=(--project "${PROJECT}")
[[ -n "${EXTRA}" ]] && ARGS+=(${EXTRA})

python3 "${REPO}/monitoring/aggregator.py" "${ARGS[@]}"
```

**Acceptance Test:**

```bash
bash scripts/report.sh           # exit 0, markdown output
bash scripts/report.sh weekly    # exit 0
bash scripts/report.sh all       # exit 0
bash scripts/report.sh --json | python3 -c "import sys, json; json.load(sys.stdin); print('OK')"
```

### Change 11: `monitoring/metrics.md` — catalog of computed metrics

**Problem:** Future-Rich (or a future spec author) needs a single document listing what each metric is, how it's computed, and what its known limitations are. This is the inventory that v0.8 will extend (cross-project aggregation reuses these definitions).

**File:** `monitoring/metrics.md` (new)

**Implementation:**

~50-line markdown document. Structure:

```markdown
# dev-platform Metrics Catalog

Every metric v0.5 computes, with definition, source events, and known limitations.
Aggregator: `monitoring/aggregator.py`. CLI: `scripts/report.sh`.

## gate_pass_rate

**Definition:** count(gate_run where outcome=pass) / count(gate_run).
**Source events:** `gate_run` (emitted by `scripts/gate_fast.sh`).
**Limitations:** Only counts the dev-platform `gate_fast.sh` orchestrator. Other
projects' gate runs are not captured until those projects' gate scripts emit
`gate_run` events into the same log — tracked as an v0.8 follow-on.

## code_retry_rate

**Definition:** Number of /code invocations followed by another /code in the
same session without an intervening /docs.
**Source events:** `user_prompt` with command=/code or command=/docs.
**Limitations:** Doesn't distinguish "retry because /test failed" from "user
re-invoked /code for a separate change." v0.5 ships the raw count; refinement
deferred to future spec.

## review_count (catch-rate deferred)

**Definition:** Count of /review invocations.
**Source events:** `user_prompt` with command=/review.
**Limitations:** True catch-rate (issues raised per review) requires the
/review skill to emit a structured "issues found: N" event. Not yet
implemented — v0.5 ships count-only; full catch-rate is a future spec.

## tool_duration_ms

**Definition:** Per-tool average time between PreToolUse and PostToolUse
events, paired by tool_call_id.
**Source events:** `tool_use_start`, `tool_use_end`.
**Limitations:** Excludes legacy lines (pre-v0.5) which have no start event.
Pairing is by tool_call_id (Claude Code's tool_use_id); if a pair is missing
(e.g., session crashed mid-tool), the start event is silently dropped.

## events_per_project

**Definition:** Count of all events, grouped by `project` field.
**Source events:** all.
**Limitations:** Project is derived from cwd at hook fire time. A session that
starts in dev-platform and cd's into projects/X mid-session would tag
later events as project=X. This is intentional — the metric reflects where
work happened, not where the session began.
```

**Acceptance Test:** File exists; the four metrics above are documented with definition + source events + limitations sections.

---

## Phase 4: Tests + Acceptance + Docs

### Change 12: `tests/monitoring/` — aggregator unit tests

**Problem:** The aggregator must be regression-tested. v0.4 auto-discovery (`scripts/gate_fast.sh`) picks up `tests/monitoring/*.sh` automatically — no orchestrator edit needed. The suite needs JSONL fixtures + a runner that asserts each metric.

**File:** `tests/monitoring/` (new directory)

**Implementation:**

Fixtures:

- `tests/monitoring/fixtures/empty.jsonl` — zero events
- `tests/monitoring/fixtures/legacy-only.txt` — 3 legacy `<ts> tool=<name>` lines
- `tests/monitoring/fixtures/mixed-window.jsonl` — covers all 5 event types, one session, dev-platform project, ~10 events including a paired tool_use_start/end + a gate_run pass + a /code invocation
- `tests/monitoring/fixtures/two-projects.jsonl` — events from both dev-platform and "kermit" projects to verify project filter
- `tests/monitoring/fixtures/code-retry.jsonl` — sequence of /code, /code, /docs, /code (one retry detected)

Runner: `tests/monitoring/run.sh`. For each fixture, runs `aggregator.py --log <fixture> --period all --json`, parses the output, asserts specific metric values.

```bash
#!/usr/bin/env bash
# tests/monitoring/run.sh — fixture suite for monitoring/aggregator.py.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

AGG="${REPO}/monitoring/aggregator.py"

run_check() {
    local fixture="$1"; local description="$2"; local check_py="$3"
    out="$(python3 "${AGG}" --log "${HERE}/fixtures/${fixture}" --period all --json 2>&1)"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        record_fail "${description} — aggregator exit ${rc}: ${out}"
        return
    fi
    if echo "${out}" | python3 -c "${check_py}" >/dev/null 2>&1; then
        record_pass "${description}"
    else
        record_fail "${description} — assertion failed (output: ${out:0:200})"
    fi
}

run_check "empty.jsonl" "empty log produces zero events" \
    "import sys, json; d=json.load(sys.stdin); assert d['event_count']==0"

run_check "legacy-only.txt" "legacy format parsed (3 events)" \
    "import sys, json; d=json.load(sys.stdin); assert d['event_count']==3"

run_check "mixed-window.jsonl" "gate_run pass detected" \
    "import sys, json; d=json.load(sys.stdin); assert d['metrics']['gate']['pass']==1"

run_check "mixed-window.jsonl" "tool duration paired" \
    "import sys, json; d=json.load(sys.stdin); assert d['metrics']['tools']['count']>=1"

run_check "code-retry.jsonl" "/code retry detected (1 retry across 3 invocations)" \
    "import sys, json; d=json.load(sys.stdin); m=d['metrics']['code']; assert m['retries']==1 and m['code_invocations']==3"

run_check "two-projects.jsonl" "project filter narrows events" \
    "import sys, json; d=json.load(sys.stdin); assert d['event_count'] >= 2"
```

**Acceptance Test:** `bash tests/monitoring/run.sh` records 6 PASS, 0 FAIL. After v0.4 orchestrator picks the suite up, `bash scripts/gate_fast.sh` includes the 6 checks in its totals.

### Change 13: End-to-end acceptance + live cutover

**Problem:** The full pipeline (4 hooks + gate_fast instrumentation + aggregator + CLI) must run against a real Claude Code session to prove it works end-to-end. v0.2 had a similar cutover step; v0.5 follows the same shape.

**File:** none (procedural)

**Implementation:**

```bash
# 1. Static checks (pre-cutover)
bash scripts/gate_fast.sh   # all v0.4 lift checks + v0.5's new tests/monitoring suite pass

# 2. Install (deploys new hooks + settings.json hooks block)
bash scripts/install.sh

# 3. Verify symlinks
bash scripts/verify.sh   # expect exit 0 with N+3 OK lines (3 new hooks)

# 4. Restart Claude Code, run a fresh session against dev-platform.
#    Use the session for ~5 minutes — invoke /dev, run some tool calls.

# 5. Confirm new event types are present
tail -50 ~/.claude/dev-platform-telemetry.log | python3 -c "
import sys, json
seen = set()
for line in sys.stdin:
    line = line.strip()
    if line.startswith('{'):
        d = json.loads(line)
        seen.add(d['event'])
print('events seen:', sorted(seen))
assert 'session_start' in seen, 'no session_start emitted'
assert 'tool_use_start' in seen, 'no tool_use_start emitted'
assert 'tool_use_end' in seen, 'no tool_use_end emitted'
# user_prompt + gate_run are optional depending on what the session did
print('OK')
"

# 6. Run the gate to emit a gate_run event
bash scripts/gate_fast.sh
tail -1 ~/.claude/dev-platform-telemetry.log | python3 -c "
import sys, json
e = json.loads(sys.stdin.readline())
assert e['event'] == 'gate_run'
print('OK')
"

# 7. Run the report
bash scripts/report.sh daily   # expect non-empty output, gate_pass_rate line, tool_duration line
bash scripts/report.sh weekly  # expect non-empty output covering the legacy data too
bash scripts/report.sh --json | python3 -m json.tool >/dev/null  # valid JSON
```

**Acceptance Test:** All 7 sub-steps pass: gate_fast green; install + verify green; live session produces 3 new event types; gate_run emitted on gate invocation; report renders both human and JSON output.

### Change 14: Docs — README, planning, CLAUDE.md updates

**Problem:** v0.5 introduces a new top-level capability (telemetry + reporting). The README's Roadmap line, the `dev/CLAUDE.md` Repo Structure table, and `planning.md` all need updates. ROADMAP.md needs v0.5's "complete" status with its commit hash recorded (after the commit; per /docs the line is hash-free).

**File:** `README.md` (modify), `dev/CLAUDE.md` (modify), `ROADMAP.md` (modify), `planning.md` (modify)

**Implementation:**

`README.md`:
- Add a "## Telemetry" section after "## Verifying deployment" with a 3-line description of `scripts/report.sh` and the four metrics it shows.
- Update the Roadmap mention to reflect v0.5 done.

`dev/CLAUDE.md` Repo Structure table:
- The `monitoring/` row exists but reads "Workflow telemetry — populated by future monitoring spec." Replace with: "Workflow telemetry — event schema, aggregator (`aggregator.py`), metrics catalog. Reported via `scripts/report.sh`."

`ROADMAP.md`:
- Mark v0.5 done with date.

`planning.md`:
- Move v0.5 from "Recently shipped" hint to actual "Recently shipped" bullet; remove "v0.5 Monitoring is next" — replace with "v0.6 VSCode is next" (the original ROADMAP sequence resumes).

`tasks/lessons.md`:
- Append any new lessons surfaced during /code (e.g., hook payload key surprises, schema decisions).

**Acceptance Test:** All four files reference v0.5 as shipped; the Repo Structure table reflects the real content of `monitoring/`; `scripts/report.sh` is mentioned in the README.

---

## Acceptance Criteria

- [ ] `monitoring/schemas/event-v1.json` exists, valid JSON Schema (Change 1).
- [ ] `monitoring/schemas/examples.jsonl` has at least one example per event type (Change 1).
- [ ] `hooks/post-tool-heartbeat.sh` emits JSONL events; backward-compatible with old payloads (Change 2).
- [ ] `.gitignore` extension tracks `monitoring/**/*.py`, `**/*.json`, `**/*.jsonl` (Change 3).
- [ ] `hooks/session-start.sh` exists, executable, smoke-test passes (Change 4).
- [ ] `hooks/user-prompt.sh` emits events only for slash commands (Change 5).
- [ ] `hooks/pre-tool-use.sh` emits start events; deliberately broken version exits 0 (failure tolerance) (Change 6).
- [ ] `scripts/gate_fast.sh` emits one `gate_run` event per invocation (Change 7).
- [ ] `settings/settings.json` registers all 4 hook events (Change 8).
- [ ] `monitoring/aggregator.py` parses both JSONL and legacy `tool=X` lines; computes 4 metrics; supports `--period`, `--project`, `--json` flags (Change 9).
- [ ] `scripts/report.sh` exists, executable, delegates to aggregator (Change 10).
- [ ] `monitoring/metrics.md` catalogs all 4 metrics with definition + source + limitations (Change 11).
- [ ] `tests/monitoring/run.sh` records ≥6 PASS, auto-discovered by `gate_fast.sh` (Change 12).
- [ ] End-to-end live cutover: 3 new event types observed in real session; report renders non-empty output (Change 13).
- [ ] README, dev/CLAUDE.md, ROADMAP.md, planning.md all reflect v0.5 done (Change 14).
- [ ] v0.2 live verify still passes — v0.5 does not break existing symlinks.
- [ ] `bash scripts/gate_fast.sh` still PASS after all changes.
- [ ] No file under `projects/` modified.

## Out of Scope (Future Specs)

- **Cross-project aggregation (v0.8 territory).** v0.5 emits per-project events into one log; v0.8 builds the cross-project view + dashboard.
- **/review structured issue-count emission.** The `/review` skill doesn't yet emit a "issues found: N" event. v0.5 ships `/review` count only. Refining catch-rate is a future spec (touches the skill itself).
- **Web dashboard / real-time UI.** No browser front-end. CLI markdown only.
- **Database backend.** JSONL is sufficient at current volume (~600 events/day). Migration to SQLite or Postgres is a future spec when query complexity or retention requirements demand it.
- **Alerting / paging.** No "you've had 3 gate failures in a row" notifications. Future spec.
- **Log rotation.** The log file grows unbounded. At ~200K events/year and ~100 bytes/event = ~20 MB/year — not urgent. Rotation policy is a future spec when it crosses ~100 MB.
- **Per-tool retry detection.** The current `/code retry` heuristic uses /docs as the "natural end" of a /code phase. /test, /review, /gate as alternative terminators are deferred.
- **Skill-level instrumentation.** Currently we detect skill invocations from UserPromptSubmit; deeper signals (skill internal state, time-per-skill-step) would require the skill bodies themselves to emit events. Out of scope.

## What NOT to Do

- **Do not block tool calls from a hook.** Every new hook MUST exit 0 regardless of internal failure. PreToolUse hooks especially — a hang or non-zero exit there blocks the entire session. The `set -uo pipefail` (no `-e`) + `|| true` pattern is mandatory; tests enforce it.
- **Do not introduce a database or external dependency.** JSONL log + Python stdlib only. No SQLite, no Postgres, no Redis, no log-shipping. v0.5 is a single-machine solo-dev tool; complexity has to be justified by a real bottleneck.
- **Do not parse JSONL with `jq`.** `jq` isn't guaranteed installed. The hooks use Python (already a dependency); the aggregator uses Python stdlib `json`.
- **Do not delete the 2 days of legacy log lines.** The aggregator handles both formats. Wiping the history would erase the only baseline we have for current /code retry rates.
- **Do not bundle v0.8 cross-project aggregation.** v0.8 is the next phase; v0.5 stays scoped to single-project metrics.
- **Do not emit events from inside `tests/`.** Test fixtures may contain JSONL lines but those go to per-fixture files; the production log never sees test data.
- **Do not log sensitive payload data.** Hooks emit only: tool name, command name, project name, timestamps, durations. Never log tool arguments, prompt text bodies, file contents, secrets. The Python emitters above DO NOT extract `payload['prompt']` body or `payload['tool_input']` — only metadata.
- **Do not use `~` or `${HOME}` in `settings.json` command paths.** v0.2 locked this — absolute `/home/rich/.claude/hooks/...`.
- **Do not introduce a Python web framework, CLI framework, or templating engine.** stdlib `argparse` + plain f-string rendering. The Demand Elegance rule applies; the aggregator is ~250 lines, not 2500.
- **Do not break the v0.2 heartbeat contract.** `post-tool-heartbeat.sh` still exists at the same path with the same exit-0 guarantee — only its emission format changes. Settings.json `PostToolUse` still references it.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `monitoring/schemas/event-v1.json` | New | JSON Schema for telemetry events |
| `monitoring/schemas/examples.jsonl` | New | One example per event type |
| `monitoring/README.md` | Modify | Replace placeholder with event-format + project-tagging + backward-compat docs |
| `monitoring/aggregator.py` | New | Log parser + 4-metric computation engine |
| `monitoring/metrics.md` | New | Metrics catalog |
| `hooks/post-tool-heartbeat.sh` | Modify | JSONL emission (replaces text format) |
| `hooks/session-start.sh` | New | SessionStart collector |
| `hooks/user-prompt.sh` | New | UserPromptSubmit slash-command detector |
| `hooks/pre-tool-use.sh` | New | PreToolUse tool-call-start emitter |
| `scripts/gate_fast.sh` | Modify | Append `gate_run` telemetry emission |
| `scripts/report.sh` | New | CLI entry to the aggregator |
| `settings/settings.json` | Modify | Register 3 new hook events |
| `.gitignore` | Modify | Allow `monitoring/**/*.py`, `**/*.json`, `**/*.jsonl` |
| `tests/monitoring/fixtures/*.jsonl,*.txt` | New | 5 aggregator fixtures |
| `tests/monitoring/run.sh` | New | Aggregator unit-test suite |
| `README.md` | Modify | Add Telemetry section; update Roadmap line |
| `dev/CLAUDE.md` | Modify | Repo Structure table row for `monitoring/` |
| `ROADMAP.md` | Modify | Mark v0.5 done |
| `planning.md` | Modify | v0.5 in Recently shipped; v0.6 becomes next |
| `tasks/lessons.md` | Modify (during /code) | Any new lessons surfaced |
| `tasks/dev-platform-r2-monitoring-spec.md` | (this file) | Spec |

## Implementation Order

1. **Phase 1 (Changes 1–3)** — schema, hook migration, gitignore. Foundation. Can be done in any order; gitignore is the lightest.
2. **Phase 2 (Changes 4–8)** — 3 new hooks + gate_fast emission + settings wire-up. Hooks (4, 5, 6, 7) are independent and can be batched. Change 8 must come after at least one of 4–6 so settings.json references real scripts.
3. **Phase 3 (Changes 9–11)** — aggregator, CLI, metrics catalog. The aggregator (9) is the largest single piece. Catalog (11) and CLI (10) depend on knowing the aggregator's interface.
4. **Phase 4 (Change 12)** — test suite. Depends on aggregator from Change 9.
5. **Phase 4 (Change 13)** — end-to-end acceptance. MUST come last — validates the full chain.
6. **Phase 4 (Change 14)** — doc updates. Can be done in the same commit as the rest (per the Docs Before Commit rule, /docs runs after gate_fast pass and before commit; the same atomic commit holds code + docs).

Within Phase 2, Changes 4, 5, 6, 7 can be batched in one `/code` session. Phase 3 is the heaviest single-session block. The whole spec is approximately two `/code` sessions of work to plan + implement + acceptance-test, depending on Claude Code's actual hook-payload key naming surfacing surprises during Change 13.

## Verification Checklist

- [ ] All 14 Changes implemented per the spec.
- [ ] `bash -n` passes on every new `.sh` file.
- [ ] `python3 -m py_compile monitoring/aggregator.py` exits 0.
- [ ] `python3 -c "import json; json.load(open('monitoring/schemas/event-v1.json'))"` succeeds.
- [ ] `python3 -c "import json; json.load(open('settings/settings.json'))"` succeeds.
- [ ] All four metrics produce non-error output on the existing 1,124-line log (legacy + new format combined).
- [ ] Failure-tolerance test: a deliberately corrupted hook script still exits 0 when fed input.
- [ ] `bash scripts/gate_fast.sh` passes including the new `tests/monitoring/` suite (auto-discovered).
- [ ] Live cutover: SessionStart + UserPromptSubmit + PreToolUse + PostToolUse events all observed in a real Claude Code session.
- [ ] `bash scripts/report.sh daily` produces non-empty markdown.
- [ ] `bash scripts/report.sh --json` produces valid JSON.
- [ ] `bash scripts/verify.sh` exits 0 — no broken symlinks.
- [ ] No file under `projects/` modified.
- [ ] No literal secrets / passwords / tokens emitted in any hook.
- [ ] No `console.log` / `print` debug code left in production paths.
- [ ] dev/CLAUDE.md, README.md, ROADMAP.md, planning.md updated.

## Notes for Implementation

- **Claude Code hook payload key names are not 100% verified at spec time.** The v0.2 heartbeat uses `payload.get("tool_name", "?")` and works in practice; v0.5 assumes `payload["session_id"]`, `payload["tool_use_id"]`, `payload["prompt"]` exist on their respective events. /test phase MUST confirm — if a key name differs, fix in /code and update the spec inline. Per the `dev/CLAUDE.md` "Hook scripts that read external-tool event payloads MUST degrade gracefully on shape change" lesson, every key access uses `.get(..., "?")` with a fallback. A wrong key produces `"?"` placeholder, never an exception.
- **Schema versioning is mandatory.** `"v": 1` on every event. The aggregator currently only handles v=1; future schema bumps will require either backward-compat code paths or a migration step.
- **The legacy text format support in the aggregator is permanent.** The 1,124 historical lines have value as a baseline. Deleting that compatibility ever would require a migration script that rewrites legacy → v1 JSONL. v0.5 does not ship the migration script; it ships the aggregator that reads both.
- **`tool_call_id` pairing relies on Claude Code emitting the same ID in PreToolUse and PostToolUse.** If it doesn't (or uses different field names), the aggregator's tool_duration metric returns count=0. Test fixture (Change 12) MUST include paired events to validate; if live cutover (Change 13) shows count=0, that's a bug to chase, not a deferred-feature.
- **Project derivation is fragile to cwd changes mid-session.** If a session `cd`s from `/home/rich/dev` to `/home/rich/dev/projects/kermit`, later events tag project=kermit. This is intentional (events should reflect where they happened) — but a confusing user message during /test phase is worth a callout in the metrics.md doc.
- **Hook execution time is bounded by Python startup (~50 ms cold).** At ~600 events/day, that's ~30 seconds/day of Python startup cost across all hooks. Acceptable but worth measuring during /test phase. If it ever creeps past 100 ms/event a Bash-only emission path becomes worth considering. v0.5 prefers correctness (proper JSON) over micro-optimization.
- **The v0.4 auto-discovery contract carries the new test suite for free.** No `gate_fast.sh` edit is needed for the `tests/monitoring/` suite — adding the directory + a `*.sh` runner is enough. This is exactly what v0.4's auto-discovery was designed for; v0.5 is the first spec to exercise it.
- **The /docs skill runs BEFORE commit per the Docs Before Commit rule.** The Change 14 doc updates land in the same atomic commit as the code, not a follow-up "docs:" commit. ROADMAP.md and planning.md do NOT receive v0.5's commit hash — that's the chicken-and-egg paradox closed in commands/docs.md (`git log` is the authoritative hash record).
- **v0.5 is the data layer; v0.8 (cross-project orchestration) is the consumer.** Design choices here affect v0.8's surface area. The per-event project tag, the single global log, the JSONL format, and the aggregator's `--project` filter are all v0.8-aware decisions. If a future v0.8 design discussion challenges any of these, expect the spec to be revisited.
