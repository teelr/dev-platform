# monitoring/

Workflow-effectiveness telemetry for dev-platform. Collects events from hook scripts + `scripts/gate_fast.sh`, aggregates them into per-project metrics, reports via `scripts/report.sh`. Also holds `projects.json`, the fleet registry every `fleet-*` script reads.

## projects.json — the fleet registry

One JSON array; one object per project. Six scripts read it, so a change here changes fleet-wide behaviour. `scripts/check-registry.sh` validates it and runs in `gate_fast.sh`.

| Field | Type | Required | Read by |
| ----- | ---- | -------- | ------- |
| `name` | string | yes | all six — the registry key, matching the directory under `projects/` and the `--project` argument every consumer but `check-registry.sh` accepts |
| `path` | string | yes | all six — `projects/<name>`, or absolute |
| `gate_cmd` | string | yes | `fleet-gate.sh` runs it; `check-registry.sh` checks the script exists |
| `primary_language` | string | yes | **nothing reads it.** Required only so entries stay uniform — `check-registry.sh` is the sole consumer, and only to assert its presence. Drop the requirement rather than inventing a use if one is ever wanted. |
| `enabled` | boolean | yes | all six — `false` removes the project from every fleet operation |
| `frozen` | boolean | no (default `false`) | all but `fleet-gate.sh` — deployed but not developed; see below |
| `notes` | string | no | humans only; no script parses it |

**Relative paths resolve against the main checkout, not the invoking worktree.** `projects/` is gitignored, so it exists nowhere else — every consumer resolves it through `scripts/lib/main_checkout.sh`.

**A missing `enabled` is a validation error, not a default.** Every consumer reads it as false-if-absent, so a typo'd or omitted key silently drops the project from the entire fleet. `check-registry.sh` rejects it rather than letting that pass quietly.

### `frozen` — deployed, but not developed

For a project still running in production that nobody will develop further (kermit-pa, superseded by kermit-v3). `enabled` alone cannot express this: it controls both *whether the fleet runs the tests* and *whether the fleet chases the pin*, and for a frozen project those want opposite answers.

`frozen` is **not one check** — each consumer answers "does this operation still mean anything on a repo nobody will open a PR against?" for itself:

| Consumer | On `frozen: true` | Why |
| -------- | ----------------- | --- |
| `scripts/fleet-gate.sh` | **still sweeps** | it is deployed; a broken test is the thing you want to hear about |
| `monitoring/fleet_dashboard.py` | **still lists**, marked `frozen` | hiding a deployed project is worse than listing it |
| `monitoring/fleet_pins.py` | pin still read, status `frozen`, no staleness delta | `dev-platform-gate` fires only on PRs, and a frozen repo raises none |
| `scripts/check-migration-coverage.sh` | skip, reported as `FROZEN` | the lessons convention prevents *future* concurrent appends; there will be none |
| `scripts/audit-project-drift.sh` | skip, named in the summary | chain drift only matters to someone about to follow the chain |
| `scripts/fleet-install-template.sh` | refuse | it mutates a consumer repo; a fresh pin would gate PRs nobody will raise |

**`enabled: false` wins.** `frozen` qualifies an *enabled* project, so a disabled entry is skipped regardless of it. The combination is contradictory rather than dangerous, and `check-registry.sh` rejects it outright instead of leaving a precedence rule for a reader to remember.

Skips are always **reported, never silent** — a project vanishing from a report with no explanation is indistinguishable from a broken filter.

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
