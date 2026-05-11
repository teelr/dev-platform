#!/usr/bin/env bash
# tests/monitoring/run.sh — fixture suite for monitoring/aggregator.py.
#
# For each fixture under tests/monitoring/fixtures/, invokes the aggregator
# with `--log <fixture> --period all --json` and calls a named assertion
# function from `tests/monitoring/asserts.py`. Catches regressions in:
# legacy-format parsing, JSONL parsing, /code retry heuristic, gate_pass_rate
# computation, project filter, malformed-line skipping, degraded-event
# exclusion from pairing.
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 (R3) auto-discovery
# contract — adding a new tests/<suite>/*.sh is enough; no orchestrator edit.
#
# Adding a new check: write a function in `asserts.py` and add a
# `run_check <fixture> <function_name>` line below. The function name is
# the ONLY shell-expanded value, and it must be a valid Python identifier
# (no shell-special chars possible). Assertion code lives in real Python.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

AGG="${REPO}/monitoring/aggregator.py"

# run_check <fixture> <assertion_function> [extra aggregator args...]
#
# Runs the aggregator against the fixture (with `--period all --json`),
# then invokes `<assertion_function>(d)` from asserts.py with the parsed
# JSON output. Surfaces the Python AssertionError message on failure.
run_check() {
    local fixture="$1"
    local fn="$2"
    shift 2
    local extra_args=("$@")

    local out
    if ! out="$(python3 "${AGG}" --log "${HERE}/fixtures/${fixture}" --period all --json "${extra_args[@]}" 2>&1)"; then
        record_fail "monitoring ${fixture}/${fn}: aggregator non-zero exit — ${out:0:200}"
        return
    fi

    # Pipe aggregator JSON into a tiny harness that imports asserts.py and
    # calls the named function. The function name is the only shell-expanded
    # value, and asserts.py's identifiers cannot contain shell-special chars.
    # Capture stderr so AssertionError messages surface in the failure line.
    local err
    if err="$(echo "${out}" | PYTHONPATH="${HERE}" python3 -c "
import sys, json
from asserts import ${fn}
${fn}(json.load(sys.stdin))
" 2>&1)"; then
        record_pass "monitoring ${fixture}/${fn}"
    else
        # err contains the traceback / AssertionError message
        local last_line
        last_line="$(echo "${err}" | tail -1)"
        record_fail "monitoring ${fixture}/${fn}: ${last_line}"
    fi
}

# --- core metric coverage ---
run_check empty.jsonl                empty_log_zero_events
run_check legacy-only.txt            legacy_3_events
run_check mixed-window.jsonl         mixed_gate_50pct
run_check mixed-window.jsonl         mixed_one_tool_pair
run_check mixed-window.jsonl         mixed_code_and_review
run_check two-projects.jsonl         two_projects_unfiltered
run_check code-retry.jsonl           code_retry_1_of_3

# --- coverage additions (Phase 4 /review #3) ---
run_check two-projects.jsonl         two_projects_filtered_to_devplatform  --project dev-platform
run_check malformed-mixed.jsonl      malformed_lines_skipped
run_check degraded-events.jsonl      degraded_events_excluded_from_pairing
