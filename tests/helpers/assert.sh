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

# deploy_source_repo <this-suite's-REPO> — the repo path install.sh deploys FROM.
#
# Since v1.25 the live ~/.claude deployment always tracks the MAIN checkout:
# install.sh, verify.sh and uninstall.sh all resolve there via git-common-dir,
# whichever worktree invokes them. So a suite asserting on a symlink target must
# compare against the main checkout, NOT against its own ${REPO}. Those are the
# same path from the main checkout and different paths from a worktree — which
# is why four suites passed on main and failed the first time the gate ran from
# a worktree against a non-docs diff.
#
# One shared helper rather than four inline copies, per the Derivation Sweep
# rule in CLAUDE.md. Falls back to the argument outside a git repo.
deploy_source_repo() {
    local self="$1" common common_abs
    if common="$(cd "${self}" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)"; then
        if common_abs="$(cd "${self}" && cd "${common}" 2>/dev/null && pwd -P)"; then
            dirname "${common_abs}"
            return 0
        fi
    fi
    printf '%s' "${self}"
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
