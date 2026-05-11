#!/usr/bin/env python3
"""dev-platform telemetry aggregator.

Reads ~/.claude/dev-platform-telemetry.log (mixed legacy text format +
v0.5 JSONL), computes the four v0.5 Monitoring metrics, emits a markdown
report (or JSON for machine consumption).

Usage:
    python3 monitoring/aggregator.py                       # daily, all projects
    python3 monitoring/aggregator.py --period weekly
    python3 monitoring/aggregator.py --period all
    python3 monitoring/aggregator.py --project dev-platform
    python3 monitoring/aggregator.py --json                # machine-readable
    python3 monitoring/aggregator.py --log /path/to/log    # alternate log path

Exits 0 on success, 1 on missing log file or argparse error.

Schema reference: monitoring/schemas/event-v1.json
Metrics catalog:  monitoring/metrics.md
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterator

LOG_DEFAULT = Path.home() / ".claude" / "dev-platform-telemetry.log"

# Legacy v0.2 format: "<ISO-timestamp> tool=<name>"
LEGACY_RE = re.compile(r"^(\S+)\s+tool=(\S+)$")


@dataclass
class Event:
    """Parsed telemetry event. Mirrors monitoring/schemas/event-v1.json
    but more permissive: missing fields default to None."""
    ts: datetime
    event: str
    project: str
    session_id: str = "?"
    tool: str | None = None
    tool_call_id: str | None = None
    command: str | None = None
    outcome: str | None = None
    pass_count: int | None = None
    fail_count: int | None = None
    duration_s: int | None = None


def parse_line(line: str) -> Event | None:
    """Parse a JSONL or legacy-format line. Returns None on unparseable input."""
    line = line.strip()
    if not line:
        return None

    if line.startswith("{"):
        try:
            d = json.loads(line)
            ts = datetime.fromisoformat(d["ts"])
        except Exception:
            return None
        return Event(
            ts=ts,
            event=d.get("event", "?"),
            project=d.get("project", "?"),
            session_id=d.get("session_id", "?"),
            tool=d.get("tool"),
            tool_call_id=d.get("tool_call_id"),
            command=d.get("command"),
            outcome=d.get("outcome"),
            pass_count=d.get("pass_count"),
            fail_count=d.get("fail_count"),
            duration_s=d.get("duration_s"),
        )

    # Legacy format
    m = LEGACY_RE.match(line)
    if not m:
        return None
    try:
        ts = datetime.fromisoformat(m.group(1))
    except Exception:
        return None
    return Event(
        ts=ts,
        event="tool_use_end",
        project="dev-platform",   # legacy was always dev-platform context
        tool=m.group(2),
    )


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
    """Return events in [since, until] window, optionally filtered by project."""
    out: list[Event] = []
    for ev in events:
        # Some legacy datetimes may be naive; normalize to local tz.
        ts = ev.ts if ev.ts.tzinfo else ev.ts.replace(tzinfo=since.tzinfo)
        if ts < since or ts > until:
            continue
        if project is not None and ev.project != project:
            continue
        out.append(ev)
    return out


# --- Metric computations -------------------------------------------------

def metric_gate_pass_rate(events: list[Event]) -> dict:
    """gate_pass_rate = count(gate_run where outcome=pass) / count(gate_run)."""
    gates = [e for e in events if e.event == "gate_run"]
    if not gates:
        return {"count": 0, "pass": 0, "fail": 0, "rate": None}
    passed = sum(1 for e in gates if e.outcome == "pass")
    return {
        "count": len(gates),
        "pass": passed,
        "fail": len(gates) - passed,
        "rate": passed / len(gates),
    }


def metric_code_retries(events: list[Event]) -> dict:
    """A 'retry' is a /code invocation immediately followed by another /code in
    the same session without an intervening /docs."""
    by_session: dict[str, list[Event]] = defaultdict(list)
    for e in events:
        if e.event == "user_prompt" and e.command in {"/code", "/docs"}:
            by_session[e.session_id].append(e)
    code_count = 0
    retry_count = 0
    for evs in by_session.values():
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
    return {
        "count": code_count,
        "retries": retry_count,
        "avg": retry_count / code_count if code_count else None,
    }


def metric_events_per_project(events: list[Event]) -> dict[str, int]:
    """Count of all events in the window, grouped by `project` field.

    Returned as a plain dict; rendering layer decides how to display it
    (per-project breakdown table in markdown; `events_by_project` key in JSON).
    """
    by_project: dict[str, int] = defaultdict(int)
    for e in events:
        by_project[e.project] += 1
    return dict(by_project)


def metric_review_catch_rate(events: list[Event]) -> dict:
    """Count of /review invocations only. True catch-rate (issues per review)
    requires /review skill instrumentation; deferred."""
    reviews = [e for e in events if e.event == "user_prompt" and e.command == "/review"]
    return {
        "count": len(reviews),
        "catch_rate": None,
        "note": "Catch-rate computation deferred — /review skill does not yet "
                "emit issue counts. Tracked in roadmap.",
    }


def metric_tool_duration(events: list[Event]) -> dict:
    """Pair tool_use_start with tool_use_end via tool_call_id; compute duration."""
    starts: dict[str, datetime] = {}
    durations: list[tuple[str, int]] = []
    for e in events:
        if e.event == "tool_use_start" and e.tool_call_id and e.tool_call_id != "?":
            starts[e.tool_call_id] = e.ts
        elif e.event == "tool_use_end" and e.tool_call_id and e.tool_call_id != "?":
            if e.tool_call_id in starts:
                start_ts = starts.pop(e.tool_call_id)
                end_ts = e.ts if e.ts.tzinfo else e.ts.replace(tzinfo=start_ts.tzinfo)
                ms = int((end_ts - start_ts).total_seconds() * 1000)
                if ms >= 0:
                    durations.append((e.tool or "?", ms))
    if not durations:
        return {"count": 0, "avg_ms": None, "by_tool": {}}
    by_tool: dict[str, list[int]] = defaultdict(list)
    for tool, ms in durations:
        by_tool[tool].append(ms)
    avg_overall = sum(ms for _, ms in durations) / len(durations)
    by_tool_avg = {t: int(sum(v) / len(v)) for t, v in by_tool.items()}
    by_tool_top = dict(sorted(by_tool_avg.items(), key=lambda kv: -kv[1])[:5])
    return {
        "count": len(durations),
        "avg_ms": int(avg_overall),
        "by_tool": by_tool_top,
    }


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
    by_project = metric_events_per_project(events)

    lines = []
    title = "dev-platform telemetry report"
    if project_filter:
        title += f" — project={project_filter}"
    lines.append(f"=== {title} ===")
    lines.append(f"Window: {since.date()} → {until.date()}   "
                 f"Events: {len(events)} total")
    lines.append("")

    g = metrics["gate"]
    if g["count"]:
        lines.append(f"Gate pass rate:        {g['pass']}/{g['count']}  "
                     f"({int(g['rate']*100)}%)")
    else:
        lines.append("Gate pass rate:        no gate runs in window")

    c = metrics["code"]
    if c["count"]:
        avg = f"{c['avg']:.2f}" if c['avg'] is not None else "n/a"
        lines.append(f"/code retry counts:    avg {avg}  "
                     f"({c['count']} invocations, "
                     f"{c['retries']} retries)")
    else:
        lines.append("/code retry counts:    no /code in window")

    r = metrics["review"]
    if r["count"]:
        lines.append(f"/review count:         {r['count']} invocations  "
                     "(catch-rate computation deferred)")
    else:
        lines.append("/review count:         no /review in window")

    t = metrics["tools"]
    if t["count"]:
        top_parts = ", ".join(f"{k}={v}ms" for k, v in t["by_tool"].items())
        lines.append(f"Tool exec time avg:    {t['avg_ms']}ms  "
                     f"({t['count']} paired calls)")
        lines.append(f"  top tools by avg:    {top_parts}")
    else:
        lines.append("Tool exec time avg:    no paired tool events in window")

    if not project_filter:
        lines.append("")
        lines.append("Per-project event breakdown:")
        for proj in sorted(by_project, key=lambda p: -by_project[p]):
            lines.append(f"  {proj:20s} {by_project[proj]:5d} events")

    return "\n".join(lines) + "\n"


def metrics_json(window: tuple[datetime, datetime], events: list[Event],
                 project_filter: str | None) -> dict:
    since, until = window
    return {
        "window": {"since": since.isoformat(), "until": until.isoformat()},
        "project": project_filter,
        "event_count": len(events),
        "events_by_project": metric_events_per_project(events),
        "metrics": {
            "gate": metric_gate_pass_rate(events),
            "code": metric_code_retries(events),
            "review": metric_review_catch_rate(events),
            "tools": metric_tool_duration(events),
        },
    }


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="dev-platform telemetry aggregator (v0.5 Monitoring).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--period", choices=["daily", "weekly", "all"], default="daily",
                   help="Reporting window (default: daily)")
    p.add_argument("--project", default=None,
                   help="Filter to a single project (omit for all)")
    p.add_argument("--json", action="store_true",
                   help="Emit machine-readable JSON instead of markdown")
    p.add_argument("--log", default=str(LOG_DEFAULT),
                   help=f"Telemetry log path (default: {LOG_DEFAULT})")
    return p.parse_args()


def main() -> int:
    args = parse_args()

    log_path = Path(args.log)
    if not log_path.exists():
        print(f"ERROR: telemetry log not found at {log_path}", file=sys.stderr)
        return 1

    now = datetime.now(timezone.utc).astimezone()
    if args.period == "daily":
        since = now.replace(hour=0, minute=0, second=0, microsecond=0)
    elif args.period == "weekly":
        since = now - timedelta(days=7)
    else:
        since = datetime.min.replace(tzinfo=now.tzinfo)

    events = filter_window(load_events(log_path), since, now, args.project)

    if args.json:
        print(json.dumps(metrics_json((since, now), events, args.project),
                         indent=2, default=str))
    else:
        print(render_markdown((since, now), events, args.project))
    return 0


if __name__ == "__main__":
    sys.exit(main())
