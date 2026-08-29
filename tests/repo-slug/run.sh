#!/usr/bin/env bash
# tests/repo-slug/run.sh — regression suite for scripts/lib/repo_slug.py.
#
# Sourced contract: uses record_pass/record_fail from tests/helpers/assert.sh;
# never exit-s (the orchestrator owns the exit code).
#
# This is the unit-level guard for the one parse three scripts now share. The
# per-script suites (tests/version-collision/, tests/phase-milestones/) prove
# each caller actually REACHES this parse; this one pins what it returns.
#
# Driven through the CLI entry point rather than a Python import, so the module
# and its __main__ wrapper are both covered — the shell caller
# (check-phase-milestones.sh) depends on the CLI form.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
SLUG_PY="${REPO}/scripts/lib/repo_slug.py"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

# expect_slug <url> <expected> <label>
expect_slug() {
    local url="$1" expected="$2" label="$3" got rc
    got="$(python3 "${SLUG_PY}" "${url}" 2>/dev/null)"; rc=$?
    if [[ ${rc} -eq 0 && "${got}" == "${expected}" ]]; then
        record_pass "repo-slug: ${label}"
    else
        record_fail "repo-slug: ${label} — got '${got}' (rc=${rc}), expected '${expected}'"
    fi
}

# expect_none <url> <label> — no stdout, exit 1.
expect_none() {
    local url="$1" label="$2" got rc
    got="$(python3 "${SLUG_PY}" "${url}" 2>/dev/null)"; rc=$?
    if [[ ${rc} -eq 1 && -z "${got}" ]]; then
        record_pass "repo-slug: ${label}"
    else
        record_fail "repo-slug: ${label} — got '${got}' (rc=${rc}), expected no output and rc=1"
    fi
}

# --- shapes that already worked before v1.21: must not regress ---------------
expect_slug 'git@github.com:owner/repo.git'           'owner/repo' 'scp-style ssh URL'
expect_slug 'https://github.com/owner/repo.git'       'owner/repo' 'https URL with .git'
expect_slug 'https://github.com/owner/repo'           'owner/repo' 'https URL without .git'
expect_slug 'ssh://git@github.com/owner/repo.git'     'owner/repo' 'ssh:// URL'
expect_slug 'https://user@github.com/owner/repo.git'  'owner/repo' 'https URL with userinfo'

# --- v1.21 regressions: both returned None before this change ----------------
# Issue #77 — the SSH host-alias shape dev-platform's own multi-account setup
# prescribes. This is the bug that blocked SQRL's /plan entirely.
expect_slug 'git@github-teelr129:Osigin-LLC/SQRL.git' 'Osigin-LLC/SQRL' 'SSH host-alias remote (issue #77)'
# Second latent bug found while writing the spec: the old ([^/.]+?) group
# excluded dots from the repo name, so a dotted repo name never parsed.
expect_slug 'git@github.com:owner/my.repo.git'        'owner/my.repo'  'dotted repo name'

# --- host-agnostic by construction -------------------------------------------
expect_slug 'git@git.corp.example:team/tool.git'      'team/tool'  'non-github host still parses'
expect_slug 'https://github.com/owner/repo/'          'owner/repo' 'trailing slash tolerated'

# --- unparseable input --------------------------------------------------------
expect_none 'not-a-url' 'single token is unparseable'
expect_none ''          'empty string is unparseable'
# Relative remotes have no segment before their only slash. tests/version-collision
# relies on this exact case to reach the degraded-coverage path with an origin
# git can still fetch from.
expect_none '../origin.git' 'relative origin path is unparseable'

# --- CLI contract -------------------------------------------------------------
if [[ -x "${SLUG_PY}" ]]; then
    record_pass "repo-slug: script is executable"
else
    record_fail "repo-slug: script is not executable"
fi

usage_out="$(python3 "${SLUG_PY}" 2>&1)"; usage_rc=$?
if [[ ${usage_rc} -eq 2 ]] && grep -q "usage:" <<<"${usage_out}"; then
    record_pass "repo-slug: no argument prints usage and exits 2"
else
    record_fail "repo-slug: no-argument handling (rc=${usage_rc}, out: ${usage_out})"
fi
