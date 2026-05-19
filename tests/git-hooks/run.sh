#!/usr/bin/env bash
# tests/git-hooks/run.sh — fixture suite for shell/git-hooks/pre-commit.
# Five tests covering the cross-product of (no-gate / passing / failing) ×
# (default env / SKIP_GATE_FAST=1), plus install integration.
#
# Per tasks/lessons.md (2026-05-16): exit-code capture uses two-line pattern,
# never `cmd || true; check $?` (always yields $? = 0).
# Per tasks/lessons.md (2026-05-11 negative-test rule): assertions check both
# exit code AND specific stderr substring — not exit-code-only.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

HOOK="${REPO}/shell/git-hooks/pre-commit"
PASSING_FIXTURE="${HERE}/fixtures/passing-gate.sh"
FAILING_FIXTURE="${HERE}/fixtures/failing-gate.sh"

# Each test creates its own tmpdir + trap so failures still clean up.

# Test 1 — no scripts/gate_fast.sh: hook exits 0 (no-op).
test_no_gate() {
    local tmp; tmp="$(mktemp -d)"
    trap "rm -rf '${tmp}'" RETURN
    (cd "${tmp}" && git init -q)
    local out rc
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"
    rc=$?
    if [[ ${rc} -eq 0 ]]; then
        record_pass "no-gate no-op (exit 0)"
    else
        record_fail "no-gate no-op: expected exit 0, got ${rc}; out: ${out}"
    fi
}

# Test 2 — passing gate: hook exits 0.
test_passing_gate() {
    local tmp; tmp="$(mktemp -d)"
    trap "rm -rf '${tmp}'" RETURN
    (cd "${tmp}" && git init -q)
    mkdir -p "${tmp}/scripts"
    cp "${PASSING_FIXTURE}" "${tmp}/scripts/gate_fast.sh"
    chmod +x "${tmp}/scripts/gate_fast.sh"
    local out rc
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"
    rc=$?
    if [[ ${rc} -eq 0 ]]; then
        record_pass "passing gate (exit 0)"
    else
        record_fail "passing gate: expected exit 0, got ${rc}; out: ${out}"
    fi
}

# Test 3 — failing gate: hook exits 1 with refusal message.
test_failing_gate() {
    local tmp; tmp="$(mktemp -d)"
    trap "rm -rf '${tmp}'" RETURN
    (cd "${tmp}" && git init -q)
    mkdir -p "${tmp}/scripts"
    cp "${FAILING_FIXTURE}" "${tmp}/scripts/gate_fast.sh"
    chmod +x "${tmp}/scripts/gate_fast.sh"
    local out rc
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"
    rc=$?
    if [[ ${rc} -ne 1 ]]; then
        record_fail "failing gate: expected exit 1, got ${rc}; out: ${out}"
        return
    fi
    if [[ "${out}" == *"GATE FAST: FAIL"* ]]; then
        record_pass "failing gate refuses with FAIL message (exit 1)"
    else
        record_fail "failing gate exited 1 but missing 'GATE FAST: FAIL' message; out: ${out}"
    fi
}

# Test 4 — SKIP_GATE_FAST=1 bypasses even when gate would fail.
test_bypass_env_var() {
    local tmp; tmp="$(mktemp -d)"
    trap "rm -rf '${tmp}'" RETURN
    (cd "${tmp}" && git init -q)
    mkdir -p "${tmp}/scripts"
    cp "${FAILING_FIXTURE}" "${tmp}/scripts/gate_fast.sh"
    chmod +x "${tmp}/scripts/gate_fast.sh"
    local out rc
    out="$(cd "${tmp}" && SKIP_GATE_FAST=1 bash "${HOOK}" 2>&1)"
    rc=$?
    if [[ ${rc} -ne 0 ]]; then
        record_fail "SKIP_GATE_FAST=1 bypass: expected exit 0, got ${rc}; out: ${out}"
        return
    fi
    if [[ "${out}" == *"bypassing gate"* ]]; then
        record_pass "SKIP_GATE_FAST=1 bypasses failing gate (exit 0)"
    else
        record_fail "bypass exited 0 but missing 'bypassing gate' message; out: ${out}"
    fi
}

# Test 5 — install integration: install.sh git-hooks symlinks the hook
# into <tmpdir>/.claude/git-hooks/pre-commit pointing back at the tracked
# source. Uses HOME override (not actual $HOME modification).
test_install_integration() {
    local tmp; tmp="$(mktemp -d)"
    trap "rm -rf '${tmp}'" RETURN
    local out rc
    out="$(HOME="${tmp}" bash "${REPO}/scripts/install.sh" git-hooks 2>&1)"
    rc=$?
    if [[ ${rc} -ne 0 ]]; then
        record_fail "install git-hooks: expected exit 0, got ${rc}; out: ${out}"
        return
    fi
    local deployed="${tmp}/.claude/git-hooks/pre-commit"
    if [[ ! -L "${deployed}" ]]; then
        record_fail "install git-hooks: symlink ${deployed} not created"
        return
    fi
    local resolved; resolved="$(readlink -f "${deployed}")"
    if [[ "${resolved}" != "${HOOK}" ]]; then
        record_fail "install git-hooks: symlink resolves to ${resolved}, expected ${HOOK}"
        return
    fi
    record_pass "install git-hooks: symlink at ${deployed#${tmp}} → tracked source"
}

test_no_gate
test_passing_gate
test_failing_gate
test_bypass_env_var
test_install_integration
