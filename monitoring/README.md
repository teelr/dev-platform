# monitoring/

Workflow-effectiveness telemetry for dev-platform. Collects events from hook scripts + `scripts/gate_fast.sh`, aggregates them into per-project metrics, reports via `scripts/report.sh`.

## What goes here

- `schemas/event-v1.json` — JSON Schema for the telemetry event format
- `schemas/examples.jsonl` — one example event per event type

Phase 3 of v0.5 will add the aggregator (`aggregator.py`) and metrics catalog (`metrics.md`); both arrive with their own doc updates.

## What does NOT go here

- Hook implementations — those live in `hooks/` (they emit events to the log)
- The CLI entry point — that's `scripts/report.sh` (Bash wrapper delegating to `aggregator.py`)
- The log file itself — `~/.claude/dev-platform-telemetry.log`, machine-local, gitignored (anywhere under `~/.claude/` is excluded by dev/.gitignore)
- Per-project metrics — each project tracks its own; this directory aggregates across them via the `project` event field

## Event format

Each line in `~/.claude/dev-platform-telemetry.log` is one JSON object matching `schemas/event-v1.json`. Five event types:

| Event | Emitted by | Purpose |
| ----- | ---------- | ------- |
| `session_start` | `hooks/session-start.sh` | Records session + project context once per Claude Code session |
| `user_prompt` | `hooks/user-prompt.sh` | Records slash-command invocations (free-text prompts not captured) |
| `tool_use_start` | `hooks/pre-tool-use.sh` | Pairs with `tool_use_end` via `tool_call_id` to compute duration |
| `tool_use_end` | `hooks/post-tool-heartbeat.sh` | Closes a tool-call pair |
| `gate_run` | `scripts/gate_fast.sh` (self-instrumented) | One per gate invocation, with pass/fail counts and duration |

## Project tagging

The `project` field on every event derives from `cwd` at hook fire time:

- `cwd == /home/rich/dev` or `cwd` startswith `/home/rich/dev/` → `project = "dev-platform"`
- `cwd` startswith `/home/rich/dev/projects/<name>/` → `project = "<name>"`
- otherwise → `project = "other"`

A session that `cd`s mid-flight tags later events at the new project — events reflect where they fired, not where the session started.

## Fallback asymmetry — deliberate, not a bug

Each of the four hook scripts (`hooks/*.sh`) delegates JSON shaping to `hooks/_emit_event.py`. When the emitter fails (Python interpreter missing, malformed payload that crashes inside the emitter, etc.), each bash wrapper decides whether to emit a degraded JSONL line as a fallback. The decision differs by event type:

| Hook | On emitter failure | Why |
| ---- | ------------------ | --- |
| `session-start.sh` | Emits `{event:"session_start", session_id:"?", …}` | Marker for every session, even with an unreadable payload. Aggregator can still count sessions. |
| `post-tool-heartbeat.sh` | Emits `{event:"tool_use_end", tool:"?", tool_call_id:"?", …}` | Maintains v0.2's "always emit, never miss a tool call" contract. The tool call happened; record its existence. |
| `user-prompt.sh` | Silent (no fallback line) | We can't tell if an unparsed prompt was a slash command or free text. A degraded `user_prompt` would leak the existence of a free-text user message — violates the privacy-by-omission design. |
| `pre-tool-use.sh` | Silent (no fallback line) | A fallback start with `tool_call_id="?"` would never pair with a real `tool_use_end`, producing two unrelated orphan rows. Silent failure leaves only the end orphaned — cleaner for the aggregator's pairing logic. |

The two strategies are intentional. Don't align them without re-validating the rationale above.

## Backward compatibility

The legacy format from v0.2 — lines shaped `<ISO-timestamp> tool=<name>` — predates this schema. The aggregator reads both formats; legacy lines are interpreted as `tool_use_end` events with `project="dev-platform"` (legacy was always dev-platform context). Historical lines from v0.2's text format remain queryable indefinitely.

## Deployment

The hook scripts deploy via `scripts/install.sh` (the standard symlink mechanism from v0.1). The aggregator runs in-place — no symlinking needed. The CLI entry `scripts/report.sh` is on the standard scripts path.
