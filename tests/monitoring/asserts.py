"""Named assertion functions for the monitoring test suite.

Each function takes a dict (the aggregator's --json output) and either
returns silently on success or raises AssertionError on failure.

The bash runner imports this module via `python3 -c` and calls the named
function by argv. This eliminates shell-variable interpolation of
assertion code — the only shell-expanded var is the function NAME (an
identifier, can't contain shell-special characters), and the function
body lives in real Python source where shell rules don't apply.

Adding a new check:
1. Write a new function below that takes `d` (the parsed JSON dict)
2. Add a `run_check <fixture> <function_name>` line in run.sh

That's it — no heredoc gymnastics, no shell escaping concerns.
"""


def empty_log_zero_events(d):
    assert d["event_count"] == 0, f'expected 0 events; got {d["event_count"]}'


def legacy_3_events(d):
    assert d["event_count"] == 3, f'expected 3 events; got {d["event_count"]}'
    assert d["events_by_project"].get("dev-platform") == 3, \
        f'expected dev-platform=3; got {d["events_by_project"]}'
    # Legacy lines have no tool_call_id, so no pairs possible
    assert d["metrics"]["tools"]["count"] == 0, \
        f'legacy has no tool pairs; got tools.count={d["metrics"]["tools"]["count"]}'


def mixed_gate_50pct(d):
    g = d["metrics"]["gate"]
    assert g["count"] == 2, f'gate count: {g}'
    assert g["pass"] == 1 and g["fail"] == 1, f'gate pass/fail: {g}'
    assert abs(g["rate"] - 0.5) < 1e-9, f'gate rate not 0.5: {g["rate"]}'


def mixed_one_tool_pair(d):
    t = d["metrics"]["tools"]
    assert t["count"] == 1, f'expected 1 tool pair; got {t}'


def mixed_code_and_review(d):
    c = d["metrics"]["code"]
    r = d["metrics"]["review"]
    assert c["count"] == 1, f'/code count: {c}'
    assert r["count"] == 1, f'/review count: {r}'


def two_projects_unfiltered(d):
    p = d["events_by_project"]
    assert p.get("dev-platform") == 2, f'dev-platform count: {p}'
    assert p.get("kermit") == 3, f'kermit count: {p}'


def two_projects_filtered_to_devplatform(d):
    # Run with --project dev-platform; expect only dev-platform's 2 events
    assert d["event_count"] == 2, f'expected 2 events with project filter; got {d["event_count"]}'
    assert d["project"] == "dev-platform", f'project filter not applied: {d.get("project")}'
    # And the filter should narrow events_by_project too
    p = d["events_by_project"]
    assert "kermit" not in p, f'kermit should be excluded; got {p}'


def code_retry_1_of_3(d):
    c = d["metrics"]["code"]
    assert c["count"] == 3, f'/code count: {c}'
    # Sequence is /code, /code, /docs, /code → 1st→2nd is a retry, 3rd is fresh post-/docs
    assert c["retries"] == 1, f'expected 1 retry; got {c}'


def malformed_lines_skipped(d):
    # Fixture has 2 valid JSONL events + 2 invalid lines (bad JSON, missing fields).
    # Only the 2 valid events should be counted.
    assert d["event_count"] == 2, \
        f'expected 2 events (invalid lines silently skipped); got {d["event_count"]}'


def degraded_events_excluded_from_pairing(d):
    # Fixture has 2 tool pairs: one with real tool_call_id, one with "?"
    # The aggregator pairs only the real one; the "?" pair is excluded.
    t = d["metrics"]["tools"]
    assert t["count"] == 1, \
        f'expected 1 pair (degraded "?" tcid excluded); got tools.count={t["count"]}'
    # Total event count should still include all 4 events
    assert d["event_count"] == 4, \
        f'expected 4 events total (degraded events still counted); got {d["event_count"]}'
