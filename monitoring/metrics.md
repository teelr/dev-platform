# dev-platform Metrics Catalog

Every metric the aggregator computes, with definition, source events, and
known limitations. v0.7 (Team Enablement) and v0.8 (Cross-project
orchestration) build on this catalog — new metrics get added here first.

- **Aggregator:** `monitoring/aggregator.py`
- **CLI:** `scripts/report.sh`
- **Schema:** `monitoring/schemas/event-v1.json`
- **Log file:** `~/.claude/dev-platform-telemetry.log`

## gate_pass_rate

**Definition:** `count(gate_run where outcome="pass") / count(gate_run)`

**Source events:** `gate_run` (emitted by `scripts/gate_fast.sh` at end-of-run).

**Computation:** Counts every `gate_run` event in the window. Pass-rate
is the fraction whose `outcome` field is `"pass"`.

**Known limitations:**

- Only counts the dev-platform `gate_fast.sh` orchestrator. Other projects'
  gate runs are not captured until those projects' gate scripts also emit
  `gate_run` events into the same log (tracked as a v0.7 follow-on).
- The emission is failure-tolerant (`|| true` guard in `gate_fast.sh`), so
  if Python is broken on the host, a gate run won't be recorded. This is
  a silent data-loss case — gate's job is the gate, not the telemetry.

## code_retry_rate

**Definition:** A "retry" is a `/code` invocation followed by another `/code`
in the same session without an intervening `/docs`. The metric reports
total `/code` count + retry count + average retries per `/code` invocation.

**Source events:** `user_prompt` with `command="/code"` or `command="/docs"`.

**Computation:** Group `user_prompt` events by `session_id`, sort by
timestamp, walk forward — each `/code` that follows another `/code`
without a `/docs` in between counts as a retry.

**Known limitations:**

- Doesn't distinguish "retry because `/test` failed" from "user re-invoked
  `/code` for a separate change in the same session." Hard to fix without
  also tracking `/test` outcomes and intent — deferred to a future spec.
- The heuristic uses `/docs` as the "natural end" of a `/code` phase.
  `/test`, `/review`, `/gate` as alternative terminators are deferred.
- Sessions without any `/code` invocations contribute nothing (correct
  behavior — but the denominator can be very small early in adoption).

## review_count (catch-rate deferred)

**Definition:** Count of `/review` invocations in the window.

**Source events:** `user_prompt` with `command="/review"`.

**Computation:** Simple count.

**Known limitations:**

- True catch-rate (issues raised per review) requires the `/review` skill
  itself to emit a structured "issues found: N" event after each run.
  Not yet implemented — v0.5 ships count-only. Refining to true catch-rate
  is its own future spec (touches the `/review` skill).

## tool_duration_ms

**Definition:** Per-tool average milliseconds between `tool_use_start` and
`tool_use_end`, paired by `tool_call_id`. Also reports the top-5 tools
by average duration.

**Source events:** `tool_use_start`, `tool_use_end`.

**Computation:** For each `tool_use_start`, record the timestamp keyed by
`tool_call_id`. For each `tool_use_end` with the same `tool_call_id`,
compute `end.ts - start.ts` in milliseconds. Skip unpaired events.
Average across all paired durations; group by tool name for the top-5.

**Known limitations:**

- Excludes legacy lines (pre-v0.5) which have no `tool_use_start` event —
  legacy `<ts> tool=<name>` rows are interpreted as `tool_use_end` with no
  pair candidate. Aggregator silently drops them from the duration calc.
- Pairing is by `tool_call_id` (Claude Code's `tool_use_id`). If the start
  event is missing (e.g., session crashed mid-tool, or pre-hook failed),
  the end event is silently dropped from duration calc — but still counted
  in `event_count`.
- Tools with `tool_call_id="?"` (degraded events from fallback emissions)
  are excluded from pairing — they're treated as ignorable noise rather
  than valid data points.

## events_per_project

**Definition:** Count of all events in the window, grouped by `project`
field. Surfaces where the user spent time.

**Source events:** All.

**Computation:** `defaultdict(int)` incremented per event.

**Known limitations:**

- Project is derived from `cwd` at hook fire time. A session that starts
  in `dev-platform` and `cd`s into `projects/X` mid-session will tag later
  events as `project=X`. This is intentional — the metric reflects where
  work happened, not where the session began. Documented in
  `monitoring/README.md > Project tagging`.

## Adding a new metric

1. Add a `metric_<name>(events)` function in `monitoring/aggregator.py`
2. Wire it into both `render_markdown()` and `metrics_json()`
3. Document it here with the same four sections (Definition / Source
   events / Computation / Known limitations)
4. Add a test fixture under `tests/monitoring/fixtures/` (Phase 4 ships
   the test suite; until then, smoke-test manually)

Don't add metrics without documenting limitations honestly — the Honesty
rule (`dev/CLAUDE.md`) applies. Every metric here has caveats; future
metrics will too.
