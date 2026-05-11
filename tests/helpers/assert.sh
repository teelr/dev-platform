# tests/helpers/assert.sh — sourced by per-suite runners.
# Maintains running PASS/FAIL/SKIP counters AND optionally appends each result
# to a shared count file (_GATE_COUNTS_FILE) so the orchestrator can aggregate
# across subshells. Per-suite runners just call record_pass / record_fail /
# record_skip; the orchestrator sets _GATE_COUNTS_FILE and reads the file at
# the end.

: "${PASS_COUNT:=0}"
: "${FAIL_COUNT:=0}"
: "${SKIP_COUNT:=0}"

_gate_log() {
    # Append a one-token line to the orchestrator's count file if set.
    # Silent no-op when running a suite standalone.
    [[ -n "${_GATE_COUNTS_FILE:-}" ]] && echo "$1" >> "${_GATE_COUNTS_FILE}" 2>/dev/null || true
}

record_pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  PASS  $1"
    _gate_log "PASS"
}

record_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  FAIL  $1" >&2
    _gate_log "FAIL"
}

record_skip() {
    SKIP_COUNT=$((SKIP_COUNT + 1))
    echo "  SKIP  $1"
    _gate_log "SKIP"
}

# Assert command exits non-zero (for negative tests).
assert_fails() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        record_fail "${description} (expected non-zero exit, got 0)"
    else
        record_pass "${description}"
    fi
}
